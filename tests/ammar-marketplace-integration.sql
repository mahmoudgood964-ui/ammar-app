\set ON_ERROR_STOP on

INSERT INTO auth.users(id,email) VALUES
('11111111-1111-4111-8111-111111111111','buyer@ammar.test'),
('22222222-2222-4222-8222-222222222222','supplier@ammar.test'),
('33333333-3333-4333-8333-333333333333','outsider@ammar.test');

INSERT INTO public.projects(id,client_id,title)
VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','اختبار مشروع');

-- Supplier profile and product creation.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
INSERT INTO public.ammar_market_suppliers(owner_id,business_name,governorate,city,area,market_name)
VALUES ('22222222-2222-4222-8222-222222222222','مورد الاختبار','الخرطوم','الخرطوم','السجانة','السجانة')
RETURNING id AS supplier_id \gset
INSERT INTO public.ammar_market_products(supplier_id,title,category,unit,price,currency,quantity_available)
VALUES (:'supplier_id','أسمنت اختبار','أسمنت','جوال',1000,'SDG',50)
RETURNING id AS product_id \gset

-- Buyer creates an order linked to a project.
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT public.ammar_create_market_request(
  :'supplier_id', :'product_id', 2, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'اختبار شراء'
) AS request_id \gset

-- Supplier sends a quote; request status must advance to quoted automatically.
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
INSERT INTO public.ammar_market_quotes(request_id,supplier_id,created_by,total_amount,currency,delivery_days)
VALUES (:'request_id',:'supplier_id','22222222-2222-4222-8222-222222222222',2000,'SDG',2)
RETURNING id AS quote_id \gset

RESET ROLE;
SELECT set_config('ammar.test.request_id', :'request_id', false);
DO $$ BEGIN
  IF (SELECT status FROM public.ammar_market_requests WHERE id=current_setting('ammar.test.request_id')::uuid) <> 'quoted' THEN
    RAISE EXCEPTION 'Quote trigger did not set request status to quoted';
  END IF;
END $$;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT public.ammar_accept_market_quote(:'quote_id');

-- Agreement can only be created by a party to the accepted transaction.
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

-- A private market-request conversation and message.
SELECT public.ammar_start_conversation(
  '22222222-2222-4222-8222-222222222222','market_request',:'request_id','محادثة اختبار'
) AS conversation_id \gset
INSERT INTO public.ammar_messages(conversation_id,sender_id,message_type,body)
VALUES (:'conversation_id','11111111-1111-4111-8111-111111111111','text','رسالة اختبار من العميل.');

-- The supplier acknowledges fulfilment; the buyer confirms receipt.
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
SELECT public.ammar_advance_market_request(:'request_id','fulfilling',NULL);
SELECT public.ammar_advance_market_request(:'request_id','delivered',NULL);

RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT public.ammar_advance_market_request(:'request_id','completed',NULL);

-- Buyer review of supplier after completion.
INSERT INTO public.ammar_reviews(request_id,reviewer_id,reviewed_user_id,rating,review_text)
VALUES (:'request_id','11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222',5,'توريد مكتمل.');

-- Service provider creates a profile and answers the buyer's RFQ.
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
INSERT INTO public.ammar_service_providers(owner_id,business_name,provider_type)
VALUES ('22222222-2222-4222-8222-222222222222','مقاول الاختبار','contractor')
RETURNING id AS provider_id \gset

RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
INSERT INTO public.ammar_service_requests(
  requester_id,project_id,service_type,title,description,city,currency
) VALUES (
  '11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'contractor','طلب مقاول اختبار','تنفيذ أعمال ترميم للغرفة الرئيسية.','أم درمان','SDG'
) RETURNING id AS service_request_id \gset

RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
INSERT INTO public.ammar_service_offers(request_id,provider_id,created_by,amount,currency,duration_days)
VALUES (:'service_request_id',:'provider_id','22222222-2222-4222-8222-222222222222',50000,'SDG',14)
RETURNING id AS service_offer_id \gset

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

-- Outsider must not read the private conversation or its messages.
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
SELECT set_config('ammar.test.conversation_id', :'conversation_id', false);
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.ammar_conversations WHERE id=current_setting('ammar.test.conversation_id')::uuid) THEN
    RAISE EXCEPTION 'RLS failure: outsider can read a private conversation';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ammar_messages WHERE conversation_id=current_setting('ammar.test.conversation_id')::uuid) THEN
    RAISE EXCEPTION 'RLS failure: outsider can read private messages';
  END IF;
END $$;

RESET ROLE;

-- Final assertions under database owner.
SELECT set_config('ammar.test.request_id', :'request_id', false);
DO $$
DECLARE v_expenses integer; v_commission numeric; v_notifications integer;
BEGIN
  SELECT count(*) INTO v_expenses FROM public.project_expenses
  WHERE project_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  IF v_expenses <> 1 THEN RAISE EXCEPTION 'Expected one linked project expense, got %',v_expenses; END IF;

  SELECT commission_amount INTO v_commission FROM public.ammar_commission_ledger
  WHERE request_id=current_setting('ammar.test.request_id')::uuid;
  IF v_commission <> 100 THEN RAISE EXCEPTION 'Expected 5%% commission of 100, got %',v_commission; END IF;

  SELECT count(*) INTO v_notifications FROM public.ammar_user_notifications
  WHERE user_id='22222222-2222-4222-8222-222222222222'
    AND notification_type='new_message';
  IF v_notifications <> 1 THEN RAISE EXCEPTION 'Expected one new-message notification, got %',v_notifications; END IF;
END $$;

SELECT 'AMMAR ECOSYSTEM INTEGRATION TESTS PASSED' AS result;
