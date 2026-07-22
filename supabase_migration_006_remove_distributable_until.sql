-- ============================================================
-- SHOR. 追加マイグレーション: 配信期限（distributable_until）を撤廃
-- supabase_migration_005_appday_boundary.sql の後に実行すること。
-- ============================================================
--
-- 背景:
-- 未到達最優先＋到達人数上限(K)により在庫は自然に回転するため、配信期限は
-- 不要と判断した。期限をなくすことで「流れ着かなかった」というネガティブな
-- 結果状態をユーザー体験から排除する。
--
-- 変更点:
--   - peek_drift / confirm_drift から「期限内」の足切り(now() < distributable_until)を削除
--   - スコアの urgency（期限切迫）項を廃止し、代わりに age（投稿からの経過時間）項を新設。
--     期限は参照せず created_at からの経過時間のみで、3日で頭打ちになるよう0〜1に正規化する。
--     未到達が複数あるとき古いものから先に届くようにし、漂流の滞留を防ぐのが狙い。
--   - distribution_config.w_urgency を廃止し、w_age を新設（初期値は旧w_urgencyと同じ1.5）
--   - distribution_config.display_ttl_hours、current_display_ttl_hours() 関数を削除
--   - posts.status の enum から 'expired' を削除（active / exhausted のみ）
--   - posts.distributable_until カラムを削除
--
-- 物理削除（storage_ttl_days・30日ルール、プライバシー要件）は対象外。そのまま残す。
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- 1. distribution_config: w_age を追加（w_urgencyの初期値を引き継ぐ）
-- ------------------------------------------------------------
alter table distribution_config
  add column if not exists w_age numeric not null default 1.5;
update distribution_config set w_age = w_urgency where w_age = 1.5;

-- ------------------------------------------------------------
-- 2. peek_drift / confirm_drift を更新
--    （distributable_until列を参照しなくなってから、後続手順で列を削除する）
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
        + v_cfg.w_age * least(1, extract(epoch from (now() - p.created_at)) / (3 * 86400))
        + v_cfg.w_underfed * ((p.max_reach - p.view_count)::numeric / greatest(1, p.max_reach))
        + v_cfg.w_base
      ) as weight
    from posts p
    where p.is_seed = false
      and p.status = 'active'
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
  -- クライアントのappDayStr()（日本時間・朝7時区切り）に合わせる。
  v_day_start := (
    date_trunc('day', (now() AT TIME ZONE 'Asia/Tokyo') - interval '7 hours')
    + interval '7 hours'
  ) AT TIME ZONE 'Asia/Tokyo';
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
      and author_id is distinct from p_viewer_id
      and not exists (
        select 1 from view_history vh
        where vh.post_id = p_post_id and vh.viewer_id = p_viewer_id
      )
    returning id into v_updated_id;

  if v_updated_id is null then
    return false; -- peek後に競合/既視聴になっていた（稀）
  end if;

  insert into view_history(viewer_id, post_id, viewed_seconds, viewed_at)
    values (p_viewer_id, p_post_id, 0, now());

  return true;
end;
$$;

grant execute on function confirm_drift(uuid, uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 3. current_display_ttl_hours() を削除
-- ------------------------------------------------------------
drop function if exists current_display_ttl_hours();

-- ------------------------------------------------------------
-- 4. posts: status enum から expired を削除し、distributable_until 列を削除
-- ------------------------------------------------------------
update posts set status = 'exhausted' where status = 'expired'; -- 現状未使用のはずだが念のため
alter table posts drop constraint if exists posts_status_check;
alter table posts add constraint posts_status_check check (status in ('active','exhausted'));
alter table posts drop column if exists distributable_until;

-- distributable_until を含んでいたインデックスを張り直す
drop index if exists idx_posts_candidate;
create index if not exists idx_posts_candidate on posts (status, view_count);

-- ------------------------------------------------------------
-- 5. distribution_config: display_ttl_hours / w_urgency を削除
-- ------------------------------------------------------------
alter table distribution_config drop column if exists display_ttl_hours;
alter table distribution_config drop column if exists w_urgency;
