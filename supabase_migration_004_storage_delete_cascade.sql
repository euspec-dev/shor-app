-- ============================================================
-- SHOR. 追加マイグレーション: ストレージの画像削除を posts に連動させる
-- ============================================================
--
-- 背景:
-- Supabaseダッシュボードから手動でストレージの画像だけを削除すると、
-- 対応する posts 行が画像なしのまま残り、黒画像バグが再発する。
-- storage.objects の DELETE をトリガーで拾い、対応する posts / view_history
-- を自動的に削除することで、削除経路（ダッシュボード手動 / anonキー経由の
-- cleanupOldPosts() など）によらず常に整合性を保つ。
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

drop trigger if exists trg_storage_objects_after_delete_cascade_posts on storage.objects;
create trigger trg_storage_objects_after_delete_cascade_posts
  after delete on storage.objects
  for each row execute function storage_objects_after_delete_cascade_posts();
