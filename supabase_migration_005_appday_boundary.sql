-- ============================================================
-- SHOR. 追加マイグレーション: 閲覧権リセットの区切りを深夜0時→朝7時に変更
-- supabase_migration_002_defer_reservation.sql の後に実行すること。
-- ============================================================
--
-- 背景:
-- クライアント側の閲覧権モデル（shor.html の appDayStr()）は「現在時刻から
-- 7時間引いた日付」を1日の境界として扱うよう変更した（日本時間の朝7時が
-- 区切り）。confirm_drift の1日の視聴上限チェックも同じ区切りに揃えないと、
-- クライアントとサーバで「今日」の認識が一致しなくなる。
--
-- v_day_start の算出だけを、UTC基準のdate_trunc('day', now())から
-- 「日本時間の朝7時」基準に変更する。confirm_drift の他の処理・peek_drift は
-- 変更なし。
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
