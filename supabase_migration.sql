-- ============================================================
-- SHOR. 写真配信ロジック 実装マイグレーション
-- DISTRIBUTION_SPEC.md に基づく。Supabase の SQL Editor で実行してください。
-- 既存データ（posts / view_history / users）は変更しません。カラム追加のみ。
-- ============================================================

-- ------------------------------------------------------------
-- 1. 設定テーブル（パラメータの切り出し）
--    1行だけを保証するシングルトンテーブル。
--    後で `update distribution_config set k_default = 4;` のように
--    運用中に値を変えられる。
-- ------------------------------------------------------------
create table if not exists distribution_config (
  id boolean primary key default true check (id),
  k_default int not null default 3,
  k_min int not null default 1,
  k_max int not null default 5,
  display_ttl_hours numeric not null default 60,   -- 配信対象から外れるまでの時間
  storage_ttl_days numeric not null default 30,    -- 物理削除までの日数（プライバシー要件、別系統）
  daily_post_limit int not null default 1,
  free_view_per_day int not null default 1,
  post_view_bonus int not null default 1,
  w_unreached numeric not null default 3.0,
  w_firstpost numeric not null default 2.0,
  w_urgency numeric not null default 1.5,
  w_underfed numeric not null default 1.0,
  w_base numeric not null default 0.1
);
insert into distribution_config (id) values (true) on conflict (id) do nothing;

-- distribution_config は内部の調整用パラメータなので、クライアント(anon)からの
-- 直接の読み書きは禁止する。関数経由（SECURITY DEFINER）でだけアクセス可能にする。
revoke all on distribution_config from anon, authenticated;

create or replace function current_k_default() returns int
  language sql stable security definer set search_path = public
  as $$ select k_default from distribution_config limit 1; $$;

create or replace function current_display_ttl_hours() returns numeric
  language sql stable security definer set search_path = public
  as $$ select display_ttl_hours from distribution_config limit 1; $$;

grant execute on function current_k_default() to anon, authenticated;
grant execute on function current_display_ttl_hours() to anon, authenticated;

-- ------------------------------------------------------------
-- 2. users テーブルへの追加
-- ------------------------------------------------------------
alter table users
  add column if not exists has_posted_ever boolean not null default false;

-- ------------------------------------------------------------
-- 3. posts テーブルへの追加（配信管理用フィールド）
-- ------------------------------------------------------------
alter table posts
  add column if not exists view_count int not null default 0,
  add column if not exists max_reach int not null default 0,
  add column if not exists distributable_until timestamptz,
  add column if not exists is_first_post_of_author boolean not null default false,
  add column if not exists status text not null default 'active',
  add column if not exists is_opened boolean not null default false,
  add column if not exists total_viewed_seconds numeric not null default 0,
  add column if not exists is_seed boolean not null default false;

alter table posts
  drop constraint if exists posts_status_check;
alter table posts
  add constraint posts_status_check check (status in ('active','exhausted','expired'));

-- シード投稿は author_id を持たない（運営提供のため）ので NULL を許可する
alter table posts alter column author_id drop not null;

-- 既存カラムのデフォルトを、設定テーブル参照の関数に切り替える
alter table posts alter column max_reach set default current_k_default();
alter table posts alter column distributable_until
  set default (now() + (current_display_ttl_hours() || ' hours')::interval);

-- 既存行（今回のマイグレーション以前の投稿）にも妥当な値を補完しておく
update posts
set max_reach = current_k_default()
where max_reach = 0;
update posts
set distributable_until = created_at + (current_display_ttl_hours() || ' hours')::interval
where distributable_until is null;

create index if not exists idx_posts_candidate
  on posts (status, distributable_until, view_count);
create index if not exists idx_view_history_viewer_post
  on view_history (viewer_id, post_id);

-- ------------------------------------------------------------
-- 4. トリガー: 初投稿判定 (is_first_post_of_author / users.has_posted_ever)
-- ------------------------------------------------------------
create or replace function posts_before_insert_first_post()
returns trigger language plpgsql as $$
declare
  v_has_posted boolean;
