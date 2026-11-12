\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users(id,email) VALUES
('aaaaaaaa-1000-4000-8000-000000000001','trust-owner@ammir.test'),
('aaaaaaaa-1000-4000-8000-000000000002','trust-admin@ammir.test'),
('aaaaaaaa-1000-4000-8000-000000000003','message-sender@ammir.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles(id,role) VALUES
('aaaaaaaa-1000-4000-8000-000000000001','client'),
('aaaaaaaa-1000-4000-8000-000000000002','admin'),
('aaaaaaaa-1000-4000-8000-000000000003','client')
ON CONFLICT (id) DO UPDATE SET role=EXCLUDED.role;

-- An ordinary authenticated supplier cannot claim verification or suspend itself
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-1000-4000-8000-000000000001',false);
INSERT INTO public.ammar_market_suppliers(
  owner_id,business_name,status,is_verified,verified_at
) VALUES (
  'aaaaaaaa-1000-4000-8000-000000000001',
  'AMMIR Trust Test Supplier','suspended',true,now()
) RETURNING id AS supplier_id \\gset
SELECT set_config('ammir.test.supplier_id', :'supplier_id', false);

DO $test$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.ammar_market_suppliers
    WHERE id=current_setting('ammir.test.supplier_id')::uuid
      AND owner_id=auth.uid()
      AND is_verified=false
      AND verified_at IS NULL
      AND status='active'
  ) THEN
    RAISE EXCEPTION 'Supplier self-verification or self-suspension was not blocked';
  END IF;
END
$test$;

UPDATE public.ammar_market_suppliers
SET is_verified=true, verified_at=now(), status='suspended'
WHERE id=:'supplier_id';

DO $test$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.ammar_market_suppliers
    WHERE id=current_setting('ammir.test.supplier_id')::uuid
      AND is_verified=false
      AND verified_at IS NULL
      AND status='active'
  ) THEN
    RAISE EXCEPTION 'Supplier owner update bypassed trust controls';
  END IF;
END
$test$;

-- The same protection applies to contractor / service-provider profiles
INSERT INTO public.ammar_service_providers(
  owner_id,business_name,provider_type,status,is_verified,verified_at
) VALUES (
  'aaaaaaaa-1000-4000-8000-000000000001',
  'AMMIR Trust Test Contractor','contractor','suspended',true,now()
) RETURNING id AS provider_id \\gset
SELECT set_config('ammir.test.provider_id', :'provider_id', false);

DO $test$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.ammar_service_providers
    WHERE id=current_setting('ammir.test.provider_id')::uuid
      AND is_verified=false
      AND verified_at IS NULL
      AND status='active'
  ) THEN
    RAISE EXCEPTION 'Service-provider self-verification was not blocked';
  END IF;
END
$test$;

-- A report contains the only message context exposed to an administrator
RESET ROLE;
INSERT INTO public.ammar_conversations(
  id,context_type,context_id,subject,created_by
) VALUES (
  'bbbbbbbb-1000-4000-8000-000000000001',
  'project','ammir-trust-fixture','Trust controls test',
  'aaaaaaaa-1000-4000-8000-000000000003'
);
INSERT INTO public.ammar_conversation_participants(
  conversation_id,user_id,participant_role
) VALUES
('bbbbbbbb-1000-4000-8000-000000000001','aaaaaaaa-1000-4000-8000-000000000001','participant'),
('bbbbbbbb-1000-4000-8000-000000000001','aaaaaaaa-1000-4000-8000-000000000003','participant');

INSERT INTO public.ammar_messages(
  id,conversation_id,sender_id,message_type,body
) VALUES (
  'bbbbbbbb-1000-4000-8000-000000000002',
  'bbbbbbbb-1000-4000-8000-000000000001',
  'aaaaaaaa-1000-4000-8000-000000000003',
  'text','AMMIR trust moderation test message'
);

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-1000-4000-8000-000000000001',false);
INSERT INTO public.ammar_message_reports(
  conversation_id,message_id,reporter_id,reason
) VALUES (
  'bbbbbbbb-1000-4000-8000-000000000001',
  'bbbbbbbb-1000-4000-8000-000000000002',
  'aaaaaaaa-1000-4000-8000-000000000001',
  'Test report for AMMIR moderation access'
) RETURNING id AS report_id \\gset
SELECT set_config('ammir.test.report_id', :'report_id', false);

-- Only an admin can use the reported-message review RPC and manage trust state
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-1000-4000-8000-000000000002',false);

DO $test$
DECLARE
  v_count integer;
  v_body text;
BEGIN
  SELECT count(*), max(message_body)
  INTO v_count, v_body
  FROM public.ammar_admin_list_message_reports(50)
  WHERE report_id=current_setting('ammir.test.report_id')::uuid;

  IF v_count <> 1 OR v_body <> 'AMMIR trust moderation test message' THEN
    RAISE EXCEPTION 'Administrator report review RPC did not return the reported message context';
  END IF;
END
$test$;

UPDATE public.ammar_message_reports
SET status='investigating',
    reviewed_at=now(),
    reviewed_by='aaaaaaaa-1000-4000-8000-000000000002'
WHERE id=current_setting('ammir.test.report_id')::uuid;

UPDATE public.ammar_market_suppliers
SET is_verified=true, verified_at=now()
WHERE id=:'supplier_id';

UPDATE public.ammar_service_providers
SET is_verified=true, verified_at=now()
WHERE id=:'provider_id';

DO $test$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.ammar_market_suppliers
    WHERE id=current_setting('ammir.test.supplier_id')::uuid AND is_verified=true AND verified_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Administrator could not verify a supplier';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.ammar_service_providers
    WHERE id=current_setting('ammir.test.provider_id')::uuid AND is_verified=true AND verified_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Administrator could not verify a service provider';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.ammar_message_reports
    WHERE id=current_setting('ammir.test.report_id')::uuid AND status='investigating'
      AND reviewed_by='aaaaaaaa-1000-4000-8000-000000000002'
  ) THEN
    RAISE EXCEPTION 'Administrator could not update a message report';
  END IF;
END
$test$;

RESET ROLE;
ROLLBACK;

SELECT 'AMMIR TRUST AND ADMIN ACCESS TESTS PASSED' AS result;
