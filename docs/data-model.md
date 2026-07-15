# データモデル

Supabase (Postgres + Storage) 上の実体。認証は無く、匿名UUID
（`localStorage`の`shor:uid`）がそのままユーザーIDとして使われる
（[shor.html:612-613](../shor.html#L612-L613)）。

### なぜiOSだけ別のmanifestを使うのか

iOSでは、Web App Manifestで`display: standalone`（または`fullscreen`/
`minimal-ui`）を指定したページを「ホーム画面に追加」すると、Safari本体とは
別の隔離されたストレージ領域を持つ専用コンテナとして起動する。これは稀な
不具合ではなく、iOSのPWA実装として毎回・確実に起きる仕様。`shor:uid`は
`localStorage`にしか保存していないため、この隔離が起きると**同じ人物が
Safariタブとホーム画面アイコンとで別々の`uid`を持つ**ことになり、
「自分の投稿が他人の投稿として表示される」という、匿名の相手と交換する
という本アプリの前提を壊す不具合につながる。

一方、Androidの「インストール可能」判定（`beforeinstallprompt`が発火する
条件）は`display`が`standalone`/`fullscreen`/`minimal-ui`のいずれかで
あることを要求するため、`manifest.json`自体を`browser`にしてしまうと
Android側のネイティブインストールダイアログが失われる。そのため
**iOSだけ**、`display: browser`にした別ファイル`manifest-ios.json`を用意し、
ページ読み込み時にUA判定でiOSなら`<link rel="manifest" id="app-manifest">`
の参照先をそちらに差し替えている（[shor.html:15-27](../shor.html#L15-L27)）。
「ホーム画面に追加」は常にユーザーの明示的な操作で、この差し替えは
head内で同期的に（他のスクリプトより先に）実行されるため、追加操作の時点
では確実に差し替え後のmanifestが参照される。

この結果、iOSでの「ホーム画面に追加」はSafari本体の通常タブとして開くよう
になり、ストレージが分離されなくなる（トレードオフとして、アドレスバー等
Safari標準UIが表示され、フルスクリーンのネイティブアプリ風の見た目には
ならない）。Androidは従来通り`manifest.json`（`display: standalone`）を
使うため、ネイティブインストールダイアログは維持される。

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
（[shor.html:669](../shor.html#L669)）。`posts.image_url`にはパスではなく
`.../storage/v1/object/public/photos/<uuid>.jpg`という完全なURLをそのまま
保存している。そのため画像ファイル名から`posts`行を逆引きする処理
（`cleanupOldPosts()`のストレージパス抽出、削除連動トリガーのマッチ処理）は
このURL文字列に対する部分一致で行っている。

## 投稿画像のバリデーション（スクリーンショット/Web画像の排除）

スクリーンショットやWeb上の画像の投稿を防ぎ、カメラで撮った写真のみを
受け付けるための仕組み。以前はEXIFのMake/Model有無や経路（どちらのinput
経由か）で判定していたが、iOSのアプリ内カメラ撮影でEXIFが欠落する事故が
繰り返し起きたため、現在は**ファイル形式のシグネチャだけで判定する**方式に
変更してある。スクリーンショットはOS標準でPNG形式で保存され、カメラ写真は
基本的にJPEG/HEICでPNGにはならない、という前提を利用している。

- `isPng(buffer)`（[shor.html:1113-1119](../shor.html#L1113-L1119)）
  PNGのシグネチャ（先頭8バイト）を見るだけの単純な判定。EXIF解析はしない。
- `handlePickedFile(file, fromCamera)`（[shor.html:1028-1044](../shor.html#L1028-L1044)）
  - `fromCamera=true`（`camera-input`、`capture="environment"`経由。
    Androidの自前モーダルからのみ発生）: 撮ったばかりの写真は定義上
    カメラ写真なので、中身の判定を丸ごとスキップして無条件で受け付ける
  - `fromCamera=false`（iOSは後述の理由で常にこちら。Androidはギャラリー
    経由）: `isPng()`が`true`を返したら`showPickError()`で弾く
- **iOS**: `btn-pick`「＋ 写真を選ぶ」を押すと自前モーダルを挟まず
  `file-input`を直接開く（[shor.html:995-1009](../shor.html#L995-L1009)、
  `isIOS()`で判定）。iOS Safariは`accept="image/*"`のinputをタップすると
  OS標準で「写真を撮る/ライブラリ/ファイル」のアクションシートを出すため、
  自前モーダルを重ねると選択が二重になってしまう。この一本化により、
  iOSでは`camera-input`（経路によるカメラ判定）は使われず、常に
  `fileInput`経由＝`fromCamera=false`としてPNG判定を通る
  （OS標準シートで「写真を撮る」を選んだ場合もJPEG/HEICなのでPNG判定は
  通過する）
- **Android**: 一部端末で`accept="image/*"`のinputがPhoto Picker
  （カメラ選択肢が無い）に直行してしまうため、引き続き自前の
  `pick-choice-modal`（[screens.md](screens.md)参照）で
  「写真を撮る」→`camera-input`、「ギャラリーから選ぶ」→`file-input`を
  明示的に振り分けている

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
