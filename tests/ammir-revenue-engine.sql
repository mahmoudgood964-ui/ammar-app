\set ON_ERROR_STOP on

-- These checks run only against the disposable PostgreSQL service in GitHub Actions.
-- They never connect to the production Supabase project.

DO $test$
DECLARE
  v_table_oid oid;
  v_rpc_oid oid;
  v_delivery_fn oid;
  v_award_fn oid;
  v_definition text;
  v_denied boolean := false;
BEGIN
  SELECT c.oid INTO v_table_oid
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname='ammar_commission_adjustments'
    AND c.relkind='r';

  IF v_table_oid IS NULL THEN
    RAISE EXCEPTION 'Commission adjustments table was not created';
  END IF;

  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=v_table_oid) THEN
    RAISE EXCEPTION 'Commission adjustments table must have RLS enabled';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid=v_table_oid AND tgname='ammar_commission_adjustments_immutable'
      AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'Append-only mutation trigger is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid=v_table_oid AND polname='ammar_commission_adjustments_select'
      AND polcmd='r'
  ) THEN
    RAISE EXCEPTION 'Payer/admin read policy is missing';
  END IF;

  SELECT p.oid INTO v_rpc_oid
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND p.proname='ammar_record_commission_adjustment'
    AND pg_get_function_identity_arguments(p.oid) =
      'p_ledger_id uuid, p_adjustment_kind text, p_amount numeric, p_currency text, p_reason text, p_idempotency_key text, p_source_reference text';

  IF v_rpc_oid IS NULL THEN
    RAISE EXCEPTION 'Commission adjustment RPC is missing';
  END IF;

  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=v_rpc_oid) THEN
    RAISE EXCEPTION 'Commission adjustment RPC must be SECURITY DEFINER';
  END IF;

  IF has_function_privilege('anon',v_rpc_oid,'EXECUTE') THEN
    RAISE EXCEPTION 'Anonymous role must not execute commission adjustment RPC';
  END IF;

  IF NOT has_function_privilege('authenticated',v_rpc_oid,'EXECUTE') THEN
    RAISE EXCEPTION 'Authenticated role must be able to invoke the admin-gated RPC';
  END IF;

  SELECT p.oid INTO v_delivery_fn
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='app_private' AND p.proname='ammir_sync_project_delivery_commission';

  SELECT p.oid INTO v_award_fn
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='app_private' AND p.proname='ammir_record_project_service_award_commission';

  IF v_delivery_fn IS NULL OR v_award_fn IS NULL THEN
    RAISE EXCEPTION 'Expected existing AMMIR commission trigger functions were not found';
  END IF;

  v_definition := pg_get_functiondef(v_delivery_fn);
  IF position('WHERE public.ammar_commission_ledger.status <> ''paid''' in v_definition)=0 THEN
    RAISE EXCEPTION 'Delivery commission upsert does not protect paid ledger rows';
  END IF;

  v_definition := pg_get_functiondef(v_award_fn);
  IF position('WHERE public.ammar_commission_ledger.status <> ''paid''' in v_definition)=0 THEN
    RAISE EXCEPTION 'Service-award commission upsert does not protect paid ledger rows';
  END IF;

  IF has_schema_privilege('anon','app_private','USAGE') THEN
    RAISE EXCEPTION 'Anonymous role must not access the internal app_private schema';
  END IF;
END
$test$;

