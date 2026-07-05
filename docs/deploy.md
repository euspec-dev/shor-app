# 本番デプロイ手順（初心者向け）

知人に渡すURLを作るまでの手順。リリース前には必ず
[release-checklist.md](release-checklist.md)を確認すること。

## 全体像

- `main`ブランチ = 開発用。`config.js`は`.gitignore`されており、コミットしない
  （ローカルの開発用Supabaseを指す`config.js`を各自手元に置くだけ）。
- `production`ブランチ = 本番用。**このブランチにだけ**、本番用Supabaseを
  指す`config.js`（`IS_DEV: false`）を明示的にコミットする。
- GitHub Pagesが`production`ブランチの中身をそのままインターネットに公開する。
  知人に渡すURLはそこで発行される。
- `production`ブランチは、`main`と同じフォルダではなく**`git worktree`で
  別フォルダ（`../shor-app-production`）にチェックアウトして操作する**
  （理由は下の「⚠️ 注意」参照）。

`config.js`の中身（Supabaseの`anon`/`publishable`キー）は、元々ブラウザに
そのまま埋め込まれて公開される前提の値なので、`production`ブランチに
コミットして公開しても問題ない（本番ページを公開する時点でどのみち
ソースから見えるため）。

### ⚠️ 注意: 同じフォルダで`git checkout production`しないこと

`config.js`は`main`では`.gitignore`対象（追跡されていない）、
`production`では追跡対象（コミット済み）というファイルなので、同じフォルダで
`git checkout production` → `git checkout main`と行き来すると、**`main`に
戻った瞬間に`config.js`がフォルダから消える**（gitが「productionには
あったがmainには無いファイル」として削除するため）。これは実際に本番展開の
際に起きた事象。`git worktree`で作業フォルダ自体を分ければ、この問題は
一切起こらない。

## 初回セットアップ（最初の1回だけ）

### 1. これまでの変更を`main`にコミット・pushする

まだ一度もコミットしていない状態なので、最初にこれを行う。

```
git add shor.html docs/ *.sql config.example.js .gitignore claude.md DISTRIBUTION_SPEC.md
git commit -m "初期実装"
git push -u origin main
```

（`config.js`は`.gitignore`されているので、このコマンドでは上がらない）

### 2. `production`ブランチを作り、本番用`config.js`だけをコミットする

`main`と同じフォルダではなく、隣に専用フォルダを作ってそちらで作業する:

```
git checkout -b production
git worktree add ../shor-app-production production
git checkout main
```

（最後の`git checkout main`で、元のフォルダを開発用の状態に戻しておく）

`../shor-app-production/config.js`の中身を、本番用Supabaseプロジェクトの
値に書き換える（`IS_DEV`は必ず`false`）:

```js
window.SHOR_CONFIG = {
  SUPABASE_URL: "https://ispsppwwocrngxzfculg.supabase.co",
  SUPABASE_ANON_KEY: "（本番プロジェクトのanon/publishableキー）",
  IS_DEV: false
};
```

書き換えたら、`../shor-app-production`フォルダの中で
（`.gitignore`に反していても明示的に追加する）:

```
git add -f config.js
git commit -m "本番用configを追加"
git push -u origin production
```

### 3. GitHubの画面でGitHub Pagesを有効化する

1. ブラウザで `https://github.com/euspec-dev/shor-app` を開く
2. 上部タブの「**Settings**」をクリック
3. 左メニューの「**Pages**」をクリック
4. 「Build and deployment」の「Source」で「**Deploy from a branch**」を選ぶ
5. 「Branch」のプルダウンで「**production**」を選び、フォルダは「**/ (root)**」のまま、「**Save**」を押す
6. 1〜2分待つと、同じ画面に
   「Your site is live at `https://euspec-dev.github.io/shor-app/`」
   という緑のメッセージが表示される

### 4. 知人に渡すURL

上記で表示されたURLの末尾に`shor.html`を付けたもの。

```
https://euspec-dev.github.io/shor-app/shor.html
```

（トップページ`index.html`を用意していないため、`shor.html`まで含めたURLを
そのまま知人に渡す）

## 通常運用: 変更を本番に反映する

1. いつも通り`shor-app`フォルダ（`main`ブランチ）で開発・動作確認する
   （ローカルの開発用`config.js`のまま）
2. 本番に反映したい変更ができたら、`../shor-app-production`フォルダに移動して
   取り込む:
   ```
   cd ../shor-app-production
   git merge main
   git push
   ```
   （`config.js`は`main`側では管理されていないファイルなので、`merge`しても
   `production`側の本番用`config.js`は上書きされない。`shor-app`フォルダ側は
   ずっと`main`のままなので触らなくてよい）
3. push後、1〜2分でGitHub Pagesに自動反映される
4. デプロイ前に[release-checklist.md](release-checklist.md)を確認する

## URLの確認場所（再掲）

`https://github.com/euspec-dev/shor-app` → Settings → Pages に、現在公開中の
URLが常に表示されている。
