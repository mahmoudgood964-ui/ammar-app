-- AMMIR: keep privileged RPC implementations in a non-exposed schema.
-- Public RPC names remain available as SECURITY INVOKER SQL wrappers.
-- This preserves client API signatures while preventing direct Data API access
-- to SECURITY DEFINER implementations.

BEGIN;

CREATE SCHEMA app_private AUTHORIZATION postgres;
COMMENT ON SCHEMA app_private IS
  'Internal AMMIR function implementations. Do not add this schema to Supabase API exposed schemas.';

REVOKE ALL ON SCHEMA app_private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA app_private TO authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA app_private
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;

DO $ammir_move_definer_rpcs$
DECLARE
  v_count integer;
  v_expected_count integer;
  v_row record;
  v_call_args text;
  v_wrapper_body text;
  v_volatility text;
  v_parallel text;
  v_strict text;
  v_comment text;
BEGIN
  SELECT count(*)
  INTO v_expected_count
  FROM unnest(ARRAY[
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
    ]) AS expected(signature)
  WHERE to_regprocedure(expected.signature) IS NOT NULL;

  SELECT count(*)
  INTO v_count
  FROM pg_proc AS p
  JOIN pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosecdef
    AND has_function_privilege('authenticated', p.oid, 'EXECUTE');

  IF v_expected_count = 0 OR v_count <> v_expected_count THEN
    RAISE EXCEPTION
      'Authenticated SECURITY DEFINER RPC inventory mismatch: expected %, found %; aborting safely',
      v_expected_count, v_count;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
      AND NOT (coalesce(p.proconfig, ARRAY[]::text[]) @> ARRAY['search_path=""'])
  ) THEN
    RAISE EXCEPTION
      'At least one privileged RPC does not have an empty search_path; aborting safely';
  END IF;

  FOR v_row IN
    SELECT
      p.oid,
      p.proname,
      pg_get_function_identity_arguments(p.oid) AS identity_args,
      pg_get_function_arguments(p.oid) AS all_args,
      pg_get_function_result(p.oid) AS result_type,
      p.pronargs,
      p.proretset,
      p.provolatile,
      p.proparallel,
      p.proisstrict
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
    ORDER BY p.proname, p.oid
  LOOP
    v_comment := obj_description(v_row.oid, 'pg_proc');

    SELECT string_agg('$' || g.i::text, ', ' ORDER BY g.i)
    INTO v_call_args
    FROM generate_series(1, v_row.pronargs) AS g(i);
    v_call_args := coalesce(v_call_args, '');

    v_volatility := CASE v_row.provolatile
      WHEN 'i' THEN 'IMMUTABLE'
      WHEN 's' THEN 'STABLE'
      ELSE 'VOLATILE'
    END;

    v_parallel := CASE v_row.proparallel
      WHEN 's' THEN 'PARALLEL SAFE'
      WHEN 'r' THEN 'PARALLEL RESTRICTED'
      ELSE 'PARALLEL UNSAFE'
    END;

    v_strict := CASE WHEN v_row.proisstrict THEN 'STRICT' ELSE '' END;

    IF v_row.proretset THEN
      v_wrapper_body := format(
        'SELECT * FROM app_private.%I(%s)',
        v_row.proname,
        v_call_args
      );
    ELSE
      v_wrapper_body := format(
        'SELECT app_private.%I(%s)',
        v_row.proname,
        v_call_args
      );
    END IF;

    -- Move the original object (preserving its OID, owner, body and dependencies)
    -- and its SECURITY DEFINER execution context into the internal schema.
    EXECUTE format(
      'ALTER FUNCTION public.%I(%s) SET SCHEMA app_private',
      v_row.proname,
      v_row.identity_args
    );

    EXECUTE format(
      'REVOKE ALL ON FUNCTION app_private.%I(%s) FROM PUBLIC, anon',
      v_row.proname,
      v_row.identity_args
    );
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION app_private.%I(%s) TO authenticated, service_role',
      v_row.proname,
      v_row.identity_args
    );

    -- Recreate the original public RPC signature as a fixed-search-path,
    -- SECURITY INVOKER wrapper that delegates to the protected implementation.
    EXECUTE format(
      'CREATE FUNCTION public.%I(%s) RETURNS %s LANGUAGE sql %s %s %s SECURITY INVOKER SET search_path = %L AS %L',
      v_row.proname,
      v_row.all_args,
      v_row.result_type,
      v_volatility,
      v_parallel,
      v_strict,
      '',
      v_wrapper_body
    );

    EXECUTE format(
      'REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC, anon',
      v_row.proname,
      v_row.identity_args
    );
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated, service_role',
      v_row.proname,
      v_row.identity_args
    );

    IF v_comment IS NOT NULL THEN
      EXECUTE format(
        'COMMENT ON FUNCTION public.%I(%s) IS %L',
        v_row.proname,
        v_row.identity_args,
        v_comment
      );
    END IF;
  END LOOP;
END
$ammir_move_definer_rpcs$;

DO $ammir_private_rpc_assertions$
DECLARE
  v_public_count integer;
  v_private_count integer;
  v_expected_count integer;
BEGIN
  SELECT count(*)
  INTO v_expected_count
  FROM unnest(ARRAY[
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
    ]) AS expected(signature)
  WHERE to_regprocedure(expected.signature) IS NOT NULL
     OR to_regprocedure(replace(expected.signature, 'public.', 'app_private.')) IS NOT NULL;

  SELECT count(*)
  INTO v_public_count
  FROM pg_proc AS p
  JOIN pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND NOT p.prosecdef
    AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
    AND has_function_privilege('service_role', p.oid, 'EXECUTE');

  SELECT count(*)
  INTO v_private_count
  FROM pg_proc AS p
  JOIN pg_namespace AS n ON n.oid = p.pronamespace
  WHERE n.nspname = 'app_private'
    AND p.prosecdef
    AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
    AND has_function_privilege('service_role', p.oid, 'EXECUTE');

  IF v_expected_count = 0
     OR v_public_count <> v_expected_count
     OR v_private_count <> v_expected_count THEN
    RAISE EXCEPTION
      'RPC separation incomplete: expected %, public wrappers %, private implementations %',
      v_expected_count, v_public_count, v_private_count;
  END IF;

  IF has_schema_privilege('anon', 'app_private', 'USAGE')
     OR NOT has_schema_privilege('authenticated', 'app_private', 'USAGE') THEN
    RAISE EXCEPTION 'Unexpected app_private schema privileges';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) THEN
    RAISE EXCEPTION 'Authenticated SECURITY DEFINER functions remain in exposed public schema';
  END IF;
END
$ammir_private_rpc_assertions$;

NOTIFY pgrst, 'reload schema';

COMMIT;
