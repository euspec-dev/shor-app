-- ============================================================
-- SHOR. 追加マイグレーション: 予約タイミングを現像完了時まで遅延
-- supabase_migration.sql (select_drift) の後に実行すること。
-- ============================================================
--
-- 背景:
-- select_drift は「候補を選ぶ」と「view_count を予約として+1する」を
-- 同時に行っていた。しかしクライアント側の閲覧枠（無料枠/投稿枠）の消費を
-- 「現像が完了した段階」まで遅らせることにしたため、サーバ側の予約タイミングも
-- 同じ瞬間（現像完了時）に合わせないと、クライアントとサーバで
-- 「今日あと何回見られるか」の認識がズレてしまう。
--
-- そこで select_drift を2つの関数に分割する:
--   1. peek_drift(viewer_id)              … 候補を選んで返すだけ（副作用なし）
--   2. confirm_drift(viewer_id, post_id)  … 現像完了時に呼ぶ。ここで初めて
--                                            1日の視聴上限チェック・view_countの
--                                            アトミックな増分・view_history予約を行う
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- 1. peek_drift: 候補選択のみ（読み取り専用、状態は一切変更しない）
-- ------------------------------------------------------------
create or replace function peek_drift(p_viewer_id uuid)
returns table(id uuid, image_url text, message text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cfg distribution_config%rowtype;
  v_pick record;
begin
  select * into v_cfg from distribution_config limit 1;

  select c.id, c.image_url, c.message
    into v_pick
  from (
    select p.id, p.image_url, p.message,
      (
        v_cfg.w_unreached * (case when p.view_count = 0 then 1 else 0 end)
        + v_cfg.w_firstpost * (case when p.is_first_post_of_author then 1 else 0 end)
        + v_cfg.w_urgency * greatest(0, least(1,
            1 - (
              extract(epoch from (p.distributable_until - now()))
              / greatest(1, extract(epoch from (p.distributable_until - p.created_at)))
            )
          ))
        + v_cfg.w_underfed * ((p.max_reach - p.view_count)::numeric / greatest(1, p.max_reach))
        + v_cfg.w_base
      ) as weight
    from posts p
    where p.is_seed = false
      and p.status = 'active'
      and now() < p.distributable_until
      and p.view_count < p.max_reach
      and p.author_id is distinct from p_viewer_id
      and not exists (
        select 1 from view_history vh
        where vh.post_id = p.id and vh.viewer_id = p_viewer_id
      )
  ) c
  order by power(random(), 1.0 / c.weight) desc
  limit 1;

  if found then
    id := v_pick.id; image_url := v_pick.image_url; message := v_pick.message;
    return next;
    return;
  end if;

  -- 通常投稿が無ければシードにフォールバック（こちらも副作用なし）
  select p.id, p.image_url, p.message into v_pick
  from posts p
  where p.is_seed = true
    and p.author_id is distinct from p_viewer_id
    and not exists (
      select 1 from view_history vh
      where vh.post_id = p.id and vh.viewer_id = p_viewer_id
    )
  order by random()
  limit 1;

  if found then
    id := v_pick.id; image_url := v_pick.image_url; message := v_pick.message;
    return next;
  end if;

  return;
end;
$$;

grant execute on function peek_drift(uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 2. confirm_drift: 現像完了時に呼ぶ。ここで初めて状態を変更する。
--    1日の視聴上限チェック・view_countのアトミックな増分・view_history予約を
--    すべてこの1関数内で行う。
-- ------------------------------------------------------------
create or replace function confirm_drift(p_viewer_id uuid, p_post_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cfg distribution_config%rowtype;
  v_day_start timestamptz;
  v_views_today int;
  v_posted_today boolean;
  v_allowed int;
  v_updated_id uuid;
begin
  select * into v_cfg from distribution_config limit 1;

  -- --- 1日の視聴上限チェック（現像完了の瞬間に判定する = サーバ側の正） ---
  v_day_start := date_trunc('day', now());
  select count(*) into v_views_today
    from view_history
    where viewer_id = p_viewer_id and viewed_at >= v_day_start;
  select exists(
    select 1 from posts
    where author_id = p_viewer_id and is_seed = false and created_at >= v_day_start
  ) into v_posted_today;
  v_allowed := v_cfg.free_view_per_day + (case when v_posted_today then v_cfg.post_view_bonus else 0 end);
  if v_views_today >= v_allowed then
    return false;
  end if;

  -- --- 候補の再検証 + view_count のアトミックな増分（1文で行う） ---
  update posts
    set view_count = view_count + 1,
        is_opened = true,
        status = case when view_count + 1 >= max_reach then 'exhausted' else status end
    where id = p_post_id
      and view_count < max_reach
      and status = 'active'
      and now() < distributable_until
      and author_id is distinct from p_viewer_id
      and not exists (
        select 1 from view_history vh
        where vh.post_id = p_post_id and vh.viewer_id = p_viewer_id
      )
    returning id into v_updated_id;

  if v_updated_id is null then
    return false; -- peek後に競合/期限切れ/既視聴になっていた（稀）
  end if;

  insert into view_history(viewer_id, post_id, viewed_seconds, viewed_at)
    values (p_viewer_id, p_post_id, 0, now());

  return true;
end;
$$;

grant execute on function confirm_drift(uuid, uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 3. 旧関数を撤去（peek_drift + confirm_drift に置き換わったため）
-- ------------------------------------------------------------
drop function if exists select_drift(uuid);
