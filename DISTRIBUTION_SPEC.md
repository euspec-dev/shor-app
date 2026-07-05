# SHOR. 写真配信ロジック 実装仕様

SHOR.（写真を1日1通、匿名で見知らぬ誰かに届けるアプリ）のバックエンドに、写真の配信（マッチング）ロジックを実装してください。この文書はその要件と、配信優先度のスコア式を定義します。

## 0. 前提となるサービスの性質

- ユーザーは自分の写真を「海に流し」、翌日「合計何秒間、誰かに現像（閲覧）されたか」だけを知らされる。誰に・何人に見られたかは表示しない。
- 閲覧者は「流れ着いた1枚」を長押しで現像して見る。一度見た写真は二度と表示されない。
- 評価・いいね・フォロワーは存在しない。パーソナライズ（嗜好推薦）は行わない。「偶然流れ着いた」手触りが核。

この配信ロジックの**唯一の最適化目標**は「できるだけ多くの投稿を、期限内に、最低1人には届ける」こと。嗜好の一致度は目標にしない。

## 1. 需給の前提（なぜこの設計か）

1日のアクティブユーザーを N、投稿率を p とすると：
- 供給 = pN 枚/日（投稿は1日1通）
- 閲覧需要 = (1 + p)N 回/日（無料枠1 + 投稿者の追加枠1）

供給 < 需要 が常に成立し、需要は供給の約3〜4倍になる。したがって**1枚の写真は複数人に配る必要がある**。ただしこれは裏側の仕組みであり、ユーザーには一切見せない（後述）。

## 2. 中心概念：到達人数 K（不可視・可変）

- 1枚の写真が配信されうる**最大人数を K** とする。
- K は固定値ではなく、**サーバ側の需給で動的に調整する内部パラメータ**。ユーザーには表示しない。
- 初期値 `K_DEFAULT = 3`。運用で `K_MIN = 1` 〜 `K_MAX = 5` の範囲で調整可能にする。
- K の調整方針（バッチまたはリアルタイムで再計算）：
  - 直近24hの「閲覧需要 / 配信可能供給」比 = R を算出。
  - `K = clamp(round(R), K_MIN, K_MAX)` を目安に更新。
  - 供給が需要を上回る（R < 1）局面では K を下げ、希少性を高める。

**重要**：K を変えても閲覧者・投稿者の画面表示は一切変わらない。体験上の「1対1（自分だけに届いた1枚）」は完全に維持する。

## 3. データモデル

既存の想定エンティティに、配信管理用のフィールドを追加する。

```
User
  id
  createdAt
  lastActiveAt
  hasPostedEver: bool        # 初投稿判定用

Post
  id
  authorId                   # 翌日結果確認後に null 化して匿名化（既存仕様）
  imageUrl
  message
  createdAt
  totalViewedSeconds         # 閲覧秒数の累計（複数閲覧を合算）
  isOpened: bool             # 1人以上に見られたか（未到達判定に使用）
  isResultConfirmed: bool
  # --- 配信管理用（追加）---
  viewCount: int             # これまでに配信・閲覧された人数
  maxReach: int              # この写真の到達上限（配信開始時の K を焼き込む）
  distributableUntil: datetime  # 配信対象から外れる時刻（= createdAt + 表示期限）
  isFirstPostOfAuthor: bool  # 投稿者の初投稿か（コールドスタート優先用）
  status: enum(active, exhausted, expired)  # 配信状態

ViewHistory
  id
  viewerId
  postId
  viewedSeconds
  viewedAt
```

## 4. 投稿制限

- **投稿は1日1通まで**（ユーザーのローカル日付基準）。
- 投稿時に以下を設定：
  - `maxReach = 現在の K`
  - `distributableUntil = createdAt + DISPLAY_TTL`（`DISPLAY_TTL = 48時間`、初期値 `60h`）
  - `isFirstPostOfAuthor = !user.hasPostedEver`、その後 `user.hasPostedEver = true`
  - `viewCount = 0`, `isOpened = false`, `status = active`

注：`distributableUntil`（配信から外れる時刻）と、ストレージの30日完全消去（プライバシー要件）は**別物**。前者は「もう新規に配らない」、後者は「データを物理削除する」。両方を独立に持つ。

## 5. 閲覧枠（視聴権）

閲覧者が1日に見られる枚数は最大2枚：
- **無料枠**：1日1回。投稿しなくても付与。
- **投稿枠**：その日に投稿すると +1（複数投稿しても上限1）。

どちらの入口から閲覧しても、残っている枠を消費（無料枠を優先消費し、無ければ投稿枠）。※この視聴権ロジックはフロントに実装済み。サーバ側でも同じ制約を正とすること。

## 6. 配信アルゴリズム（1回の閲覧リクエストで1枚を選ぶ）

閲覧者 `viewer` が「写真を見る」を実行したときの処理：

### 6.1 候補の足切り（ハードフィルタ）

以下を**すべて**満たす Post のみ候補とする：
1. `status == active`
2. `now < distributableUntil`（期限内）
3. `viewCount < maxReach`（到達上限に未達）
4. `authorId != viewer.id`（自分の投稿は除外）
5. `viewer` がその Post を過去に見ていない（ViewHistory で判定）

候補が0件なら、シード写真（運営提供の在庫）にフォールバック。それも無ければ「今は流れ着いていない」旨を返す。

### 6.2 スコアリングと選択

候補それぞれにスコアを付け、**スコアを重みとした加重ランダム抽出**で1枚選ぶ（決定論的な最大値選択にしない。「偶然」の手触りを残すため）。

