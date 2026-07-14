# 配信ロジック（マッチング）の仕様

`DISTRIBUTION_SPEC.md` を元に実装した、投稿がどの閲覧者にどう届くかの仕組み。
SQL側の実体は次の4つのマイグレーションファイル。上から順に実行されている。

1. `supabase_migration.sql` — 配信管理カラム・設定テーブル・`select_drift`（後に分割）
2. `supabase_migration_002_defer_reservation.sql` — `select_drift` を
   `peek_drift` / `confirm_drift` の2段階に分割
3. `supabase_migration_003_storage_delete_policy.sql` — ストレージDELETEの
   anon許可
4. `supabase_migration_004_storage_delete_cascade.sql` — ストレージ削除と
   `posts`行の連動

閲覧権（1日に何回見られるか）については [view-grants.md](view-grants.md) 参照。
本ドキュメントは「どの投稿が選ばれるか」「どこまで配られたら打ち止めか」を扱う。

## 目的

1枚の写真を「気の合う誰かに」ではなく、**期限内にできるだけ多くの投稿を
最低1人には届ける**ことだけを最適化する。好み・傾向によるパーソナライズは
一切行わない（`peek_drift`の重み付けは投稿の"新しさ・不利さ"だけを見ており、
閲覧者の過去の好みは見ていない）。

## 到達人数 K（`max_reach`）

1枚の投稿が配られる最大人数。現状は`distribution_config.k_default`（既定3）を
そのまま`posts.max_reach`のデフォルト値として使う固定値運用にしている
（`DISTRIBUTION_SPEC.md`が想定する需給連動の自動調整は今回は実装していない
— 「スコープ外にしたもの」参照）。

```sql
update distribution_config set k_default = 4;
```

を実行すれば、**以降の新規投稿**から反映される（既存投稿の`max_reach`は
変わらない）。

## データモデル

`posts`テーブルに以下を追加している（`supabase_migration.sql`）。

| カラム | 役割 |
|---|---|
| `view_count` | これまでに配信・現像された人数 |
| `max_reach` | 到達上限（投稿時のKを焼き込む） |
| `distributable_until` | これを過ぎると新規配信されなくなる（投稿時刻+`display_ttl_hours`、既定60時間） |
| `is_first_post_of_author` | 投稿者の初投稿か（トリガーで自動判定） |
| `status` | `active` / `exhausted`（`max_reach`到達） / `expired`（未使用、下記参照） |
| `is_opened` | 1人以上に現像されたか |
| `total_viewed_seconds` | 全閲覧者の視聴秒数の合計（`view_history`更新トリガーで自動加算） |
| `is_seed` | 運営提供のシード投稿か |

パラメータ（K・重み・TTL・視聴枠）は`distribution_config`という1行だけの
シングルトンテーブルに切り出してあり、コードを変えずにSQLの`UPDATE`だけで
調整できる。ただし`anon`からは直接読み書きできないようアクセス権限を
`REVOKE`してあり、`current_k_default()`等の`SECURITY DEFINER`関数を経由
してのみ参照される。

投稿時、`max_reach`と`distributable_until`は`posts`のカラムデフォルト式
（`current_k_default()` / `current_display_ttl_hours()`）で自動設定される
ため、`shor.html`側の`createPost()`は特別なことをしていない。
`is_first_post_of_author`と`users.has_posted_ever`もトリガー
（`posts_before_insert_first_post` / `posts_after_insert_mark_user_posted`）
が自動で面倒を見る。

## 配信フロー: peek → confirm の2段階

以前は1つのRPC（`select_drift`）で「候補選択」と「予約」を同時に行って
いたが、閲覧枠の消費タイミングを「現像完了時」に統一するため
（詳細は[view-grants.md](view-grants.md)）、2つに分割している。

### 1. `peek_drift(viewer_id)` — 候補を選ぶだけ（副作用なし）

