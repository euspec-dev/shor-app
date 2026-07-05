# 本番リリース前チェックリスト

`shor.html`を本番用Supabaseプロジェクトに向けて公開する前に、このリストを
上から順に確認する。関連: [deploy.md](deploy.md)（実際の公開手順）。

## config.js（接続情報・開発フラグ）

- [ ] 本番用の`config.js`で`IS_DEV: false`になっている
      （`config.example.js`の既定値も`false`なので、コピーしただけなら問題ない。
      手動で`true`に書き換えていないか確認）
- [ ] `SUPABASE_URL` / `SUPABASE_ANON_KEY`が**本番用**プロジェクト
      （開発用プロジェクト `yzivhoovldubxejertcf` ではない）を指している
- [ ] `config.js`が`.gitignore`されており、GitHubにキーが上がっていない
      （`git status`で`config.js`が出てこないことを確認。もし過去に誤って
      コミットしてしまった場合は、鍵のローテーションも含めて要相談）

## IS_DEVに連動する項目（config.jsのIS_DEVが正しければ自動的に満たされる）

- [ ] EXIF検証スキップ（`DEV_SKIP_EXIF`）が本番で無効
- [ ] 開発バー（前日投稿/一日進める/リセットの3ボタン）が本番で非表示
      （`IS_DEV=false`だと`#devbar`要素自体がDOMから除去される。
      実際にブラウザで開いて右上に何も出ないことを目視確認する）

## 本番Supabaseプロジェクトの状態

- [ ] `supabase_bootstrap_prod.sql`と`supabase_prod_fix_001_rls_policies.sql`
      （およびそれ以降に追加したマイグレーション）が全て適用済み
- [ ] テスト投稿・テストユーザー・テスト画像が本番DB/ストレージに残っていない
      （`posts` / `view_history` / `users` / Storageの`photos`バケットを
      ダッシュボードで目視確認）
- [ ] `distribution_config`の値（K・重み・TTL・視聴枠）が意図した値になっている
      （既定値のままでよいか、運用前に一度見直す）
- [ ] シード投稿（コールドスタート対策）を用意する場合は投入済み
      （`is_seed=true`, `author_id=null`。詳細は[distribution.md](distribution.md)）
- [ ] `photos`ストレージバケットが`public`になっている
- [ ] `users` / `posts` / `view_history`にanon向けの許可ポリシーが効いている
      （匿名UUIDで直接読み書きする設計のため。RLSが強制有効なプロジェクトでは
      `supabase_prod_fix_001_rls_policies.sql`のポリシーが無いと投稿・閲覧が
      全て失敗する）

## 物理削除（プライバシー要件）

- [ ] `cleanupOldPosts()`（30日経過投稿の物理削除）が本番でも動作する状態か
      確認する。**これはcronではなくアプリ起動時に実行される**ため、
      本番で誰もアクセスしない期間が続くと削除が走らない点に注意
      （[distribution.md](distribution.md)参照。厳密な30日運用が必要なら
      別途バッチ化を検討する）
- [ ] ストレージの画像を手動で消しても`posts`/`view_history`が連動して
      消えるトリガーが本番にも入っている

## 最終確認

- [ ] 本番URLを外部の実ブラウザ（IDEの埋め込みプレビューではない）で開き、
      投稿→閲覧→結果表示の一連の流れを実際に試す
- [ ] `git log` / GitHubのリポジトリ画面で、本番ブランチの内容が
      意図したコミットになっていることを確認する
