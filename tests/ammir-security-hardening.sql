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
  v_signature text;
  v_private_signature text;
  v_public regprocedure;
  v_private regprocedure;
BEGIN
  -- Each Data API RPC remains available as SECURITY INVOKER, while its
  -- privileged implementation is kept in the non-exposed app_private schema.
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
    v_public := to_regprocedure(v_signature);
    v_private_signature := replace(v_signature, 'public.', 'app_private.');
    v_private := to_regprocedure(v_private_signature);

    IF v_public IS NULL OR v_private IS NULL THEN
      RAISE EXCEPTION 'Public wrapper or private implementation is missing: %', v_signature;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p
      WHERE p.oid=v_public
        AND NOT p.prosecdef
        AND has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND has_function_privilege('service_role',p.oid,'EXECUTE')
        AND (coalesce(p.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=""'])
    ) THEN
      RAISE EXCEPTION 'Public RPC % is not a safe SECURITY INVOKER wrapper',v_signature;
    END IF;

    IF has_function_privilege('anon',v_public,'EXECUTE') THEN
      RAISE EXCEPTION 'Public RPC % is executable by anon',v_signature;
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p
      WHERE p.oid=v_private
        AND p.prosecdef
        AND has_function_privilege('authenticated',p.oid,'EXECUTE')
        AND has_function_privilege('service_role',p.oid,'EXECUTE')
        AND (coalesce(p.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=""'])
    ) THEN
      RAISE EXCEPTION 'Private implementation % is not safely privileged',v_private_signature;
    END IF;

    IF has_function_privilege('anon',v_private,'EXECUTE') THEN
      RAISE EXCEPTION 'Private implementation % is executable by anon',v_private_signature;
    END IF;
  END LOOP;

  IF NOT has_schema_privilege('authenticated','app_private','USAGE')
     OR has_schema_privilege('anon','app_private','USAGE') THEN
    RAISE EXCEPTION 'Unexpected app_private schema access';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.prosecdef
      AND has_function_privilege('authenticated',p.oid,'EXECUTE')
  ) THEN
    RAISE EXCEPTION 'Authenticated SECURITY DEFINER implementations remain in public';
  END IF;

  -- The four corrected authenticated actions must remain callable by the wrapper.
  FOREACH v_signature IN ARRAY ARRAY[
    'public.ammar_accept_agreement(uuid)',
    'public.ammar_accept_market_quote(uuid)',
    'public.ammar_accept_service_offer(uuid)',
    'public.ammar_complete_service_request(uuid)'
  ] LOOP
    IF to_regprocedure(v_signature) IS NULL THEN
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
          FROM unnest(p.polroles) AS r(role_oid)
          WHERE r.role_oid IN ('anon'::regrole,'authenticated'::regrole)
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
