# 配信ロジック（マッチング）の仕様

`DISTRIBUTION_SPEC.md` を元に実装した、投稿がどの閲覧者にどう届くかの仕組み。
SQL側の実体は次の6つのマイグレーションファイル。上から順に実行されている。

1. `supabase_migration.sql` — 配信管理カラム・設定テーブル・`select_drift`（後に分割）
2. `supabase_migration_002_defer_reservation.sql` — `select_drift` を
   `peek_drift` / `confirm_drift` の2段階に分割
3. `supabase_migration_003_storage_delete_policy.sql` — ストレージDELETEの
   anon許可
4. `supabase_migration_004_storage_delete_cascade.sql` — ストレージ削除と
   `posts`行の連動
5. `supabase_migration_005_appday_boundary.sql` — `confirm_drift`の1日の
   視聴上限チェックの区切りを、UTC深夜0時から日本時間の朝7時に変更
   （詳細は[view-grants.md](view-grants.md)参照）
6. `supabase_migration_006_remove_distributable_until.sql` — 配信期限
   （`distributable_until`）を撤廃し、スコアの`urgency`項を`age`項に
   置き換え（詳細は下記）
7. `supabase_migration_007_theme_and_view_order.sql` — `posts.theme`を
   追加し、`peek_drift`の候補選択を加重ランダムから`view_count`昇順
   （同点内ランダム）に変更（詳細は下記）

閲覧権（1日に何回見られるか）については [view-grants.md](view-grants.md) 参照。
本ドキュメントは「どの投稿が選ばれるか」「どこまで配られたら打ち止めか」を扱う。
投稿テーマ（`theme`）については[data-model.md](data-model.md)参照。

## 目的

1枚の写真を「気の合う誰かに」ではなく、**できるだけ多くの投稿を
最低1人には届ける**ことだけを最適化する。好み・傾向によるパーソナライズは
一切行わない（`peek_drift`は候補の`view_count`だけを見て選んでおり、
閲覧者の過去の好みは見ていない）。配信に期限は設けていない（後述）。

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
| `is_first_post_of_author` | 投稿者の初投稿か（トリガーで自動判定） |
| `status` | `active` / `exhausted`（`max_reach`到達）の2値のみ |
| `is_opened` | 1人以上に現像されたか |
| `total_viewed_seconds` | 全閲覧者の視聴秒数の合計（`view_history`更新トリガーで自動加算） |
| `is_seed` | 運営提供のシード投稿か |
| `theme` | 投稿時の30日周期テーマ（`text`, nullable）。詳細は[data-model.md](data-model.md)参照 |

以前は`distributable_until`（配信期限）カラムと`status='expired'`もあったが、
`supabase_migration_006_remove_distributable_until.sql`で撤廃した
（理由は下記「配信期限を撤廃した理由」参照）。`theme`は
`supabase_migration_007_theme_and_view_order.sql`で追加した表示専用の
カラムで、**配信の足切り・順序には一切使わない**（既存行はnullのまま）。

パラメータ（K・重み・視聴枠）は`distribution_config`という1行だけの
シングルトンテーブルに切り出してあり、コードを変えずにSQLの`UPDATE`だけで
調整できる。ただし`anon`からは直接読み書きできないようアクセス権限を
`REVOKE`してあり、`current_k_default()`等の`SECURITY DEFINER`関数を経由
してのみ参照される。

投稿時、`max_reach`は`posts`のカラムデフォルト式（`current_k_default()`）で
自動設定されるため、`shor.html`側の`createPost()`は特別なことをしていない。
`is_first_post_of_author`と`users.has_posted_ever`もトリガー
（`posts_before_insert_first_post` / `posts_after_insert_mark_user_posted`）
が自動で面倒を見る。

## 配信フロー: peek → confirm の2段階

以前は1つのRPC（`select_drift`）で「候補選択」と「予約」を同時に行って
いたが、閲覧枠の消費タイミングを「現像完了時」に統一するため
（詳細は[view-grants.md](view-grants.md)）、2つに分割している。

### 1. `peek_drift(viewer_id)` — 候補を選ぶだけ（副作用なし）

