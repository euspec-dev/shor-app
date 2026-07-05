-- ============================================================
-- SHOR. 本番用 Supabase プロジェクト ブートストラップSQL
-- 新規作成した空のプロジェクトの SQL Editor に、これを丸ごと1回貼って実行する。
-- 開発環境（既存プロジェクト）で段階的に適用した
-- supabase_migration.sql / _002 / _003 / _004 の内容を、
-- 新規プロジェクトで一度に再現できるようまとめたもの。
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 1. 基本テーブル（users / posts / view_history）
--    開発環境の実データから逆算した定義。RLSは明示的に無効化し、
--    anonキーで直接読み書きできる開発環境と同じ挙動にする
--    （このアプリはログイン機能を持たず、匿名UUIDだけで運用するため）。
-- ------------------------------------------------------------

create table users (
  id uuid primary key default gen_random_uuid(),
  last_active_at timestamptz,
  has_posted_ever boolean not null default false
);
alter table users disable row level security;

create table posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid references users(id),
  image_url text not null,
  message text default '',
  created_at timestamptz not null default now(),
  view_count int not null default 0,
  max_reach int not null default 3,
  distributable_until timestamptz,
  is_first_post_of_author boolean not null default false,
  status text not null default 'active'
    check (status in ('active','exhausted','expired')),
  is_opened boolean not null default false,
  total_viewed_seconds numeric not null default 0,
  is_seed boolean not null default false
);
alter table posts disable row level security;

create table view_history (
  id uuid primary key default gen_random_uuid(),
  viewer_id uuid not null references users(id),
  post_id uuid not null references posts(id),
  viewed_seconds numeric not null default 0,
  viewed_at timestamptz not null default now()
);
alter table view_history disable row level security;

create index idx_posts_candidate on posts (status, distributable_until, view_count);
create index idx_view_history_viewer_post on view_history (viewer_id, post_id);

-- ------------------------------------------------------------
-- 2. 配信ロジック用の設定テーブル（distribution_config）
--    anonからは直接触れないようにし、SECURITY DEFINER関数経由でのみ使う。
-- ------------------------------------------------------------
create table distribution_config (
  id boolean primary key default true check (id),
  k_default int not null default 3,
  k_min int not null default 1,
  k_max int not null default 5,
  display_ttl_hours numeric not null default 60,
  storage_ttl_days numeric not null default 30,
  daily_post_limit int not null default 1,
  free_view_per_day int not null default 1,
  post_view_bonus int not null default 1,
  w_unreached numeric not null default 3.0,
  w_firstpost numeric not null default 2.0,
  w_urgency numeric not null default 1.5,
  w_underfed numeric not null default 1.0,
  w_base numeric not null default 0.1
);
insert into distribution_config (id) values (true);
revoke all on distribution_config from anon, authenticated;

create or replace function current_k_default() returns int
  language sql stable security definer set search_path = public
  as $$ select k_default from distribution_config limit 1; $$;

create or replace function current_display_ttl_hours() returns numeric
  language sql stable security definer set search_path = public
  as $$ select display_ttl_hours from distribution_config limit 1; $$;

grant execute on function current_k_default() to anon, authenticated;
grant execute on function current_display_ttl_hours() to anon, authenticated;

alter table posts alter column max_reach set default current_k_default();
alter table posts alter column distributable_until
  set default (now() + (current_display_ttl_hours() || ' hours')::interval);

-- ------------------------------------------------------------
-- 3. トリガー: 初投稿判定 / users.has_posted_ever
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

create trigger trg_posts_after_insert_mark_user_posted
  after insert on posts
  for each row execute function posts_after_insert_mark_user_posted();

-- ------------------------------------------------------------
-- 4. トリガー: view_history.viewed_seconds 確定更新 → total_viewed_seconds 加算
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

create trigger trg_view_history_after_update_bump_total
  after update on view_history
  for each row execute function view_history_after_update_bump_total();

-- ------------------------------------------------------------
-- 5. peek_drift: 候補選択のみ（副作用なし）
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
-- 6. confirm_drift: 現像完了時に確定（視聴上限チェック・アトミックな予約）
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
    return false;
  end if;

  insert into view_history(viewer_id, post_id, viewed_seconds, viewed_at)
    values (p_viewer_id, p_post_id, 0, now());

  return true;
end;
$$;

grant execute on function confirm_drift(uuid, uuid) to anon, authenticated;

-- ------------------------------------------------------------
-- 7. Storage: photos バケット（公開）+ anon の SELECT/INSERT/DELETE
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('photos', 'photos', true);

create policy "public can read photos bucket objects"
on storage.objects for select
to anon, authenticated
using (bucket_id = 'photos');

create policy "anon can upload photos bucket objects"
on storage.objects for insert
to anon, authenticated
with check (bucket_id = 'photos');

create policy "anon can delete photos bucket objects"
on storage.objects for delete
to anon, authenticated
using (bucket_id = 'photos');

-- ------------------------------------------------------------
-- 8. トリガー: ストレージの画像削除と posts の連動
-- ------------------------------------------------------------
create or replace function storage_objects_after_delete_cascade_posts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if OLD.bucket_id = 'photos' then
    delete from view_history
      where post_id in (
        select id from posts where image_url like '%/photos/' || OLD.name
      );
    delete from posts
      where image_url like '%/photos/' || OLD.name;
  end if;
  return OLD;
end;
$$;

create trigger trg_storage_objects_after_delete_cascade_posts
  after delete on storage.objects
  for each row execute function storage_objects_after_delete_cascade_posts();