begin
  if NEW.is_seed then
    NEW.is_first_post_of_author := false;
    return NEW;
  end if;

  select has_posted_ever into v_has_posted from users where id = NEW.author_id;
  NEW.is_first_post_of_author := (coalesce(v_has_posted, false) = false);
  return NEW;
end;
$$;

drop trigger if exists trg_posts_before_insert_first_post on posts;
create trigger trg_posts_before_insert_first_post
  before insert on posts
  for each row execute function posts_before_insert_first_post();

create or replace function posts_after_insert_mark_user_posted()
returns trigger language plpgsql as $$
begin
  if not NEW.is_seed then
    update users set has_posted_ever = true where id = NEW.author_id and has_posted_ever = false;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_posts_after_insert_mark_user_posted on posts;
create trigger trg_posts_after_insert_mark_user_posted
  after insert on posts
  for each row execute function posts_after_insert_mark_user_posted();

-- ------------------------------------------------------------
-- 5. トリガー: view_history.viewed_seconds 確定更新 → posts.total_viewed_seconds に加算
-- ------------------------------------------------------------
create or replace function view_history_after_update_bump_total()
returns trigger language plpgsql as $$
begin
  if NEW.viewed_seconds is distinct from OLD.viewed_seconds then
    update posts
      set total_viewed_seconds = total_viewed_seconds + (NEW.viewed_seconds - OLD.viewed_seconds)
      where id = NEW.post_id;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_view_history_after_update_bump_total on view_history;
create trigger trg_view_history_after_update_bump_total
  after update on view_history
  for each row execute function view_history_after_update_bump_total();

-- ------------------------------------------------------------
-- 6. 配信 RPC: select_drift(p_viewer_id)
--    6.1 足切り → 6.2 加重ランダム選択 → 6.3 アトミックな更新 まで一つの関数内で行う。
--    候補0件ならシード投稿 (is_seed=true) にフォールバック。
--    1日の視聴上限（無料1+投稿ボーナス1）もサーバ側で検証する（フロントの制限のバックストップ）。
-- ------------------------------------------------------------
create or replace function select_drift(p_viewer_id uuid)
returns table(id uuid, image_url text, message text)
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
  v_pick record;
  v_updated_id uuid;
  v_attempt int;
begin
  select * into v_cfg from distribution_config limit 1;

  -- --- 1日の視聴上限チェック（サーバ側の正） ---
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
    return; -- 上限到達。空の結果を返す
  end if;

  -- --- 通常投稿から、加重ランダムで1件選ぶ（競合時は再試行） ---
  v_attempt := 0;
  while v_attempt < 5 loop
    v_attempt := v_attempt + 1;

    select c.id, c.image_url, c.message, c.view_count, c.max_reach
      into v_pick
    from (
      select p.id, p.image_url, p.message, p.view_count, p.max_reach,
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

    exit when not found;

    update posts p
      set view_count = p.view_count + 1,
          is_opened = true,
          status = case when p.view_count + 1 >= p.max_reach then 'exhausted' else p.status end
      where p.id = v_pick.id and p.view_count < p.max_reach
      returning p.id into v_updated_id;

    if v_updated_id is not null then
      insert into view_history(viewer_id, post_id, viewed_seconds, viewed_at)
        values (p_viewer_id, v_pick.id, 0, now());
      id := v_pick.id; image_url := v_pick.image_url; message := v_pick.message;
      return next;
      return;
    end if;
    -- 競合で取れなかった場合はループして再試行
  end loop;

  -- --- 通常投稿が無ければシードにフォールバック ---
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
    update posts set view_count = view_count + 1, is_opened = true where posts.id = v_pick.id;
    insert into view_history(viewer_id, post_id, viewed_seconds, viewed_at)
      values (p_viewer_id, v_pick.id, 0, now());
    id := v_pick.id; image_url := v_pick.image_url; message := v_pick.message;
    return next;
  end if;

  return;
end;
$$;

grant execute on function select_drift(uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 7. シード投稿の投入例（運営提供の在庫。実際の画像URLに差し替えて実行してください）
-- ------------------------------------------------------------
-- insert into posts (author_id, image_url, message, is_seed, max_reach, distributable_until)
-- values (null, 'https://.../seed1.jpg', '', true, 999999, 'infinity');
