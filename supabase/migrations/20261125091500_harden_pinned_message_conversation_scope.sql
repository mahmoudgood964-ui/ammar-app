-- Correctly bind a pinned message to the conversation row being inserted.
-- Also remove anonymous table privileges where every intended policy is authenticated-only.
BEGIN;

DROP POLICY IF EXISTS ammar_pinned_messages_member_insert
  ON public.ammar_pinned_messages;

CREATE POLICY ammar_pinned_messages_member_insert
ON public.ammar_pinned_messages
FOR INSERT TO authenticated
WITH CHECK (
  pinned_by = (SELECT auth.uid())
  AND public.ammar_is_conversation_member(conversation_id)
  AND EXISTS (
    SELECT 1
    FROM public.ammar_messages AS m
    WHERE m.id = ammar_pinned_messages.message_id
      AND m.conversation_id = ammar_pinned_messages.conversation_id
  )
);

REVOKE ALL ON TABLE public.profiles FROM anon;
REVOKE ALL ON TABLE public.project_members FROM anon;
REVOKE ALL ON TABLE public.ammar_pinned_messages FROM anon;

COMMIT;
