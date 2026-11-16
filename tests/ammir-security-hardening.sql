\set ON_ERROR_STOP on

-- Run after 20261116210000_ammir_security_defense_in_depth.sql.
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
  v_rpc_count integer;
BEGIN
  SELECT count(*) INTO v_rpc_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND p.prosecdef
    AND has_function_privilege('authenticated',p.oid,'EXECUTE')
    AND p.proname = ANY(ARRAY[
      'ammar_accept_agreement','ammar_accept_market_quote','ammar_accept_project_invitation',
      'ammar_accept_service_offer','ammar_admin_list_message_reports','ammar_admin_review_provider',
      'ammar_advance_market_request','ammar_complete_service_request','ammar_create_market_request',
      'ammar_create_project_invitation','ammar_forward_message','ammar_get_conversation_presence',
      'ammar_is_conversation_member','ammar_mark_conversation_delivered','ammar_mark_conversation_read',
      'ammar_message_to_change_order','ammar_message_to_project_task','ammar_project_role',
      'ammar_remove_project_member','ammar_revoke_project_invitation','ammar_set_presence',
      'ammar_start_conversation','ammar_update_project_member_role','is_admin','is_project_member'
    ]);

  IF v_rpc_count <> 25 THEN
    RAISE EXCEPTION 'Expected 25 authenticated SECURITY DEFINER RPCs, found %',v_rpc_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.prosecdef
      AND has_function_privilege('authenticated',p.oid,'EXECUTE')
      AND p.proname = ANY(ARRAY[
        'ammar_accept_agreement','ammar_accept_market_quote','ammar_accept_project_invitation',
        'ammar_accept_service_offer','ammar_admin_list_message_reports','ammar_admin_review_provider',
        'ammar_advance_market_request','ammar_complete_service_request','ammar_create_market_request',
        'ammar_create_project_invitation','ammar_forward_message','ammar_get_conversation_presence',
        'ammar_is_conversation_member','ammar_mark_conversation_delivered','ammar_mark_conversation_read',
        'ammar_message_to_change_order','ammar_message_to_project_task','ammar_project_role',
        'ammar_remove_project_member','ammar_revoke_project_invitation','ammar_set_presence',
        'ammar_start_conversation','ammar_update_project_member_role','is_admin','is_project_member'
      ])
      AND NOT (coalesce(p.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=""'])
  ) THEN
    RAISE EXCEPTION 'An authenticated SECURITY DEFINER RPC does not use an empty search_path';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.prosecdef
      AND has_function_privilege('anon',p.oid,'EXECUTE')
      AND p.proname = ANY(ARRAY[
        'ammar_accept_agreement','ammar_accept_market_quote','ammar_accept_project_invitation',
        'ammar_accept_service_offer','ammar_admin_list_message_reports','ammar_admin_review_provider',
        'ammar_advance_market_request','ammar_complete_service_request','ammar_create_market_request',
        'ammar_create_project_invitation','ammar_forward_message','ammar_get_conversation_presence',
        'ammar_is_conversation_member','ammar_mark_conversation_delivered','ammar_mark_conversation_read',
        'ammar_message_to_change_order','ammar_message_to_project_task','ammar_project_role',
        'ammar_remove_project_member','ammar_revoke_project_invitation','ammar_set_presence',
        'ammar_start_conversation','ammar_update_project_member_role','is_admin','is_project_member'
      ])
  ) THEN
    RAISE EXCEPTION 'An RPC is executable by anon';
  END IF;

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

ROLLBACK;

SELECT 'AMMIR SECURITY DEFENSE-IN-DEPTH TESTS PASSED' AS result;
