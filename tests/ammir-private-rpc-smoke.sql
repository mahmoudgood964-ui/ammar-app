\set ON_ERROR_STOP on

BEGIN;

INSERT INTO auth.users(id,email) VALUES
  ('aaaaaaaa-2000-4000-8000-000000000001','rpc-smoke-client@ammir.test'),
  ('aaaaaaaa-2000-4000-8000-000000000002','rpc-smoke-admin@ammir.test')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles(id,role) VALUES
  ('aaaaaaaa-2000-4000-8000-000000000001','client'),
  ('aaaaaaaa-2000-4000-8000-000000000002','admin')
ON CONFLICT (id) DO UPDATE SET role=EXCLUDED.role;

INSERT INTO public.ammar_conversations(
  id,context_type,context_id,subject,created_by
) VALUES (
  'bbbbbbbb-2000-4000-8000-000000000001',
  'project','rpc-wrapper-smoke','Private RPC wrapper smoke test',
  'aaaaaaaa-2000-4000-8000-000000000001'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.ammar_conversation_participants(
  conversation_id,user_id,participant_role
) VALUES
  ('bbbbbbbb-2000-4000-8000-000000000001','aaaaaaaa-2000-4000-8000-000000000001','participant'),
  ('bbbbbbbb-2000-4000-8000-000000000001','aaaaaaaa-2000-4000-8000-000000000002','participant')
ON CONFLICT (conversation_id,user_id) DO NOTHING;

INSERT INTO public.ammar_messages(
  id,conversation_id,sender_id,message_type,body
) VALUES (
  'bbbbbbbb-2000-4000-8000-000000000002',
  'bbbbbbbb-2000-4000-8000-000000000001',
  'aaaaaaaa-2000-4000-8000-000000000002',
  'text','Private RPC wrapper smoke message'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.ammar_message_receipts(message_id,user_id)
VALUES (
  'bbbbbbbb-2000-4000-8000-000000000002',
  'aaaaaaaa-2000-4000-8000-000000000001'
)
ON CONFLICT (message_id,user_id) DO NOTHING;

-- Client-facing wrappers must call the private implementations with the
-- original caller's JWT context and preserve the function results.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-2000-4000-8000-000000000001',true);

DO $ammir_client_rpc_smoke$
DECLARE
  v_count integer;
  v_presence_count integer;
BEGIN
  IF public.is_admin() IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Client wrapper is_admin returned an unexpected result';
  END IF;

  IF public.is_project_member('00000000-0000-0000-0000-000000000001'::uuid) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'Client wrapper is_project_member returned an unexpected result';
  END IF;

  IF public.ammar_is_conversation_member(
    'bbbbbbbb-2000-4000-8000-000000000001'
  ) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Conversation-member wrapper did not preserve the caller identity';
  END IF;

  IF public.ammar_project_role('missing-rpc-smoke-project') IS NOT NULL THEN
    RAISE EXCEPTION 'Project-role wrapper returned a role for a missing project';
  END IF;

  SELECT count(*) INTO v_count
  FROM public.ammar_get_conversation_presence(
    'bbbbbbbb-2000-4000-8000-000000000001',
    'aaaaaaaa-2000-4000-8000-000000000002'
  );
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Unexpected presence returned for a user without a presence row';
  END IF;

  v_count := public.ammar_mark_conversation_delivered(
    'bbbbbbbb-2000-4000-8000-000000000001'
  );
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Delivered wrapper updated %, expected 1 receipt',v_count;
  END IF;

  PERFORM public.ammar_mark_conversation_read(
    'bbbbbbbb-2000-4000-8000-000000000001'
  );

  PERFORM public.ammar_set_presence(false);

  SELECT count(*) INTO v_presence_count
  FROM public.ammar_user_presence
  WHERE user_id='aaaaaaaa-2000-4000-8000-000000000001'
    AND show_last_seen=false;
  IF v_presence_count <> 1 THEN
    RAISE EXCEPTION 'Presence wrapper did not persist the caller preference';
  END IF;
END
$ammir_client_rpc_smoke$;

-- Administrator identity remains visible to the is_admin wrapper.
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-2000-4000-8000-000000000002',true);
DO $ammir_admin_rpc_smoke$
BEGIN
  IF public.is_admin() IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Administrator wrapper is_admin did not preserve admin identity';
  END IF;
END
$ammir_admin_rpc_smoke$;

RESET ROLE;
ROLLBACK;

SELECT 'AMMIR PRIVATE RPC WRAPPER SMOKE TESTS PASSED' AS result;
