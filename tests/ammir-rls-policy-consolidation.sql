\set ON_ERROR_STOP on

BEGIN;

DO $ammir_rls_consolidation_tests$
DECLARE
  v_case record;
  v_count integer;
  v_using text;
  v_check text;
BEGIN
  FOR v_case IN
    SELECT *
    FROM (VALUES
      ('ammar_commission_ledger','SELECT','payer_id',false),
      ('ammar_disputes','SELECT','ammar_market_requests',false),
      ('ammar_market_suppliers','SELECT','owner_id',false),
      ('ammar_market_suppliers','UPDATE','owner_id',true),
      ('ammar_message_reports','SELECT','reporter_id',false),
      ('ammar_service_providers','SELECT','owner_id',false),
      ('ammar_service_providers','UPDATE','owner_id',true),
      ('ammar_transaction_events','SELECT','ammar_market_requests',false)
    ) AS expected(table_name, action_name, preserved_condition, needs_check)
  LOOP
    SELECT count(*), max(qual), max(with_check)
      INTO v_count, v_using, v_check
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = v_case.table_name
      AND cmd = v_case.action_name
      AND 'authenticated'::name = ANY(roles);

    IF v_count <> 1 THEN
      RAISE EXCEPTION
        'Expected exactly one authenticated % policy on %, found %',
        v_case.action_name, v_case.table_name, v_count;
    END IF;

    IF position('is_admin' IN coalesce(v_using,'')) = 0
       OR position(v_case.preserved_condition IN coalesce(v_using,'')) = 0 THEN
      RAISE EXCEPTION
        'Combined % policy on % lost the admin or original user predicate: %',
        v_case.action_name, v_case.table_name, v_using;
    END IF;

    IF v_case.needs_check THEN
      IF position('is_admin' IN coalesce(v_check,'')) = 0
         OR position(v_case.preserved_condition IN coalesce(v_check,'')) = 0 THEN
        RAISE EXCEPTION
          'Combined UPDATE WITH CHECK on % lost the admin or owner predicate: %',
          v_case.table_name, v_check;
      END IF;
    END IF;
  END LOOP;
END
$ammir_rls_consolidation_tests$;

ROLLBACK;

SELECT 'AMMIR RLS POLICY CONSOLIDATION TESTS PASSED' AS result;
