# データモデル

Supabase (Postgres + Storage) 上の実体。認証は無く、匿名UUID
（`localStorage`の`shor:uid`）がそのままユーザーIDとして使われる
（[shor.html:603-604](../shor.html#L603-L604)）。

## テーブル一覧

### users

| カラム | 型 | 備考 |
|---|---|---|
| `id` | uuid (PK) | クライアントが`crypto.randomUUID()`で生成し、以後永続化する匿名ID |
| `last_active_at` | timestamptz | `initUser()`が起動の度にupsertする |
| `has_posted_ever` | boolean | 初投稿判定用。トリガーが自動更新（後述） |

### posts

| カラム | 型 | 備考 |
|---|---|---|
| `id` | uuid (PK) | |
| `author_id` | uuid（nullable） | 投稿者。シード投稿は`null` |
| `image_url` | text | Supabase Storageの公開URL（フルURLを直接保存。パスだけではない） |
| `message` | text | 任意の一言（最大15文字、クライアント側でカウント） |
| `created_at` | timestamptz | |
| `view_count` | int | これまでに現像が確定した人数 |
| `max_reach` | int | 到達上限（配信管理、[distribution.md](distribution.md)参照） |
| `distributable_until` | timestamptz | これを過ぎると新規配信されない |
| `is_first_post_of_author` | boolean | トリガーが投稿時に自動判定 |
| `status` | text | `active` / `exhausted` / `expired`（`expired`は現状未使用） |
| `is_opened` | boolean | 1人以上に現像されたか |
| `total_viewed_seconds` | numeric | 全閲覧者の視聴秒数合計（トリガーで自動加算） |
| `is_seed` | boolean | 運営提供のシード投稿か |

後半8カラム（`view_count`〜`is_seed`）は`supabase_migration.sql`で追加した
配信管理用フィールド。詳細は[distribution.md](distribution.md)。

### view_history

| カラム | 型 | 備考 |
|---|---|---|
| `id` | uuid (PK) | |
| `viewer_id` | uuid | 閲覧者（`users.id`参照、FK制約あり） |
| `post_id` | uuid | 閲覧された投稿 |
| `viewed_seconds` | numeric | 保持秒数。`confirm_drift`が`0`で予約行を作り、現像完了後に`recordViewHistoryDB()`が確定値へ更新する |
| `viewed_at` | timestamptz | 予約（＝現像完了）した時刻 |

1閲覧者×1投稿につき最大1行しか作られない設計（同じ投稿を同じ人に
二度と見せないための実質的な既読管理はこのテーブルの存在有無で判定している）。

### distribution_config（シングルトン）

`supabase_migration.sql`で追加。K・重み・TTL・視聴枠の既定値を1行に集約した
設定テーブル。`id boolean primary key default true check (id)`という制約で
複数行の挿入を防いでいる。列の意味は[distribution.md](distribution.md)・
[view-grants.md](view-grants.md)参照。

## リレーション

```
users 1 ──< posts (author_id)         -- 1人が複数投稿できる
users 1 ──< view_history (viewer_id)  -- 1人が複数閲覧できる
posts 1 ──< view_history (post_id)    -- 1投稿を複数人が閲覧できる（最大 max_reach 人）
```

## Storage

バケット名: `photos`（公開バケット）。ファイル名は`crypto.randomUUID()+".jpg"`
（[shor.html:660](../shor.html#L660)）。`posts.image_url`にはパスではなく
`.../storage/v1/object/public/photos/<uuid>.jpg`という完全なURLをそのまま
保存している。そのため画像ファイル名から`posts`行を逆引きする処理
（`cleanupOldPosts()`のストレージパス抽出、削除連動トリガーのマッチ処理）は
このURL文字列に対する部分一致で行っている。

## 投稿画像のバリデーション（カメラ写真かどうかの判定）

スクリーンショットやWeb上の画像の投稿を防ぎ、カメラで撮った写真のみを
受け付けるための仕組み。以前はファイルの中身（EXIF）だけで判定していたが、
iOSのアプリ内カメラ撮影ではEXIFのMake/Model情報が欠落することがあり、
正当なカメラ写真が誤って弾かれる事故が繰り返し起きたため、現在は
**どちらのinput経由で来たか（経路）を信頼する**方式に変更してある。

- `handlePickedFile(file, fromCamera)`（[shor.html:1011-1027](../shor.html#L1011-L1027)）
  - `fromCamera=true`（`camera-input`、`capture="environment"`経由）:
    撮ったばかりの写真は定義上カメラ写真なので、EXIF/HEIC判定を
    丸ごとスキップして無条件で受け付ける
  - `fromCamera=false`（`file-input`＝ギャラリー経由）:
    従来通り`hasCameraExif()`（[shor.html:1093](../shor.html#L1093)、
    JPEGのEXIF Make/Modelタグの有無を見る簡易パーサ）または`isHeic()`
    （[shor.html:1127](../shor.html#L1127)、HEIC/HEIFのシグネチャ判定。
    HEICはスクリーンショットやWeb画像としては流通しない実質カメラ専用
    形式なのでEXIF解析はせず許可する）のどちらかを満たさないと
    `showPickError()`で弾く
- 経路を確定させるため、`btn-pick`「＋ 写真を選ぶ」を押すと、iOS/Androidを
  問わず常に`pick-choice-modal`（[screens.md](screens.md)参照）を表示し、
  「写真を撮る」→`camera-input`、「ギャラリーから選ぶ」→`file-input`を
  明示的に振り分けている（[shor.html:993](../shor.html#L993)）

## アクセス権限（RLS/GRANT）の状態

- `users` / `posts` / `view_history` / `storage.objects`（`photos`バケット）:
  `anon`ロールから直接 SELECT/INSERT/UPDATE/DELETE できる（RLSは実質的に
  無効、または全許可のポリシーがある状態）。クライアントはSupabaseの
  anonキーだけで直接テーブルを操作している。
- `distribution_config`: `anon`/`authenticated`からは`REVOKE ALL`で
  完全に遮断。`current_k_default()` / `current_display_ttl_hours()` /
  `peek_drift()` / `confirm_drift()`が`SECURITY DEFINER`で定義されており、
  これらの関数を経由したときだけ内部的に読み取れる。

この構成（`posts`等は事実上フルオープン、設定だけ厳格に守る）は現状の
意図的な設計。将来的に`posts`/`view_history`等もRLSで守りたくなった場合は、
各トリガー関数（`posts_before_insert_first_post`等）を
`SECURITY DEFINER`化する必要がある点に注意（[distribution.md](distribution.md)
参照）。
