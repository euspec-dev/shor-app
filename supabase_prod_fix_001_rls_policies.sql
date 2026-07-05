-- ============================================================
-- SHOR. 本番プロジェクト用 追加修正: users/posts/view_history に
-- anon向けの明示的な許可ポリシーを追加する
-- ============================================================
--
-- 背景:
-- supabase_bootstrap_prod.sql で `disable row level security` を
-- 実行したにもかかわらず、実際にはINSERTが
-- "new row violates row-level security policy" で拒否された。
-- おそらくこのプロジェクトでは新規テーブルにRLSが強制的に有効化される
-- （開発環境作成時より新しいSupabaseの既定動作）。
--
-- このアプリは認証を持たず、匿名UUIDだけでクライアントが直接テーブルを
-- 読み書きする設計（開発環境と同じ挙動）にする必要があるため、
-- RLSを無効化する代わりに「anon/authenticatedに全操作を許可する」
-- ポリシーを明示的に追加して対応する。
-- ------------------------------------------------------------

alter table users enable row level security;
alter table posts enable row level security;
alter table view_history enable row level security;

create policy "anon full access" on users
  for all to anon, authenticated
  using (true) with check (true);

create policy "anon full access" on posts
  for all to anon, authenticated
  using (true) with check (true);

create policy "anon full access" on view_history
  for all to anon, authenticated
  using (true) with check (true);
