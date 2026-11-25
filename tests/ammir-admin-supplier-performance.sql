\set ON_ERROR_STOP on
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.ammar_admin_supplier_performance(timestamp with time zone)') IS NULL THEN
    RAISE EXCEPTION 'supplier performance RPC is missing';
  END IF;
  IF has_function_privilege('anon','public.ammar_admin_supplier_performance(timestamptz)','EXECUTE') THEN
    RAISE EXCEPTION 'anon must not execute supplier performance RPC';
  END IF;
  IF NOT has_function_privilege('authenticated','public.ammar_admin_supplier_performance(timestamptz)','EXECUTE') THEN
    RAISE EXCEPTION 'authenticated must be able to invoke guarded RPC';
  END IF;
  IF has_function_privilege('anon','app_private.ammar_admin_supplier_performance(timestamptz)','EXECUTE') THEN
    RAISE EXCEPTION 'anon must not execute internal privileged function';
  END IF;
END $$;

-- A signed-in non-admin must be denied by the RPC itself, not merely hidden by UI.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000099',true);
DO $
BEGIN
  BEGIN
    PERFORM * FROM public.ammar_admin_supplier_performance(now() - interval '90 days');
    RAISE EXCEPTION 'non-admin unexpectedly received supplier performance';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END $;
RESET ROLE;

-- The exposed result contract must stay aggregate-only: no project identifiers,
-- project names, RFQ titles, delivery references, contact details, or prices.
DO $$
DECLARE
  v_definition text := pg_get_function_result('public.ammar_admin_supplier_performance(timestamptz)');
BEGIN
  IF v_definition ILIKE '%project_id%'
     OR v_definition ILIKE '%project_title%'
     OR v_definition ILIKE '%reference_code%'
     OR v_definition ILIKE '%contact_phone%'
     OR v_definition ILIKE '%total_cost%' THEN
    RAISE EXCEPTION 'RPC result exposes project-specific or unnecessary sensitive fields: %', v_definition;
  END IF;
END $$;

ROLLBACK;