-- Create isolated CI-only payer, unrelated account, and administrator fixtures.
INSERT INTO auth.users(id,email) VALUES
('aaaaaaaa-2424-4000-8000-000000000001','revenue-payer@ammir.test'),
('aaaaaaaa-2424-4000-8000-000000000002','revenue-unrelated@ammir.test'),
('aaaaaaaa-2424-4000-8000-000000000003','revenue-admin@ammir.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles(id,role) VALUES
('aaaaaaaa-2424-4000-8000-000000000001','client'),
('aaaaaaaa-2424-4000-8000-000000000002','client'),
('aaaaaaaa-2424-4000-8000-000000000003','admin')
ON CONFLICT (id) DO UPDATE SET role=EXCLUDED.role;

INSERT INTO public.ammar_commission_ledger(
  id,request_id,activity_type,source_type,source_id,gross_amount,currency,
  rate_percent,commission_amount,payer_id,status
) VALUES (
  'aaaaaaaa-2424-4000-8000-000000000099',NULL,'market_materials',
  'market_request','ci-revenue-adjustment-fixture',1000.00,'SDG',
  5.00,50.00,'aaaaaaaa-2424-4000-8000-000000000001','due'
);

INSERT INTO public.ammar_commission_ledger(
  id,request_id,activity_type,source_type,source_id,gross_amount,currency,
  rate_percent,commission_amount,payer_id,status
) VALUES (
  'aaaaaaaa-2424-4000-8000-000000000098',NULL,'market_materials',
  'market_request','ci-revenue-concurrency-fixture',1000.00,'SDG',
  5.00,50.00,'aaaaaaaa-2424-4000-8000-000000000001','due'
);

-- Exercise the admin gate using a real authenticated non-admin fixture.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-2424-4000-8000-000000000001',false);

DO $test$
DECLARE
  v_denied boolean := false;
BEGIN
  BEGIN
    PERFORM public.ammar_record_commission_adjustment(
      'aaaaaaaa-2424-4000-8000-000000000099'::uuid,
      'partial_refund',
      1.00,
      'SDG',
      'CI authorization denial fixture',
      'ci-auth-denial-0001',
      NULL
    );
  EXCEPTION WHEN OTHERS THEN
    v_denied := true;
  END;

  IF NOT v_denied THEN
    RAISE EXCEPTION 'Non-admin authenticated account executed commission adjustment RPC';
  END IF;
END
$test$;

RESET ROLE;

-- Valid admin adjustments: partial refund, idempotent retry, full reversal and fee increase.
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-2424-4000-8000-000000000003',false);

SELECT public.ammar_record_commission_adjustment(
  'aaaaaaaa-2424-4000-8000-000000000099','partial_refund',10.00,'SDG',
  'CI partial refund test','ci-refund-0000001',NULL
) AS adjustment_id \gset
SELECT set_config('ammir.test.adjustment_id', :'adjustment_id', false);

DO $test$
DECLARE v_retry uuid; v_count integer;
BEGIN
  v_retry := public.ammar_record_commission_adjustment(
    'aaaaaaaa-2424-4000-8000-000000000099','partial_refund',10.00,'SDG',
    'CI partial refund test','ci-refund-0000001',NULL
  );
  IF v_retry::text <> current_setting('ammir.test.adjustment_id') THEN
    RAISE EXCEPTION 'Idempotent retry returned a different adjustment ID';
  END IF;
  SELECT count(*) INTO v_count FROM public.ammar_commission_adjustments
  WHERE idempotency_key='ci-refund-0000001';
  IF v_count <> 1 THEN RAISE EXCEPTION 'Idempotent retry created duplicate rows'; END IF;
END
$test$;

DO $test$
DECLARE v_rejected boolean := false;
BEGIN
  BEGIN
    PERFORM public.ammar_record_commission_adjustment(
      'aaaaaaaa-2424-4000-8000-000000000099','partial_refund',11.00,'SDG',
      'Changed payload retry','ci-refund-0000001',NULL
    );
  EXCEPTION WHEN OTHERS THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Idempotency key accepted a different payload'; END IF;
END
$test$;

DO $test$
DECLARE v_rejected boolean := false;
BEGIN
  BEGIN
    PERFORM public.ammar_record_commission_adjustment(
      'aaaaaaaa-2424-4000-8000-000000000099','partial_refund',1.00,'EUR',
      'Currency mismatch test','ci-currency-000001',NULL
    );
  EXCEPTION WHEN OTHERS THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Currency mismatch was accepted'; END IF;
END
$test$;

DO $test$
DECLARE v_rejected boolean := false;
BEGIN
  BEGIN
    PERFORM public.ammar_record_commission_adjustment(
      'aaaaaaaa-2424-4000-8000-000000000099','partial_refund',41.00,'SDG',
      'Over adjustment test','ci-overadjust-0001',NULL
    );
  EXCEPTION WHEN OTHERS THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Over-adjustment was accepted'; END IF;
END
$test$;

-- Reject invalid amounts, reasons, and idempotency keys before writing any row.
DO $test$
DECLARE v_rejected boolean;
BEGIN
  v_rejected := false;
  BEGIN
    PERFORM public.ammar_record_commission_adjustment(
      'aaaaaaaa-2424-4000-8000-000000000099','partial_refund',0,'SDG',
      'Zero amount rejection test','ci-zero-amount-0001',NULL
    );
  EXCEPTION WHEN OTHERS THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Zero adjustment amount was accepted'; END IF;

  v_rejected := false;
  BEGIN
    PERFORM public.ammar_record_commission_adjustment(
      'aaaaaaaa-2424-4000-8000-000000000099','partial_refund',-1,'SDG',
      'Negative amount rejection test','ci-negative-amount-01',NULL
    );
  EXCEPTION WHEN OTHERS THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Negative adjustment amount was accepted'; END IF;

  v_rejected := false;
  BEGIN
    PERFORM public.ammar_record_commission_adjustment(
      'aaaaaaaa-2424-4000-8000-000000000099','partial_refund',1.234,'SDG',
      'Precision rejection test','ci-precision-amount-01',NULL
    );
  EXCEPTION WHEN OTHERS THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Adjustment with more than two decimal places was accepted'; END IF;

  v_rejected := false;
  BEGIN
    PERFORM public.ammar_record_commission_adjustment(
      'aaaaaaaa-2424-4000-8000-000000000099','partial_refund',1,'SDG',
      'Too short','ci-short-reason-0001',NULL
    );
  EXCEPTION WHEN OTHERS THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Short adjustment reason was accepted'; END IF;

  v_rejected := false;
  BEGIN
    PERFORM public.ammar_record_commission_adjustment(
      'aaaaaaaa-2424-4000-8000-000000000099','partial_refund',1,'SDG',
      'Short idempotency key test','short-key',NULL
    );
  EXCEPTION WHEN OTHERS THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Short idempotency key was accepted'; END IF;

  v_rejected := false;
  BEGIN
    PERFORM public.ammar_record_commission_adjustment(
      'aaaaaaaa-2424-4000-8000-000000000099'::uuid,'partial_refund',1,'SDG',
      '          ','ci-blank-reason-001',NULL
    );
  EXCEPTION WHEN OTHERS THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Blank adjustment reason was accepted'; END IF;

  v_rejected := false;
  BEGIN
    PERFORM public.ammar_record_commission_adjustment(
      'aaaaaaaa-2424-4000-8000-000000000099'::uuid,'partial_refund',1,'',
      'Blank currency rejection test','ci-blank-currency-01',NULL
    );
  EXCEPTION WHEN OTHERS THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Blank currency was accepted'; END IF;

  v_rejected := false;
  BEGIN
    PERFORM public.ammar_record_commission_adjustment(
      'aaaaaaaa-2424-4000-8000-000000000099'::uuid,'partial_refund',NULL,'SDG',
      'Null amount rejection test','ci-null-amount-0001',NULL
    );
  EXCEPTION WHEN OTHERS THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Null adjustment amount was accepted'; END IF;

  v_rejected := false;
  BEGIN
    PERFORM public.ammar_record_commission_adjustment(
      'aaaaaaaa-2424-4000-8000-000000000099'::uuid,'partial_refund',1,'SDG',
      NULL,'ci-null-reason-0001',NULL
    );
  EXCEPTION WHEN OTHERS THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Null adjustment reason was accepted'; END IF;

  v_rejected := false;
  BEGIN
    PERFORM public.ammar_record_commission_adjustment(
      'aaaaaaaa-2424-4000-8000-000000000099'::uuid,'partial_refund',1,'SDG',
      'Null idempotency key test',NULL,NULL
    );
  EXCEPTION WHEN OTHERS THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Null idempotency key was accepted'; END IF;
END
$test$;

SELECT public.ammar_record_commission_adjustment(
  'aaaaaaaa-2424-4000-8000-000000000099','full_reversal',40.00,'SDG',
  'CI remaining balance reversal','ci-full-reversal-01',NULL
);
SELECT public.ammar_record_commission_adjustment(
  'aaaaaaaa-2424-4000-8000-000000000099','fee_increase',5.00,'SDG',
  'CI fee increase test','ci-fee-increase-01',NULL
);
SELECT public.ammar_record_commission_adjustment(
  'aaaaaaaa-2424-4000-8000-000000000099','fee_decrease',2.00,'SDG',
  'CI fee decrease test','ci-fee-decrease-01',NULL
);

DO $test$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.ammar_commission_adjustments
    WHERE idempotency_key='ci-fee-increase-01' AND amount_delta=5.00
  ) THEN RAISE EXCEPTION 'Fee increase did not create a positive adjustment'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.ammar_commission_adjustments
    WHERE idempotency_key='ci-fee-decrease-01' AND amount_delta=-2.00
  ) THEN RAISE EXCEPTION 'Fee decrease did not create a negative adjustment'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.ammar_commission_ledger
    WHERE id='aaaaaaaa-2424-4000-8000-000000000099'::uuid
      AND gross_amount=1000.00 AND currency='SDG' AND rate_percent=5.00
      AND commission_amount=50.00
      AND payer_id='aaaaaaaa-2424-4000-8000-000000000001'::uuid
      AND status='due'
  ) THEN
    RAISE EXCEPTION 'Commission adjustments rewrote the original ledger financial values or status';
  END IF;

  IF (SELECT count(*) FROM public.project_payment_milestones) <> 0
     OR (SELECT count(*) FROM public.project_payment_events) <> 0 THEN
    RAISE EXCEPTION 'Revenue adjustment tests unexpectedly wrote legacy payment milestone/event rows';
  END IF;
