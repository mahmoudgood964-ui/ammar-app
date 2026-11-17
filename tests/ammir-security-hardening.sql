\set ON_ERROR_STOP on

-- Run after the AMMIR security and paused-payment deny-policy migrations.
-- Uses no real account, inserts no business data, and rolls back its session changes.
BEGIN;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','',true);

DO $ammir_auth_guard_tests$
DECLARE
  v_message text;
BEGIN
  BEGIN
    PERFORM public.ammar_accept_agreement('00000000-0000-0000-0000-000000000000');
    RAISE EXCEPTION 'AUTH_GUARD_TEST_FAILED: agreement';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
    IF v_message <> 'Authentication required' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM public.ammar_accept_market_quote('00000000-0000-0000-0000-000000000000');
    RAISE EXCEPTION 'AUTH_GUARD_TEST_FAILED: market quote';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
    IF v_message <> 'Authentication required' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM public.ammar_accept_service_offer('00000000-0000-0000-0000-000000000000');
    RAISE EXCEPTION 'AUTH_GUARD_TEST_FAILED: service offer';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
    IF v_message <> 'Authentication required' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM public.ammar_complete_service_request('00000000-0000-0000-0000-000000000000');
    RAISE EXCEPTION 'AUTH_GUARD_TEST_FAILED: service completion';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    GET STACKED DIAGNOSTICS v_message = MESSAGE_TEXT;
    IF v_message <> 'Authentication required' THEN RAISE; END IF;
  END;
END
$ammir_auth_guard_tests$;

RESET ROLE;

DO $ammir_security_assertions$
DECLARE
  v_expected regprocedure;
  v_signature text;
  v_resolved regprocedure;
BEGIN
  -- Every RPC present in this fixture must remain a callable SECURITY DEFINER
  -- function for authenticated clients, with a fixed empty search_path.
  FOREACH v_signature IN ARRAY ARRAY[
      'public.ammar_accept_agreement(uuid)',
      'public.ammar_accept_market_quote(uuid)',
      'public.ammar_accept_project_invitation(text)',
      'public.ammar_accept_service_offer(uuid)',
      'public.ammar_admin_list_message_reports(integer)',
      'public.ammar_admin_review_provider(text, uuid, text, text, text)',
      'public.ammar_advance_market_request(uuid, text, text)',
      'public.ammar_complete_service_request(uuid)',
      'public.ammar_create_market_request(uuid, uuid, numeric, text, text)',
      'public.ammar_create_project_invitation(text, text, text)',
      'public.ammar_forward_message(uuid, uuid)',
      'public.ammar_get_conversation_presence(uuid, uuid)',
      'public.ammar_is_conversation_member(uuid)',
      'public.ammar_mark_conversation_delivered(uuid)',
      'public.ammar_mark_conversation_read(uuid)',
      'public.ammar_message_to_change_order(uuid, text, text, numeric, text, integer)',
      'public.ammar_message_to_project_task(uuid)',
      'public.ammar_project_role(text)',
      'public.ammar_remove_project_member(text, uuid)',
      'public.ammar_revoke_project_invitation(text, uuid)',
      'public.ammar_set_presence(boolean)',
      'public.ammar_start_conversation(uuid, text, text, text)',
      'public.ammar_update_project_member_role(text, uuid, text)',
      'public.is_admin()',
      'public.is_project_member(uuid)'
  ] LOOP
    v_resolved := to_regprocedure(v_signature);
    IF v_resolved IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        WHERE p.oid=v_resolved
          AND p.prosecdef
          AND has_function_privilege('authenticated',p.oid,'EXECUTE')
          AND (coalesce(p.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=""'])
      ) THEN
        RAISE EXCEPTION 'RPC % is missing, not SECURITY DEFINER, not callable by authenticated, or has an unsafe search_path',v_signature;
      END IF;

      IF has_function_privilege('anon',v_resolved,'EXECUTE') THEN
        RAISE EXCEPTION 'RPC % is executable by anon',v_signature;
      END IF;

      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role')
         AND NOT has_function_privilege('service_role',v_resolved,'EXECUTE') THEN
        RAISE EXCEPTION 'RPC % is not executable by service_role',v_signature;
      END IF;
    END IF;
  END LOOP;

  -- The four corrected actions must exist in every CI fixture and explicitly
  -- reject requests without an authenticated user (tested above).
  FOREACH v_signature IN ARRAY ARRAY[
    'public.ammar_accept_agreement(uuid)',
    'public.ammar_accept_market_quote(uuid)',
    'public.ammar_accept_service_offer(uuid)',
    'public.ammar_complete_service_request(uuid)'
  ] LOOP
    v_resolved := to_regprocedure(v_signature);
    IF v_resolved IS NULL THEN
      RAISE EXCEPTION 'Required authenticated action is missing: %',v_signature;
    END IF;
  END LOOP;

  IF EXISTS (
    SELECT 1 FROM pg_default_acl d
    CROSS JOIN LATERAL aclexplode(d.defaclacl) a
    WHERE d.defaclrole='postgres'::regrole
      AND d.defaclnamespace='public'::regnamespace
      AND (
        (d.defaclobjtype IN ('r','S') AND a.grantee IN ('anon'::regrole,'authenticated'::regrole))
        OR
        (d.defaclobjtype='f' AND a.privilege_type='EXECUTE'
          AND a.grantee IN (0,'anon'::regrole,'authenticated'::regrole))
      )
  ) THEN
    RAISE EXCEPTION 'Unsafe default API privileges remain in public schema';
  END IF;

  IF to_regclass('public.project_payment_milestones') IS NOT NULL AND (
    has_table_privilege('anon','public.project_payment_milestones','SELECT')
    OR has_table_privilege('authenticated','public.project_payment_milestones','SELECT')
  ) THEN
    RAISE EXCEPTION 'Paused payment milestone table still grants direct client access';
  END IF;

  IF to_regclass('public.project_payment_events') IS NOT NULL AND (
    has_table_privilege('anon','public.project_payment_events','SELECT')
    OR has_table_privilege('authenticated','public.project_payment_events','SELECT')
  ) THEN
    RAISE EXCEPTION 'Paused payment events table still grants direct client access';
  END IF;
END
$ammir_security_assertions$;


DO $ammir_paused_payment_policy_tests$
DECLARE
  v_table regclass;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'public.project_payment_milestones'::regclass,
    'public.project_payment_events'::regclass
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_class c
      WHERE c.oid=v_table AND c.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'Paused payment table % does not have RLS enabled',v_table;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_policy p
      WHERE p.polrelid=v_table
        AND p.polcmd='*'
        AND (
          SELECT count(DISTINCT role_oid)
          FROM unnest(p.polroles) AS role_oid
          WHERE role_oid IN ('anon'::regrole,'authenticated'::regrole)
        )=2
        AND pg_get_expr(p.polqual,p.polrelid)='false'
        AND pg_get_expr(p.polwithcheck,p.polrelid)='false'
    ) THEN
      RAISE EXCEPTION 'Paused payment table % is missing its deny-all client policy',v_table;
    END IF;

    IF has_table_privilege('anon',v_table,'SELECT')
       OR has_table_privilege('authenticated',v_table,'SELECT') THEN
      RAISE EXCEPTION 'Paused payment table % still grants direct client SELECT',v_table;
    END IF;
  END LOOP;
END
$ammir_paused_payment_policy_tests$;

ROLLBACK;

SELECT 'AMMIR SECURITY DEFENSE-IN-DEPTH TESTS PASSED' AS result;
