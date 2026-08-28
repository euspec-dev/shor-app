# データモデル

Supabase (Postgres + Storage) 上の実体。認証は無く、匿名UUID
（`localStorage`の`shor:uid`）がそのままユーザーIDとして使われる
（[shor.html:967-974](../shor.html#L967-L974)）。

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

## 投稿結果表示用のローカルストレージ（shor:myPosts）

「あなたの一枚は」結果モーダル（[screens.md](screens.md)参照）は
投稿1件ごとにサムネイル付きで表示するため、投稿成功時に`localStorage`の
`shor:myPosts`へ自分の投稿を記録している。サーバ側に「これは自分の投稿の
一覧」という専用テーブルは無く、あくまでクライアント側の表示専用データ。

- 保存形式: `{id, createdAt, thumb}`の配列。`id`は`posts.id`、`createdAt`は
  `Date.now()`（ミリ秒epoch）、`thumb`は長辺240px・JPEG品質0.5の
  サムネイルdataURL
- 書き込み: `btnSend`のクリックハンドラ内、`createPost()`成功直後
  （[shor.html:1747-1749](../shor.html#L1747-L1749)）。サムネイルは
  `makeThumb(finalDataUrl, 240, .5)`（[shor.html:1844-1856](../shor.html#L1844-L1856)）
  で生成する。`finalDataUrl`は投稿本体のアップロードにも使う
  `cropAdjusted()`（[screens.md](screens.md)の「投稿写真の拡大縮小・移動調整」
  節参照）の出力そのもので、`downscale()`（写真選択直後の縮小用）とは別の
  軽量版。既にJPEG化済みのdataURLを再度縮小するだけなのでFile/Blobを
  経由しない
- 掃除: `pruneMyPostThumbs()`（[shor.html:1030-1034](../shor.html#L1030-L1034)）が
  起動時に`STORAGE_EXPIRE_MS`（30日）より古いエントリを削除する。
  `cleanupOldPosts()`（サーバ側の投稿本体の掃除）とは別関数だが、
  同じ期限・同じタイミング（起動時）で走らせている
- 読み出し: `renderHome()`が起動の度に`shor:myPosts`を読み、まだ結果を
  見せていない前日以前の投稿について`getResultForPost(postId)`
  （[shor.html:1100-1106](../shor.html#L1100-L1106)）で`view_history`の
  `viewed_seconds`合計を取得する。`view_history`に行が無い（＝まだ誰にも
  見られていない）場合は`null`を返し、結果モーダルには出さず無言で
  先送りする（`resultConfirmed`フラグも立てない）。詳細は
  [screens.md](screens.md)の「結果モーダル」節を参照

## テーブル一覧

### users

| カラム | 型 | 備考 |
|---|---|---|
| `id` | uuid (PK) | クライアントが`genUUID()`（[shor.html:967-974](../shor.html#L967-L974)）で生成し、以後永続化する匿名ID |
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
| `is_first_post_of_author` | boolean | トリガーが投稿時に自動判定 |
| `status` | text | `active` / `exhausted`の2値のみ |
| `is_opened` | boolean | 1人以上に現像されたか |
| `total_viewed_seconds` | numeric | 全閲覧者の視聴秒数合計（トリガーで自動加算） |
| `is_seed` | boolean | 運営提供のシード投稿か |
| `theme` | text（nullable） | 投稿時点の30日周期テーマ。表示専用（下記「投稿テーマ」参照） |

`view_count`〜`is_seed`の7カラムは`supabase_migration.sql`で追加した
配信管理用フィールド。詳細は[distribution.md](distribution.md)。以前は
`distributable_until`（配信期限）カラムもあり`status`に`expired`もあったが、
`supabase_migration_006_remove_distributable_until.sql`で撤廃した
（配信期限を撤廃した理由は[distribution.md](distribution.md)参照）。
`theme`は`supabase_migration_007_theme_and_view_order.sql`で追加した
カラムで、既存行は`null`のまま埋めていない。

## 投稿テーマ（30日周期）

投稿画面・閲覧画面それぞれに、その投稿の日の「テーマ」を表示する
（[screens.md](screens.md)参照）。仕様は次の通り。

- `THEMES`（[shor.html:946-955](../shor.html#L946-L955)）: 30個の固定文言の
  配列。**並び順を変更・削除しないこと** — 既に投稿済みの`posts.theme`は
  文字列としてそのまま保存されるため実は並び替えても過去分には影響しないが、
  `themeFor()`が将来の同じ暦日に対して常に同じテーマを返し続けるためには
  順序を保つ必要がある（末尾への追加は安全）
- `themeFor(dayStr = appDayStr())`（[shor.html:958-961](../shor.html#L958-L961)）:
  `dayStr`をUTC日付として解釈し、エポックからの通算日数を`THEMES.length`
  （30）で割った余りを添字にする純関数。同じ暦日を渡せば常に同じテーマを返す
- 投稿時、`createPost()`が`themeFor()`（引数省略＝今日）の結果を`theme`
  カラムに保存する。以後その投稿のテーマは固定され、後から`THEMES`の並びを
  変えても既存投稿の表示は変わらない（文字列そのものを保存しているため）
- `peek_drift`の戻り値に含まれる`theme`・`created_at`を使い、閲覧画面は
  「（投稿日の月日）のテーマ」という形で表示する。`theme`が`null`
  （`supabase_migration_007`より前の投稿、シード投稿）の場合は
  テーマ表示ブロックごと非表示にする
- 配信の足切り・順序には一切使わない（[distribution.md](distribution.md)参照）
- 開発バーの「テーマ閲覧」（`IS_DEV`限定、[shor.html:2003-2011]
  (../shor.html#L2003-L2011)）: `peek_drift`を呼ばず、`theme: themeFor()`
  （今日のテーマ）を積んだダミーのdriftを`openView("home", forcedDrift)`
  経由で直接閲覧画面に渡し、テーマ表示の見た目だけを実DBに触れず確認できる。
  写真は`bottle.png`を流用（`id: null`のため、現像しても`confirmDrift()`は
  `postId`が無く即`false`を返し、DBには何も記録されない。ただし
  `consumeView()`によるローカルの閲覧枠消費は通常の閲覧と同様に発生する）

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

バケット名: `photos`（公開バケット）。ファイル名は`genUUID()+".jpg"`
（[shor.html:1039](../shor.html#L1039)）。`genUUID()`は`crypto.randomUUID()`が
使えればそれを使い、使えない場合（`http:`のLAN IPなど非セキュアコンテキスト。
セキュアコンテキストは`https:`または`localhost`のみで、`crypto.randomUUID`は
そこでしか実装されていない）は`crypto.getRandomValues()`から自前でUUID v4を
組み立てるフォールバックに切り替える（[shor.html:967-974](../shor.html#L967-L974)）。
`posts.image_url`にはパスではなく
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

- `isPng(buffer)`（[shor.html:1818-1824](../shor.html#L1818-L1824)）
  PNGのシグネチャ（先頭8バイト）を見るだけの単純な判定。EXIF解析はしない。
- `handlePickedFile(file, fromCamera)`（[shor.html:1709-1724](../shor.html#L1709-L1724)）
  - `fromCamera=true`（`camera-input`、`capture="environment"`経由。
    Androidの自前モーダルからのみ発生）: 撮ったばかりの写真は定義上
    カメラ写真なので、中身の判定を丸ごとスキップして無条件で受け付ける
  - `fromCamera=false`（iOSは後述の理由で常にこちら。Androidはギャラリー
    経由）: `isPng()`が`true`を返したら`showPickError()`で弾く
- **iOS**: `btn-pick`「＋ 写真を選ぶ」を押すと自前モーダルを挟まず
  `file-input`を直接開く（[shor.html:1687-1690](../shor.html#L1687-L1690)、
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
  完全に遮断。`current_k_default()` /
  `peek_drift()` / `confirm_drift()`が`SECURITY DEFINER`で定義されており、
  これらの関数を経由したときだけ内部的に読み取れる（`current_display_ttl_hours()`
  は配信期限の撤廃に伴い削除した）。

この構成（`posts`等は事実上フルオープン、設定だけ厳格に守る）は現状の
意図的な設計。将来的に`posts`/`view_history`等もRLSで守りたくなった場合は、
各トリガー関数（`posts_before_insert_first_post`等）を
`SECURITY DEFINER`化する必要がある点に注意（[distribution.md](distribution.md)
参照）。
