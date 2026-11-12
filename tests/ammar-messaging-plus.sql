\set ON_ERROR_STOP on

-- Use the private market-request thread created by the base integration suite.
SELECT id AS conversation_id
FROM public.ammar_conversations
WHERE context_type='market_request' AND subject='محادثة اختبار'
ORDER BY created_at DESC LIMIT 1 \gset

SELECT id AS source_message_id
FROM public.ammar_messages
WHERE conversation_id=:'conversation_id'
  AND body='رسالة اختبار من العميل.'
ORDER BY created_at DESC LIMIT 1 \gset

-- A new message creates an undelivered receipt for the other participant.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
INSERT INTO public.ammar_messages(conversation_id,sender_id,message_type,body)
VALUES (:'conversation_id','11111111-1111-4111-8111-111111111111','text','رسالة لاختبار إيصال التسليم والقراءة.')
RETURNING id AS receipt_message_id \gset

-- Recipient marks delivery, then read.
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
SELECT public.ammar_mark_conversation_delivered(:'conversation_id');
SELECT public.ammar_mark_conversation_read(:'conversation_id');

RESET ROLE;
DO $ammar_plus_test$
BEGIN
  IF NOT EXISTS(
    SELECT 1 FROM public.ammar_message_receipts
    WHERE message_id=current_setting('ammar.test.receipt_message_id',true)::uuid
      AND user_id='22222222-2222-4222-8222-222222222222'
      AND delivered_at IS NOT NULL AND read_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Delivery/read receipts were not recorded';
  END IF;
END
$ammar_plus_test$;

-- Re-fetch the generated id into a session setting for the assertion above.
SELECT set_config('ammar.test.receipt_message_id', :'receipt_message_id', false);

-- Presence privacy: hidden last-seen must not be returned to a conversation peer.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT public.ammar_set_presence(false);
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $ammar_plus_test$
BEGIN
  IF EXISTS(SELECT 1 FROM public.ammar_get_conversation_presence(
    current_setting('ammar.test.conversation_id')::uuid,
    '11111111-1111-4111-8111-111111111111'
  )) THEN
    RAISE EXCEPTION 'Hidden last-seen was exposed';
  END IF;
END
$ammar_plus_test$;

-- Archive and pin are per-user; message reports are limited to conversation participants.
INSERT INTO public.ammar_conversation_preferences(conversation_id,user_id,archived_at)
VALUES (current_setting('ammar.test.conversation_id')::uuid,auth.uid(),now());
INSERT INTO public.ammar_pinned_messages(conversation_id,message_id,pinned_by)
VALUES (
  current_setting('ammar.test.conversation_id')::uuid,
  :'source_message_id',
  auth.uid()
);
INSERT INTO public.ammar_message_reports(conversation_id,message_id,reporter_id,reason)
VALUES (
  current_setting('ammar.test.conversation_id')::uuid,
  :'source_message_id',
  auth.uid(),
  'بلاغ اختبار آمن على رسالة داخل المحادثة.'
);

-- Show-last-seen can be enabled again by the account owner.
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT public.ammar_set_presence(true);

-- Add the supplier to the project in the fixture so the project conversation can be opened.
RESET ROLE;
INSERT INTO public.project_members(project_id,user_id,member_role)
VALUES (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '22222222-2222-4222-8222-222222222222',
  'manager'
)
ON CONFLICT(project_id,user_id) DO NOTHING;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT public.ammar_start_conversation(
  '22222222-2222-4222-8222-222222222222',
  'project',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'محادثة المشروع'
) AS project_conversation_id \gset

INSERT INTO public.ammar_messages(conversation_id,sender_id,message_type,body)
VALUES (:'project_conversation_id','11111111-1111-4111-8111-111111111111','text','أضف هذه الملاحظة إلى قائمة مهام المشروع.')
RETURNING id AS project_message_id \gset

-- Message forwarding is allowed only to another thread the sender belongs to.
SELECT public.ammar_forward_message(:'source_message_id',:'project_conversation_id');

-- Project conversation messages can be converted into a task or controlled change request.
SELECT public.ammar_message_to_project_task(:'project_message_id') AS task_id \gset
SELECT public.ammar_message_to_change_order(
  :'project_message_id',
  'طلب تغيير من المحادثة',
  'تم تحويل رسالة المشروع إلى طلب تغيير لمراجعته واعتماده.',
  0,
  'SDG',
  0
) AS change_order_id \gset

RESET ROLE;
DO $ammar_plus_test$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.project_tasks WHERE title='أضف هذه الملاحظة إلى قائمة مهام المشروع.') THEN
    RAISE EXCEPTION 'Message-to-task conversion failed';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.project_change_orders WHERE title='طلب تغيير من المحادثة') THEN
    RAISE EXCEPTION 'Message-to-change-order conversion failed';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.ammar_pinned_messages WHERE message_id=current_setting('ammar.test.source_message_id',true)::uuid) THEN
    RAISE EXCEPTION 'Message pin was not persisted';
  END IF;
END
$ammar_plus_test$;

-- A location and a video message are accepted by the extended message model.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
INSERT INTO public.ammar_messages(
  conversation_id,sender_id,message_type,body,location_lat,location_lng,location_label
) VALUES (
  :'conversation_id','11111111-1111-4111-8111-111111111111',
  'location','موقع التسليم',15.500000,32.550000,'الخرطوم'
);
INSERT INTO public.ammar_messages(
  conversation_id,sender_id,message_type,file_path,file_name,mime_type
) VALUES (
  :'conversation_id','11111111-1111-4111-8111-111111111111',
  'video',:'conversation_id' || '/11111111-1111-4111-8111-111111111111/site.mp4',
  'site.mp4','video/mp4'
);

-- A block prevents subsequent messages in an existing thread.
INSERT INTO public.ammar_user_blocks(blocker_id,blocked_id,reason)
VALUES(auth.uid(),'22222222-2222-4222-8222-222222222222','اختبار الحظر');

DO $ammar_plus_test$
BEGIN
  BEGIN
    INSERT INTO public.ammar_messages(conversation_id,sender_id,message_type,body)
    VALUES (
      current_setting('ammar.test.conversation_id')::uuid,
      auth.uid(),
      'text',
      'رسالة يجب أن تفشل بسبب الحظر.'
    );
    RAISE EXCEPTION 'Blocked messaging was not prevented';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM='Blocked messaging was not prevented' THEN RAISE; END IF;
  END;
END
$ammar_plus_test$;

RESET ROLE;

SELECT set_config('ammar.test.source_message_id', :'source_message_id', false);
SELECT 'AMMAR ADVANCED MESSAGING TESTS PASSED' AS result;