写真を開いた瞬間、`getRandomDrift()`（[shor.html:1279](../shor.html#L1279)）
から呼ばれる。以下の**足切り**を満たす投稿だけを候補にする。

1. `status = 'active'`
2. `view_count < max_reach`（到達上限未達）
3. `author_id != viewer_id`（自分の投稿は除外）
4. その`viewer`がまだ見ていない（`view_history`にその投稿の行が無い）

候補を**`view_count`昇順、同点内はランダム**（`order by view_count asc,
random() limit 1`）で並べ、先頭の1件を返す。まだ誰にも見られていない
投稿（`view_count = 0`）が常に最優先で選ばれ、`view_count`が並んでいる
候補が複数あるときだけその中からランダムに決まる。完全な決定論的選択
ではなく同点内にランダム性を残すことで「偶然」の手触りを保っている。

以前（`supabase_migration_006`まで）は`unreached`/`firstpost`/`age`/
`underfed`/`base`の5項を重み付け加算した加重ランダム抽選だったが、
`supabase_migration_007_theme_and_view_order.sql`で単純な`view_count`
昇順に置き換えた。`distribution_config`の重み列（`w_unreached`等）は
残っているが、`peek_drift`からは参照されなくなっている。

候補が0件なら、`is_seed=true`の投稿（運営提供のシード在庫）から
同じ`view_count`昇順ルールで1件返す。それも無ければ空を返し、
クライアントは「まだ、流れ着いた一枚がありません」と表示する。

`theme`・`created_at`も戻り値に含まれる（クライアント側のテーマ表示用、
[data-model.md](data-model.md)参照）が、足切り・順序には一切関与しない。

`peek_drift`は読み取り専用で、何度呼んでも状態は変わらない。

### 2. `confirm_drift(viewer_id, post_id)` — 現像完了時に確定

`tick()`内で`developed`が`true`になった瞬間
（[shor.html:1359-1360](../shor.html#L1359-L1360)）に、`confirmDrift()`
（[shor.html:1009-1014](../shor.html#L1009-L1014)）から呼ばれる。

1. 1日の視聴上限チェック（[view-grants.md](view-grants.md)参照）。
   上限到達なら`false`を返す。
2. 候補の再検証と`view_count`のアトミックな増分を1つの`UPDATE`文で行う
   （`peek`からの経過時間で他の誰かに取られていた・既視聴になっていた
   場合はここで弾かれ、`false`を返す）。`max_reach`に到達したら
   `status`を`exhausted`にする。
3. `view_history`に予約行（`viewed_seconds=0`）を挿入する。

競合で`confirm_drift`が`false`を返すことは稀にあるが、その場合も
クライアントは体験上そのまま鑑賞を継続させ、サーバ側の集計に反映されない
だけの扱いとする（[shor.html:1395](../shor.html#L1395)、`pending.catch(() => {})`
で静かに無視している箇所）。

`confirmDrift()`は非同期のfire-and-forgetで呼ぶが、指を離した際に呼ばれる
`recordViewHistoryDB()`（`viewed_seconds`の確定更新）より先に予約行の挿入が
終わっている必要があるため、`release()`は`confirmPromise`
（[shor.html:1340](../shor.html#L1340), [shor.html:1393-1397](../shor.html#L1393-L1397)）
の完了を待ってから確定更新を行う。UIの画面遷移演出はこの待ち合わせを
またがない。

## 配信期限を撤廃した理由

以前は`distributable_until`（投稿時刻+`display_ttl_hours`、既定60時間）を
過ぎた投稿を`peek_drift`/`confirm_drift`の足切りで弾き、10分毎のバッチで
`status`を`expired`に更新する設計（`DISTRIBUTION_SPEC.md`旧版）だった
（バッチ自体はcronを使わず、足切り条件のリアルタイム判定で代替していた）。

`supabase_migration_006_remove_distributable_until.sql`でこれを撤廃した。
未到達最優先（`unreached`）＋到達人数上限(K)により在庫は自然に回転するため、
配信期限は不要と判断した。期限をなくすことで「流れ着かなかった」という
ネガティブな結果状態をユーザー体験から排除する。

期限による強制的な打ち切りの代わりに、`view_count`昇順の配信順
（上記「1. `peek_drift`」参照）そのものが、未到達の投稿を常に最優先で
消化する仕組みになっている。当初（`supabase_migration_006`時点）は
スコアの`age`項（未到達の候補の中で古いものを緩やかに優先する）で
これを実現していたが、`supabase_migration_007_theme_and_view_order.sql`
で配信順を`view_count`昇順に一本化した際、より直接的にこの役目を
果たすようになったため`age`項は不要になった。`status`のenumも
`active`/`exhausted`の2値のみになり、`expired`は完全に廃止した。

## 物理削除（プライバシー要件、配信ロジックとは別系統）

配信可否の管理（上記、期限は無し）と
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
  （[shor.html:1236-1243](../shor.html#L1236-L1243)）が画像を先読みし、
  失敗したら候補0件のときと同じ「まだ、流れ着いた一枚がありません」表示に
  フォールバックすることでカバーしている（[screens.md](screens.md)参照）。

## シード投稿（コールドスタート対策）

`is_seed=true`, `author_id=null`, `max_reach`は十分大きい値で登録する
運営提供の投稿（配信期限を廃止したため`distributable_until`の指定も不要に
なった）。通常投稿の候補が0件のときだけ`peek_drift`がフォールバックとして
使う（重みを下げて通常の抽選プールに混ぜるのではなく、"最後の手段"として
完全に別枠で扱う）。

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
