\set ON_ERROR_STOP on

INSERT INTO auth.users(id,email) VALUES
('11111111-1111-4111-8111-111111111111','buyer@ammar.test'),
('22222222-2222-4222-8222-222222222222','supplier@ammar.test'),
('33333333-3333-4333-8333-333333333333','outsider@ammar.test'),
('44444444-4444-4444-8444-444444444444','admin@ammar.test');

INSERT INTO public.profiles(id,role) VALUES
('11111111-1111-4111-8111-111111111111','client'),
('22222222-2222-4222-8222-222222222222','client'),
('33333333-3333-4333-8333-333333333333','client'),
('44444444-4444-4444-8444-444444444444','admin');

INSERT INTO public.projects(id,client_id,title)
VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','اختبار مشروع');

-- Create an unverified supplier profile and catalogue item
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
INSERT INTO public.ammar_market_suppliers(owner_id,business_name,governorate,city,area,market_name)
VALUES ('22222222-2222-4222-8222-222222222222','مورد الاختبار','الخرطوم','الخرطوم','السجانة','السجانة')
RETURNING id AS supplier_id \gset
SELECT set_config('ammar.test.supplier_id', :'supplier_id', false);

INSERT INTO public.ammar_market_products(supplier_id,title,category,unit,price,currency,quantity_available)
VALUES (:'supplier_id','أسمنت اختبار','أسمنت','جوال',1000,'SDG',50)
RETURNING id AS product_id \gset
SELECT set_config('ammar.test.product_id', :'product_id', false);

-- An unverified supplier must not accept purchase requests
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
DO $ammar_test$
BEGIN
  BEGIN
    PERFORM public.ammar_create_market_request(
      current_setting('ammar.test.supplier_id')::uuid,
      current_setting('ammar.test.product_id')::uuid,
      2,
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'محاولة قبل التوثيق'
    );
    RAISE EXCEPTION 'Unverified supplier unexpectedly accepted a purchase request';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
END
$ammar_test$;

-- Only an administrator can verify a supplier, with an auditable reason
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
SELECT public.ammar_admin_review_provider(
  'supplier',
  current_setting('ammar.test.supplier_id')::uuid,
  'approved',
  'Integration test: supplier identity and business documents verified'
);

-- Buyer creates an order linked to a verified supplier
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT public.ammar_create_market_request(
  :'supplier_id', :'product_id', 2,
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'اختبار شراء'
) AS request_id \gset
SELECT set_config('ammar.test.request_id', :'request_id', false);

-- Supplier sends a quote; request status must advance to quoted automatically
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
INSERT INTO public.ammar_market_quotes(request_id,supplier_id,created_by,total_amount,currency,delivery_days)
VALUES (:'request_id',:'supplier_id','22222222-2222-4222-8222-222222222222',2000,'SDG',2)
RETURNING id AS quote_id \gset
SELECT set_config('ammar.test.quote_id', :'quote_id', false);

RESET ROLE;
DO $ammar_test$
BEGIN
  IF (
    SELECT status FROM public.ammar_market_requests
    WHERE id = current_setting('ammar.test.request_id')::uuid
  ) <> 'quoted' THEN
    RAISE EXCEPTION 'Quote trigger did not set request status to quoted';
  END IF;
END
$ammar_test$;

-- A quote cannot be accepted after supplier verification has been revoked
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
SELECT public.ammar_admin_review_provider(
  'supplier',
  current_setting('ammar.test.supplier_id')::uuid,
  'verification_revoked',
  'Integration test: temporarily revoke verification'
);

RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
DO $ammar_test$
BEGIN
  BEGIN
    PERFORM public.ammar_accept_market_quote(current_setting('ammar.test.quote_id')::uuid);
    RAISE EXCEPTION 'Buyer unexpectedly accepted a quote from an unverified supplier';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
END
$ammar_test$;

-- Restore supplier verification after the controlled rejection test
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
SELECT public.ammar_admin_review_provider(
  'supplier',
  current_setting('ammar.test.supplier_id')::uuid,
  'approved',
  'Integration test: supplier verification restored after review'
);

RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT public.ammar_accept_market_quote(:'quote_id');

-- Agreement can only be created by a party to the accepted transaction
INSERT INTO public.ammar_agreements(
  source_type,source_id,project_id,client_id,provider_id,title,scope,
  amount,currency,created_by
) VALUES (
  'market_request',:'request_id','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222',
  'اتفاق توريد الاختبار','توريد أسمنت الاختبار وفق الكمية والسعر المتفق عليه.',2000,'SDG',
  '11111111-1111-4111-8111-111111111111'
) RETURNING id AS agreement_id \gset
SELECT public.ammar_accept_agreement(:'agreement_id');

RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
SELECT public.ammar_accept_agreement(:'agreement_id');

-- A private market-request conversation and message, sent by the buyer
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT public.ammar_start_conversation(
  '22222222-2222-4222-8222-222222222222',
  'market_request',
  :'request_id',
  'محادثة اختبار'
) AS conversation_id \gset
INSERT INTO public.ammar_messages(conversation_id,sender_id,message_type,body)
VALUES (:'conversation_id','11111111-1111-4111-8111-111111111111','text','رسالة اختبار من العميل.');
INSERT INTO storage.objects(bucket_id,name)
VALUES ('ammar-chat-files', :'conversation_id' || '/11111111-1111-4111-8111-111111111111/test.pdf');

-- Supplier fulfilment; buyer confirms receipt
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
SELECT public.ammar_advance_market_request(:'request_id','fulfilling',NULL);
SELECT public.ammar_advance_market_request(:'request_id','delivered',NULL);

RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT public.ammar_advance_market_request(:'request_id','completed',NULL);

-- Buyer review of supplier after completion
INSERT INTO public.ammar_reviews(request_id,reviewer_id,reviewed_user_id,rating,review_text)
VALUES (:'request_id','11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222',5,'توريد مكتمل.');

-- Service provider creates an unverified profile
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
INSERT INTO public.ammar_service_providers(owner_id,business_name,provider_type)
VALUES ('22222222-2222-4222-8222-222222222222','مقاول الاختبار','contractor')
RETURNING id AS provider_id \gset
SELECT set_config('ammar.test.provider_id', :'provider_id', false);

RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
INSERT INTO public.ammar_service_requests(
  requester_id,project_id,service_type,title,description,city,currency
) VALUES (
  '11111111-1111-4111-8111-111111111111',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'contractor',
  'طلب مقاول اختبار',
  'تنفيذ أعمال ترميم للغرفة الرئيسية.',
  'أم درمان',
  'SDG'
) RETURNING id AS service_request_id \gset
SELECT set_config('ammar.test.service_request_id', :'service_request_id', false);

-- RLS must reject offers from an unverified provider
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $ammar_test$
BEGIN
  BEGIN
    INSERT INTO public.ammar_service_offers(
      request_id,provider_id,created_by,amount,currency,duration_days
    ) VALUES (
      current_setting('ammar.test.service_request_id')::uuid,
      current_setting('ammar.test.provider_id')::uuid,
      auth.uid(),50000,'SDG',14
    );
    RAISE EXCEPTION 'Unverified provider unexpectedly submitted a service offer';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
END
$ammar_test$;

-- Admin approves the contractor with an audit reason
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
SELECT public.ammar_admin_review_provider(
  'service_provider',
  current_setting('ammar.test.provider_id')::uuid,
  'approved',
  'Integration test: contractor identity and portfolio references verified'
);

RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
INSERT INTO public.ammar_service_offers(
  request_id,provider_id,created_by,amount,currency,duration_days
) VALUES (
  :'service_request_id',:'provider_id','22222222-2222-4222-8222-222222222222',50000,'SDG',14
) RETURNING id AS service_offer_id \gset
SELECT set_config('ammar.test.service_offer_id', :'service_offer_id', false);

-- Acceptance must re-check provider verification and status at decision time
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
SELECT public.ammar_admin_review_provider(
  'service_provider',
  current_setting('ammar.test.provider_id')::uuid,
  'verification_revoked',
  'Integration test: temporarily revoke provider verification'
);

RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
DO $ammar_test$
BEGIN
  BEGIN
    PERFORM public.ammar_accept_service_offer(current_setting('ammar.test.service_offer_id')::uuid);
    RAISE EXCEPTION 'Buyer unexpectedly accepted an offer from an unverified provider';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
END
$ammar_test$;

-- Restore provider verification, then accept the offer
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
SELECT public.ammar_admin_review_provider(
  'service_provider',
  current_setting('ammar.test.provider_id')::uuid,
  'approved',
  'Integration test: contractor verification restored after review'
);

RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT public.ammar_accept_service_offer(:'service_offer_id');

INSERT INTO public.ammar_agreements(
  source_type,source_id,client_id,provider_id,title,scope,amount,currency,created_by
) VALUES (
  'service_offer',:'service_offer_id',
  '11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222',
  'اتفاق ترميم اختبار','تنفيذ أعمال الترميم وفق النطاق المقدم والمقبول.',50000,'SDG',
  '11111111-1111-4111-8111-111111111111'
) RETURNING id AS service_agreement_id \gset
SELECT public.ammar_accept_agreement(:'service_agreement_id');

RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
SELECT public.ammar_accept_agreement(:'service_agreement_id');

-- Only the buyer can confirm the completed service and record the project expense
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT public.ammar_complete_service_request(:'service_request_id');

-- Outsider must not read the private conversation or its messages
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
SELECT set_config('ammar.test.conversation_id', :'conversation_id', false);
SELECT set_config('ammar.test.file_path', :'conversation_id' || '/11111111-1111-4111-8111-111111111111/test.pdf', false);
DO $ammar_test$
BEGIN
  IF EXISTS (SELECT 1 FROM public.ammar_conversations WHERE id=current_setting('ammar.test.conversation_id')::uuid) THEN
    RAISE EXCEPTION 'RLS failure: outsider can read a private conversation';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ammar_messages WHERE conversation_id=current_setting('ammar.test.conversation_id')::uuid) THEN
    RAISE EXCEPTION 'RLS failure: outsider can read private messages';
  END IF;
  IF EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id='ammar-chat-files' AND name=current_setting('ammar.test.file_path')) THEN
    RAISE EXCEPTION 'RLS failure: outsider can read a private attachment';
  END IF;
END
$ammar_test$;

RESET ROLE;

-- Final assertions under database owner
SELECT set_config('ammar.test.request_id', :'request_id', false);
SELECT set_config('ammar.test.service_offer_id', :'service_offer_id', false);
SELECT set_config('ammar.test.service_request_id', :'service_request_id', false);
DO $ammar_test$
DECLARE
  v_expenses integer;
  v_notifications integer;
BEGIN
  SELECT count(*) INTO v_expenses
  FROM public.project_expenses
  WHERE project_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  IF v_expenses <> 2 THEN
    RAISE EXCEPTION 'Expected two linked project expenses (materials and service), got %', v_expenses;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.ammar_commission_ledger
    WHERE request_id=current_setting('ammar.test.request_id')::uuid
       OR (source_type='service_offer' AND source_id=current_setting('ammar.test.service_offer_id'))
  ) THEN
    RAISE EXCEPTION 'No commission should be recorded while unapproved default rates are inactive';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ammar_commission_rules WHERE is_active=true) THEN
    RAISE EXCEPTION 'A default commission rule is unexpectedly active';
  END IF;

  IF (
    SELECT status FROM public.ammar_service_requests
    WHERE id=current_setting('ammar.test.service_request_id')::uuid
  ) <> 'closed' THEN
    RAISE EXCEPTION 'Service request should be closed after buyer confirmation';
  END IF;

  SELECT count(*) INTO v_notifications
  FROM public.ammar_user_notifications
  WHERE user_id='22222222-2222-4222-8222-222222222222'
    AND notification_type='new_message';
  IF v_notifications <> 1 THEN
    RAISE EXCEPTION 'Expected one new-message notification, got %', v_notifications;
  END IF;
END
$ammar_test$;

SELECT 'AMMIR ECOSYSTEM INTEGRATION TESTS PASSED' AS result;
