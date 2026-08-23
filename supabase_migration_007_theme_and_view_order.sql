-- ============================================================
-- SHOR. 追加マイグレーション: 投稿テーマの追加 + 配信順をview_count昇順に変更
-- supabase_migration_006_remove_distributable_until.sql の後に実行すること。
-- ============================================================
--
-- 変更点:
--   1. posts.theme（text, nullable）を追加。既存行は埋めない（nullのまま）。
--   2. peek_drift の候補選択を、加重ランダム抽選から「view_count昇順
--      （同点内はランダム）」に変更。未閲覧(view_count=0)の投稿を常に
--      最優先で配る。これに伴い distribution_config の重み
--      （w_unreached/w_firstpost/w_age/w_underfed/w_base）は
--      peek_drift からは参照されなくなる（列自体は残す。他用途に
--      転用する可能性を考慮し、今回は削除しない）。
--   3. peek_drift の戻り値に theme・created_at を追加
--      （クライアント側でテーマ表示に使う。配信の足切り・順序には
--      一切使わない）。
--
--   戻り値の型（RETURNS TABLE）が変わるため、CREATE OR REPLACE ではなく
--   一度 DROP してから作り直す。
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- 1. posts: theme カラムを追加
-- ------------------------------------------------------------
alter table posts add column if not exists theme text;

-- ------------------------------------------------------------
-- 2-3. peek_drift を作り直す
-- ------------------------------------------------------------
drop function if exists peek_drift(uuid);

create function peek_drift(p_viewer_id uuid)
returns table(id uuid, image_url text, message text, theme text, created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pick record;
begin
  select c.id, c.image_url, c.message, c.theme, c.created_at
    into v_pick
  from posts c
  where c.is_seed = false
    and c.status = 'active'
    and c.view_count < c.max_reach
    and c.author_id is distinct from p_viewer_id
    and not exists (
      select 1 from view_history vh
      where vh.post_id = c.id and vh.viewer_id = p_viewer_id
    )
  order by c.view_count asc, random()
  limit 1;

  if found then
    id := v_pick.id; image_url := v_pick.image_url; message := v_pick.message;
    theme := v_pick.theme; created_at := v_pick.created_at;
    return next;
    return;
  end if;

  -- 通常投稿が無ければシードにフォールバック（こちらも副作用なし。
  -- view_count昇順ルールは同じくシード内でも適用する）
  select p.id, p.image_url, p.message, p.theme, p.created_at into v_pick
  from posts p
  where p.is_seed = true
    and p.author_id is distinct from p_viewer_id
    and not exists (
      select 1 from view_history vh
      where vh.post_id = p.id and vh.viewer_id = p_viewer_id
    )
  order by p.view_count asc, random()
  limit 1;

  if found then
    id := v_pick.id; image_url := v_pick.image_url; message := v_pick.message;
    theme := v_pick.theme; created_at := v_pick.created_at;
    return next;
  end if;

  return;
end;
$$;

grant execute on function peek_drift(uuid) to anon, authenticated;