写真を開いた瞬間、`getRandomDrift()`（[shor.html:637-641](../shor.html#L637-L641)）
から呼ばれる。以下の**足切り**を満たす投稿だけを候補にする。

1. `status = 'active'`
2. `now() < distributable_until`（期限内）
3. `view_count < max_reach`（到達上限未達）
4. `author_id != viewer_id`（自分の投稿は除外）
5. その`viewer`がまだ見ていない（`view_history`にその投稿の行が無い）

候補それぞれに次のスコアを付け、**スコアを重みとした加重ランダム抽選**
（Efraimidis–Spirakis法: `power(random(), 1/weight) DESC LIMIT 1`）で
1件選ぶ。決定論的な最大値選択にしないことで「偶然」の手触りを残す。

```
score = W_UNREACHED * (view_count == 0 ? 1 : 0)     -- まだ誰にも届いていない
      + W_FIRSTPOST * (is_first_post_of_author)      -- 投稿者の初投稿
      + W_URGENCY   * urgency                         -- 期限の近さ (0〜1)
      + W_UNDERFED  * (max_reach - view_count) / max_reach  -- 到達の不足度
      + W_BASE                                        -- 全候補への最低当選機会
```

既定の重み: `W_UNREACHED=3.0`, `W_FIRSTPOST=2.0`, `W_URGENCY=1.5`,
`W_UNDERFED=1.0`, `W_BASE=0.1`（すべて`distribution_config`で調整可能）。

候補が0件なら、`is_seed=true`の投稿（運営提供のシード在庫）から
ランダムに1件返す。それも無ければ空を返し、クライアントは
「まだ写真が届いていません」と表示する。

`peek_drift`は読み取り専用で、何度呼んでも状態は変わらない。

### 2. `confirm_drift(viewer_id, post_id)` — 現像完了時に確定

`tick()`内で`developed`が`true`になった瞬間
（[shor.html:888-889](../shor.html#L888-L889)）に、`confirmDrift()`
（[shor.html:646-651](../shor.html#L646-L651)）から呼ばれる。

1. 1日の視聴上限チェック（[view-grants.md](view-grants.md)参照）。
   上限到達なら`false`を返す。
2. 候補の再検証と`view_count`のアトミックな増分を1つの`UPDATE`文で行う
   （`peek`からの経過時間で他の誰かに取られていた・期限切れになっていた
   場合はここで弾かれ、`false`を返す）。`max_reach`に到達したら
   `status`を`exhausted`にする。
3. `view_history`に予約行（`viewed_seconds=0`）を挿入する。

競合や期限切れで`confirm_drift`が`false`を返すことは稀にあるが、その場合も
クライアントは体験上そのまま鑑賞を継続させ、サーバ側の集計に反映されない
だけの扱いとする（[shor.html:643-645](../shor.html#L643-L645)のコメント参照）。

`confirmDrift()`は非同期のfire-and-forgetで呼ぶが、指を離した際に呼ばれる
`recordViewHistoryDB()`（`viewed_seconds`の確定更新）より先に予約行の挿入が
終わっている必要があるため、`release()`は`confirmPromise`
（[shor.html:869](../shor.html#L869), [shor.html:922](../shor.html#L922)）
の完了を待ってから確定更新を行う。UIの画面遷移演出はこの待ち合わせを
またがない。

## 期限切れの扱い（バッチ処理は無し）

`DISTRIBUTION_SPEC.md`は10分毎のバッチで`status`を`expired`に更新する
設計だったが、今回はcronを使わない簡易版にしている。`peek_drift`の
足切り条件2（`now() < distributable_until`）がその場でチェックされるため、
`status`列が実際に`expired`に更新されなくても、**配信されないという結果は
同じ**になる。`status='expired'`という値そのものは現状使われていない
（`active`→`exhausted`の遷移だけが実際に起こる）。将来cronを組む場合は
このバッチを追加すれば良いが、機能的な正しさには影響しない。

## 物理削除（プライバシー要件、配信ロジックとは別系統）

「配信対象から外れる」（`distributable_until`, 48〜60時間）と
「データを物理削除する」（`storage_ttl_days`, 既定30日）は別物として扱う。

- `cleanupOldPosts()`（`shor.html`）がアプリ起動時に、作成から30日経った
  投稿のストレージ画像・`view_history`・`posts`行をまとめて削除する
  （cronではなく起動時の遅延判定）。
- ストレージの画像だけをダッシュボードから手動削除した場合でも、
  `storage.objects`のDELETEトリガー
  （`supabase_migration_004_storage_delete_cascade.sql`）が対応する
  `posts`/`view_history`行を自動的に削除するため、画像だけ消えて
  `posts`行が残る「黒画像」状態にはならない。
- ただし「`peek_drift`が候補を返した直後、クライアントに画像URLが渡って
  から実際に読み込むまでの間に画像が削除される」というレースはDBトリガー
  では防げない。この隙間は`openView()`側で`imageLoads()`
  （[shor.html:808-815](../shor.html#L808-L815)）が画像を先読みし、
  失敗したら候補0件のときと同じ「まだ写真が届いていません」表示に
  フォールバックすることでカバーしている（[screens.md](screens.md)参照）。

## シード投稿（コールドスタート対策）

`is_seed=true`, `author_id=null`, `max_reach`は十分大きい値、
`distributable_until='infinity'`で登録する運営提供の投稿。通常投稿の候補が
0件のときだけ`peek_drift`がフォールバックとして使う（重みを下げて通常の
抽選プールに混ぜるのではなく、"最後の手段"として完全に別枠で扱う）。

実データはdev・本番の両Supabaseに28件投入済み（`message`は各画像ファイル名を
そのままキャプションとして使用）。投入はワンオフのNode.jsスクリプトで、
HEIC/JPEGを`sharp`+`heic-convert`でアプリの`downscale()`と同じ条件
（長辺1280px・JPEG品質82）に変換してから、anonキーでStorageアップロード＋
`posts`への直接INSERTを行った（`supabase_migration.sql`末尾に手動INSERT例
のコメントもあり、少量ならそちらでも可）。追加投入したい場合は同じ手順で
画像を用意すればよい。

## 今回スコープ外にしたもの

- **Kの需給連動自動調整** — `k_default`は固定値。手動で
  `distribution_config`を更新すれば調整できるが、自動計算バッチは無い。
- **10分毎の期限切れバッチ（cron）** — 前述の通り、クエリ時のリアルタイム
  判定で代替しており機能的には等価。
