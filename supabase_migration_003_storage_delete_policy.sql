-- ============================================================
-- SHOR. 追加マイグレーション: storage.objects の DELETE を anon に許可
-- ============================================================
--
-- 背景:
-- storage.objects には SELECT（公開読み取り）と INSERT（アップロード）の
-- ポリシーは存在するが DELETE のポリシーが無く、anon キーからの削除リクエストは
-- 200 OK かつ空配列（＝0件マッチ）で「見た目は成功・実際は何も消えていない」
-- 状態になっていた。これにより:
--   - shor.html の cleanupOldPosts()（30日後の物理削除、プライバシー要件）
--   - これまでの手動クリーンアップ
-- のどちらも画像ファイルの実削除ができていなかった。
--
-- 対応: photos バケットに限定して anon の DELETE を許可する。
-- ------------------------------------------------------------

create policy "anon can delete photos bucket objects"
on storage.objects for delete
to anon, authenticated
using (bucket_id = 'photos');