**スコア式：**

```
score(post) =
      W_UNREACHED * unreached(post)      # まだ誰にも届いていない
    + W_FIRSTPOST * firstPost(post)      # 投稿者の初投稿
    + W_URGENCY   * urgency(post)        # 期限の近さ
    + W_UNDERFED  * underfed(post)       # 到達が上限に対して不足
    + BASE                               # 全候補に最低限の当選機会

where
  unreached(post) = (post.viewCount == 0) ? 1 : 0
  firstPost(post) = post.isFirstPostOfAuthor ? 1 : 0
  urgency(post)   = clamp(1 - remaining(post) / DISPLAY_TTL, 0, 1)
                    # remaining = distributableUntil - now（秒）。期限が近いほど1に近づく
  underfed(post)  = (maxReach - viewCount) / maxReach   # 未到達枠の割合。0〜1
  BASE            = 0.1
```

**重み（初期値。運用でチューニング可能に）：**

```
W_UNREACHED = 3.0    # 全投稿に最低1人を届ける保証を最優先
W_FIRSTPOST = 2.0    # 初投稿者のリテンション（翌日結果0秒を防ぐ）
W_URGENCY   = 1.5    # 期限切れ前に配り切る
W_UNDERFED  = 1.0    # 到達を均す
```

この設計の意図：
- 未到達（viewCount==0）の写真が圧倒的に選ばれやすく、**まず全投稿の1人目を確保**してから2人目以降を配る。
- 初投稿は二重に優先（unreached かつ firstPost）され、初投稿者が翌日「0秒」を受け取る事態をほぼ防ぐ。
- 加重ランダムなので、優先度が低い写真も BASE により時々選ばれ、機械的な均一さを避ける。

### 6.3 選択後の更新（トランザクション内で）

```
選択した post について：
  INSERT ViewHistory(viewerId=viewer.id, postId=post.id, viewedSeconds=0, viewedAt=now)
      # viewedSeconds は現像完了後にクライアントから確定値で更新
  post.viewCount += 1
  post.isOpened = true
  if post.viewCount >= post.maxReach:
      post.status = exhausted
  viewer の視聴権を1つ消費
```

同時アクセスで `viewCount` が `maxReach` を超えないよう、**行ロックまたは楽観ロック**で `viewCount < maxReach` を再チェックしてからインクリメントすること。

## 7. 閲覧秒数の記録

- 現像インタラクション（長押し5秒＋鑑賞）の総保持秒数をクライアントが計測し、閲覧終了時に該当 ViewHistory の `viewedSeconds` を確定更新。
- `Post.totalViewedSeconds` は、その Post に紐づく全 ViewHistory の `viewedSeconds` の合計（＝複数閲覧者ぶんを合算）。
- 翌日、投稿者にはこの `totalViewedSeconds` のみ返す（人数は返さない）。

## 8. 期限バッチ（定期実行）

一定間隔（例：10分ごと）で：
```
for post where status == active and now >= distributableUntil:
    post.status = expired
```
※ `expired` でも `totalViewedSeconds` は保持し、翌日の結果通知に使う。物理削除は別途30日ルールで行う。

## 9. コールドスタート対策（明示的に実装すること）

1. **閲覧者側**：候補0件時は必ずシード写真にフォールバックし、初回ユーザーを空振りさせない。新規ユーザーには `viewCount` の少ない候補を優先的に回す（`underfed` が自然に効くが、新規判定で追加ブーストしてよい）。
2. **投稿者側**：`isFirstPostOfAuthor` の写真はスコアで最優先。初投稿の1人目到達を当日中にほぼ保証する。
3. **サービス全体（ローンチ初期）**：運営シード写真を N 枚投入。K を高め（初期は供給が薄いため）に設定して少ない在庫で多くの閲覧を支える。

## 10. パラメータ一覧（設定ファイルに切り出す）

```
K_DEFAULT   = 3
K_MIN       = 1
K_MAX       = 5
DISPLAY_TTL = 60h          # 表示（配信）期限
STORAGE_TTL = 30d          # 物理削除（プライバシー要件・別系統）
DAILY_POST_LIMIT = 1
FREE_VIEW_PER_DAY = 1
POST_VIEW_BONUS   = 1

# スコア重み
W_UNREACHED = 3.0
W_FIRSTPOST = 2.0
W_URGENCY   = 1.5
W_UNDERFED  = 1.0
BASE        = 0.1
```

## 11. 実装の受け入れ条件（テストで担保）

- [ ] 自分の投稿・既視聴の写真が候補に出ない
- [ ] `viewCount` が `maxReach` を超えない（並行アクセス下でも）
- [ ] 未到達（viewCount==0）の写真が、到達済みより有意に高頻度で選ばれる
- [ ] 初投稿の写真が投稿当日に高確率で1人目に到達する
- [ ] 期限（distributableUntil）を過ぎた写真が配信されない
- [ ] 候補0件でシード写真にフォールバックする
- [ ] `totalViewedSeconds` が全 ViewHistory の合計と一致する
- [ ] 投稿は1日1通に制限される
- [ ] 閲覧は1日最大2枚（無料1＋投稿1）に制限される
- [ ] K を変更しても、閲覧者・投稿者に見える情報（秒数のみ）が変わらない

## 12. スコープ外（今回実装しない）

- 嗜好ベースの推薦・パーソナライズ
- 通報・モデレーション（別途）
- 認証（MVPは LocalStorage の UUID を User ID とする既存方式のまま）
