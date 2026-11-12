\set ON_ERROR_STOP on
DO $ammar_storage_test$
DECLARE v_policy_count integer;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM storage.buckets WHERE id='ammar-chat-files' AND public=false AND file_size_limit=52428800) THEN
  RAISE EXCEPTION 'Private AMMIR chat bucket is missing or misconfigured';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM storage.buckets WHERE id='ammar-market-files' AND public=true AND file_size_limit=5242880) THEN
  RAISE EXCEPTION 'Public AMMIR market image bucket is missing or misconfigured';
 END IF;
 SELECT count(*) INTO v_policy_count FROM pg_policies
 WHERE schemaname='storage' AND tablename='objects'
 AND policyname IN (
  'ammar_chat_files_member_select','ammar_chat_files_member_insert','ammar_chat_files_member_delete',
  'ammar_market_images_public_read','ammar_market_images_supplier_insert',
  'ammar_market_images_supplier_update','ammar_market_images_supplier_delete'
 );
 IF v_policy_count<>7 THEN RAISE EXCEPTION 'Expected 7 AMMIR storage policies, found %',v_policy_count; END IF;
 IF EXISTS(SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime') THEN
  IF NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='ammar_messages')
  OR NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='ammar_user_notifications')
  OR NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='ammar_message_receipts') THEN
   RAISE EXCEPTION 'AMMIR message, notification, and receipt tables are not all in Realtime';
  END IF;
 END IF;
END
$ammar_storage_test$;
SELECT 'AMMIR STORAGE AND REALTIME TESTS PASSED' AS result;
