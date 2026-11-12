-- Harden all public SECURITY DEFINER entry points after migrations 006 and 007.
-- Trigger-only functions and internal helpers are not directly executable by API roles.
DO $ammar_revoke_definer$
DECLARE f record;
BEGIN
  FOR f IN
    SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosecdef
  LOOP
    EXECUTE format(
      'REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM PUBLIC, anon, authenticated',
      f.proname, f.args
    );
  END LOOP;
END
$ammar_revoke_definer$;

-- Project authorization helpers are required by RLS predicates.
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_project_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_project_role(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_is_conversation_member(uuid) TO authenticated;

-- Project invitations and membership management.
GRANT EXECUTE ON FUNCTION public.ammar_create_project_invitation(text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_accept_project_invitation(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_update_project_member_role(text,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_remove_project_member(text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_revoke_project_invitation(text,uuid) TO authenticated;

-- Marketplace, service and agreement workflows.
GRANT EXECUTE ON FUNCTION public.ammar_accept_agreement(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_accept_market_quote(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_accept_service_offer(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_advance_market_request(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_complete_service_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_create_market_request(uuid,uuid,numeric,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_start_conversation(uuid,text,text,text) TO authenticated;

-- Messaging actions explicitly called by the signed-in client.
GRANT EXECUTE ON FUNCTION public.ammar_mark_conversation_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_mark_conversation_delivered(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_set_presence(boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_get_conversation_presence(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_forward_message(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_message_to_project_task(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_message_to_change_order(uuid,text,text,numeric,text,integer) TO authenticated;
