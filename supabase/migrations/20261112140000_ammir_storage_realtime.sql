-- AMMIR private chat uploads, public product images, and live message delivery.
-- Idempotent storage and Realtime setup. Does not touch project-payment tables or records.

BEGIN;

INSERT INTO storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
VALUES
  (
    'ammar-chat-files',
    'ammar-chat-files',
    false,
    52428800,
    ARRAY[
      'image/jpeg','image/png','image/webp','application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'video/mp4','video/webm','video/quicktime'
    ]
  ),
  (
    'ammar-market-files',
    'ammar-market-files',
    true,
    5242880,
    ARRAY['image/jpeg','image/png','image/webp']
  )
ON CONFLICT (id) DO UPDATE
SET name=EXCLUDED.name,
    public=EXCLUDED.public,
    file_size_limit=EXCLUDED.file_size_limit,
    allowed_mime_types=EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS ammar_chat_files_member_select ON storage.objects;
CREATE POLICY ammar_chat_files_member_select
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id='ammar-chat-files'
  AND EXISTS (
    SELECT 1
    FROM public.ammar_conversations c
    WHERE c.id::text=(storage.foldername(name))[1]
      AND public.ammar_is_conversation_member(c.id)
  )
);

DROP POLICY IF EXISTS ammar_chat_files_member_insert ON storage.objects;
CREATE POLICY ammar_chat_files_member_insert
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id='ammar-chat-files'
  AND (storage.foldername(name))[2]=(SELECT auth.uid())::text
  AND EXISTS (
    SELECT 1
    FROM public.ammar_conversations c
    WHERE c.id::text=(storage.foldername(name))[1]
      AND public.ammar_is_conversation_member(c.id)
  )
);

DROP POLICY IF EXISTS ammar_chat_files_member_delete ON storage.objects;
CREATE POLICY ammar_chat_files_member_delete
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id='ammar-chat-files'
  AND (storage.foldername(name))[2]=(SELECT auth.uid())::text
  AND EXISTS (
    SELECT 1
    FROM public.ammar_conversations c
    WHERE c.id::text=(storage.foldername(name))[1]
      AND public.ammar_is_conversation_member(c.id)
  )
);

DROP POLICY IF EXISTS ammar_market_images_public_read ON storage.objects;
CREATE POLICY ammar_market_images_public_read
ON storage.objects FOR SELECT TO public
USING (bucket_id='ammar-market-files');

DROP POLICY IF EXISTS ammar_market_images_supplier_insert ON storage.objects;
CREATE POLICY ammar_market_images_supplier_insert
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id='ammar-market-files'
  AND (storage.foldername(name))[2]=(SELECT auth.uid())::text
  AND EXISTS (
    SELECT 1
    FROM public.ammar_market_suppliers s
    WHERE s.id::text=(storage.foldername(name))[1]
      AND s.owner_id=(SELECT auth.uid())
  )
);

DROP POLICY IF EXISTS ammar_market_images_supplier_update ON storage.objects;
CREATE POLICY ammar_market_images_supplier_update
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id='ammar-market-files'
  AND (storage.foldername(name))[2]=(SELECT auth.uid())::text
  AND EXISTS (
    SELECT 1
    FROM public.ammar_market_suppliers s
    WHERE s.id::text=(storage.foldername(name))[1]
      AND s.owner_id=(SELECT auth.uid())
  )
)
WITH CHECK (
  bucket_id='ammar-market-files'
  AND (storage.foldername(name))[2]=(SELECT auth.uid())::text
  AND EXISTS (
    SELECT 1
    FROM public.ammar_market_suppliers s
    WHERE s.id::text=(storage.foldername(name))[1]
      AND s.owner_id=(SELECT auth.uid())
  )
);

DROP POLICY IF EXISTS ammar_market_images_supplier_delete ON storage.objects;
CREATE POLICY ammar_market_images_supplier_delete
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id='ammar-market-files'
  AND (storage.foldername(name))[2]=(SELECT auth.uid())::text
  AND EXISTS (
    SELECT 1
    FROM public.ammar_market_suppliers s
    WHERE s.id::text=(storage.foldername(name))[1]
      AND s.owner_id=(SELECT auth.uid())
  )
);

-- Supabase Realtime publication is required by the browser's message,
-- notification, and delivery-receipt subscriptions.
DO $ammar_realtime$
DECLARE
  t text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime') THEN
    FOREACH t IN ARRAY ARRAY[
      'ammar_messages',
      'ammar_user_notifications',
      'ammar_message_receipts'
    ]
    LOOP
      IF to_regclass(format('public.%I',t)) IS NOT NULL
         AND NOT EXISTS (
           SELECT 1 FROM pg_publication_tables
           WHERE pubname='supabase_realtime'
             AND schemaname='public'
             AND tablename=t
         ) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I',t);
      END IF;
    END LOOP;
  END IF;
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'Realtime publication could not be updated automatically; add the three AMMIR messaging tables manually.';
END
$ammar_realtime$;

COMMIT;