END
$test$;

-- Payer sees their rows; an unrelated authenticated account sees none.
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-2424-4000-8000-000000000001',false);
DO $test$
BEGIN
  IF (SELECT count(*) FROM public.ammar_commission_adjustments) <> 4 THEN
    RAISE EXCEPTION 'Payer cannot read all own commission adjustments';
  END IF;
END
$test$;

SELECT set_config('request.jwt.claim.sub','aaaaaaaa-2424-4000-8000-000000000002',false);
DO $test$
BEGIN
  IF (SELECT count(*) FROM public.ammar_commission_adjustments) <> 0 THEN
    RAISE EXCEPTION 'Unrelated account can read another payer commission adjustments';
  END IF;
END
$test$;
RESET ROLE;

-- Append-only trigger must reject UPDATE and DELETE, even for the database owner.
DO $test$
DECLARE v_rejected boolean := false;
BEGIN
  BEGIN
    UPDATE public.ammar_commission_adjustments
    SET reason='Attempted mutation of immutable adjustment'
    WHERE id=current_setting('ammir.test.adjustment_id')::uuid;
  EXCEPTION WHEN OTHERS THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Commission adjustment UPDATE was not blocked'; END IF;

  v_rejected := false;
  BEGIN
    DELETE FROM public.ammar_commission_adjustments
    WHERE id=current_setting('ammir.test.adjustment_id')::uuid;
  EXCEPTION WHEN OTHERS THEN v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Commission adjustment DELETE was not blocked'; END IF;
END
$test$;

SELECT 'AMMIR REVENUE ENGINE MIGRATIONS, AUTHORIZATION, ADJUSTMENT, RLS AND IMMUTABILITY TESTS PASSED' AS result;
