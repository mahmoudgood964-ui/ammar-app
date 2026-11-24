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

-- Exercise the admin gate using a real authenticated non-admin fixture.
INSERT INTO auth.users(id,email)
VALUES ('aaaaaaaa-2424-4000-8000-000000000001','revenue-nonadmin@ammir.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles(id,role)
VALUES ('aaaaaaaa-2424-4000-8000-000000000001','client')
ON CONFLICT (id) DO UPDATE SET role='client';

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

SELECT 'AMMIR REVENUE ENGINE MIGRATIONS AND AUTHORIZATION TESTS PASSED' AS result;
