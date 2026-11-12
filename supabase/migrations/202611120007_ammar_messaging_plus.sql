-- AMMAR messaging upgrade: delivery/read receipts, archive, presence, blocking,
-- reporting, pinned/replied/forwarded messages, video and location, project actions.
-- Additive migration. Apply only after 202611120006_ammar_marketplace_messaging.sql.
BEGIN;

ALTER TABLE public.ammar_messages
  ADD COLUMN IF NOT EXISTS location_lat numeric(9,6),
  ADD COLUMN IF NOT EXISTS location_lng numeric(9,6),
  ADD COLUMN IF NOT EXISTS location_label text,
  ADD COLUMN IF NOT EXISTS forwarded_from_id uuid REFERENCES public.ammar_messages(id) ON DELETE SET NULL;

DO $ammar_message_type_check$
DECLARE c record;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid='public.ammar_messages'::regclass
      AND contype='c'
      AND pg_get_constraintdef(oid) ILIKE '%message_type%'
  LOOP
    EXECUTE format('ALTER TABLE public.ammar_messages DROP CONSTRAINT %I',c.conname);
  END LOOP;
END
$ammar_message_type_check$;

ALTER TABLE public.ammar_messages
  ADD CONSTRAINT ammar_messages_message_type_007_check
  CHECK (message_type IN ('text','image','file','video','location','system'));

ALTER TABLE public.ammar_messages
  ADD CONSTRAINT ammar_messages_content_007_check
  CHECK (
    (message_type IN ('text','system') AND body IS NOT NULL AND char_length(body) BETWEEN 1 AND 5000)
    OR (message_type IN ('image','file','video') AND file_path IS NOT NULL)
    OR (message_type='location' AND location_lat IS NOT NULL AND location_lng IS NOT NULL)
  );

ALTER TABLE public.ammar_messages
  ADD CONSTRAINT ammar_messages_location_coordinates_check
  CHECK (
    message_type <> 'location'
    OR (
      location_lat IS NOT NULL AND location_lng IS NOT NULL
      AND location_lat BETWEEN -90 AND 90
      AND location_lng BETWEEN -180 AND 180
    )
  );

CREATE TABLE IF NOT EXISTS public.ammar_message_receipts (
  message_id uuid NOT NULL REFERENCES public.ammar_messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  delivered_at timestamptz,
  read_at timestamptz,
  PRIMARY KEY(message_id,user_id)
);

CREATE TABLE IF NOT EXISTS public.ammar_conversation_preferences (
  conversation_id uuid NOT NULL REFERENCES public.ammar_conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  archived_at timestamptz,
  muted_until timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(conversation_id,user_id)
);

CREATE TABLE IF NOT EXISTS public.ammar_user_blocks (
  blocker_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(blocker_id,blocked_id),
  CHECK(blocker_id <> blocked_id)
);

CREATE TABLE IF NOT EXISTS public.ammar_message_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.ammar_conversations(id) ON DELETE CASCADE,
  message_id uuid NOT NULL REFERENCES public.ammar_messages(id) ON DELETE CASCADE,
  reporter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reason text NOT NULL CHECK(char_length(reason) BETWEEN 5 AND 2000),
  status text NOT NULL DEFAULT 'pending'
    CHECK(status IN ('pending','investigating','actioned','dismissed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES auth.users(id),
  UNIQUE(message_id,reporter_id)
);

CREATE TABLE IF NOT EXISTS public.ammar_pinned_messages (
  conversation_id uuid NOT NULL REFERENCES public.ammar_conversations(id) ON DELETE CASCADE,
  message_id uuid NOT NULL REFERENCES public.ammar_messages(id) ON DELETE CASCADE,
  pinned_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(conversation_id,message_id)
);

CREATE TABLE IF NOT EXISTS public.ammar_user_presence (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  show_last_seen boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ammar_messages_sender_created_idx ON public.ammar_messages(sender_id,created_at DESC);
CREATE INDEX IF NOT EXISTS ammar_message_receipts_user_idx
  ON public.ammar_message_receipts(user_id,read_at,delivered_at);
CREATE INDEX IF NOT EXISTS ammar_message_reports_status_idx
  ON public.ammar_message_reports(status,created_at DESC);
CREATE INDEX IF NOT EXISTS ammar_pinned_messages_conversation_idx
  ON public.ammar_pinned_messages(conversation_id,created_at DESC);

CREATE OR REPLACE FUNCTION public.ammar_users_blocked(p_user_a uuid,p_user_b uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.ammar_user_blocks b
    WHERE (b.blocker_id=p_user_a AND b.blocked_id=p_user_b)
       OR (b.blocker_id=p_user_b AND b.blocked_id=p_user_a)
  );
$$;

CREATE OR REPLACE FUNCTION public.ammar_guard_conversation_participant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
BEGIN
  IF EXISTS(
    SELECT 1
    FROM public.ammar_conversation_participants cp
    WHERE cp.conversation_id=NEW.conversation_id
      AND public.ammar_users_blocked(cp.user_id,NEW.user_id)
  ) THEN
    RAISE EXCEPTION 'Messaging is unavailable because one participant has blocked the other';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammar_guard_conversation_participant_trigger
  ON public.ammar_conversation_participants;
CREATE TRIGGER ammar_guard_conversation_participant_trigger
BEFORE INSERT ON public.ammar_conversation_participants
FOR EACH ROW EXECUTE FUNCTION public.ammar_guard_conversation_participant();

CREATE OR REPLACE FUNCTION public.ammar_guard_message_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE v_other uuid;
        v_recent integer;
BEGIN
  IF NEW.sender_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Message sender must match the signed-in account';
  END IF;
  IF NOT public.ammar_is_conversation_member(NEW.conversation_id) THEN
    RAISE EXCEPTION 'Conversation access denied';
  END IF;

  SELECT cp.user_id INTO v_other
  FROM public.ammar_conversation_participants cp
  WHERE cp.conversation_id=NEW.conversation_id
    AND cp.user_id<>NEW.sender_id
  LIMIT 1;

  IF v_other IS NOT NULL AND public.ammar_users_blocked(NEW.sender_id,v_other) THEN
    RAISE EXCEPTION 'You cannot send messages in this conversation';
  END IF;

  IF NEW.reply_to_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.ammar_messages m
    WHERE m.id=NEW.reply_to_id AND m.conversation_id=NEW.conversation_id
  ) THEN
    RAISE EXCEPTION 'A reply must reference a message in the same conversation';
  END IF;

  SELECT count(*) INTO v_recent
  FROM public.ammar_messages m
  WHERE m.sender_id=NEW.sender_id
    AND m.created_at>now()-interval '60 seconds';
  IF v_recent>=30 THEN
    RAISE EXCEPTION 'Message rate limit reached. Please slow down.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammar_guard_message_insert_trigger ON public.ammar_messages;
CREATE TRIGGER ammar_guard_message_insert_trigger
BEFORE INSERT ON public.ammar_messages
FOR EACH ROW EXECUTE FUNCTION public.ammar_guard_message_insert();

CREATE OR REPLACE FUNCTION public.ammar_record_message_receipts()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
BEGIN
  INSERT INTO public.ammar_message_receipts(message_id,user_id)
  SELECT NEW.id,cp.user_id
  FROM public.ammar_conversation_participants cp
  WHERE cp.conversation_id=NEW.conversation_id
    AND cp.user_id<>NEW.sender_id
  ON CONFLICT(message_id,user_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammar_record_message_receipts_trigger ON public.ammar_messages;
CREATE TRIGGER ammar_record_message_receipts_trigger
AFTER INSERT ON public.ammar_messages
FOR EACH ROW EXECUTE FUNCTION public.ammar_record_message_receipts();

CREATE OR REPLACE FUNCTION public.ammar_mark_conversation_delivered(p_conversation_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE v_count integer;
BEGIN
  IF auth.uid() IS NULL OR NOT public.ammar_is_conversation_member(p_conversation_id) THEN
    RAISE EXCEPTION 'Conversation access denied';
  END IF;
  UPDATE public.ammar_message_receipts mr
  SET delivered_at=coalesce(mr.delivered_at,now())
  FROM public.ammar_messages m
  WHERE mr.message_id=m.id
    AND mr.user_id=auth.uid()
    AND m.conversation_id=p_conversation_id;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.ammar_mark_conversation_read(p_conversation_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.ammar_is_conversation_member(p_conversation_id) THEN
    RAISE EXCEPTION 'Conversation access denied';
  END IF;
  UPDATE public.ammar_message_receipts mr
  SET delivered_at=coalesce(mr.delivered_at,now()),
      read_at=coalesce(mr.read_at,now())
  FROM public.ammar_messages m
  WHERE mr.message_id=m.id AND m.conversation_id=p_conversation_id
    AND mr.user_id=auth.uid();
  UPDATE public.ammar_conversation_participants
  SET last_read_at=now()
  WHERE conversation_id=p_conversation_id AND user_id=auth.uid();
  UPDATE public.ammar_user_notifications
  SET read_at=coalesce(read_at,now())
  WHERE user_id=auth.uid() AND conversation_id=p_conversation_id AND read_at IS NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.ammar_set_presence(p_show_last_seen boolean DEFAULT true)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  INSERT INTO public.ammar_user_presence(user_id,last_seen_at,show_last_seen,updated_at)
  VALUES(auth.uid(),now(),coalesce(p_show_last_seen,true),now())
  ON CONFLICT(user_id) DO UPDATE SET
    last_seen_at=now(),
    show_last_seen=coalesce(p_show_last_seen,public.ammar_user_presence.show_last_seen),
    updated_at=now();
END;
$$;

CREATE OR REPLACE FUNCTION public.ammar_get_conversation_presence(
  p_conversation_id uuid,
  p_other_user uuid
)
RETURNS TABLE(last_seen_at timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.ammar_is_conversation_member(p_conversation_id)
     OR NOT EXISTS(
       SELECT 1 FROM public.ammar_conversation_participants cp
       WHERE cp.conversation_id=p_conversation_id AND cp.user_id=p_other_user
     ) THEN
    RAISE EXCEPTION 'Conversation access denied';
  END IF;
  RETURN QUERY
  SELECT p.last_seen_at
  FROM public.ammar_user_presence p
  WHERE p.user_id=p_other_user AND p.show_last_seen=true;
END;
$$;

CREATE OR REPLACE FUNCTION public.ammar_forward_message(
  p_message_id uuid,
  p_target_conversation_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE v_source public.ammar_messages%ROWTYPE;
        v_new_id uuid;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.ammar_is_conversation_member(p_target_conversation_id) THEN
    RAISE EXCEPTION 'Target conversation access denied';
  END IF;
  SELECT * INTO v_source FROM public.ammar_messages m
  WHERE m.id=p_message_id
    AND public.ammar_is_conversation_member(m.conversation_id);
  IF NOT FOUND OR v_source.message_type<>'text' OR v_source.body IS NULL THEN
    RAISE EXCEPTION 'Only accessible text messages can be forwarded';
  END IF;
  INSERT INTO public.ammar_messages(
    conversation_id,sender_id,message_type,body,forwarded_from_id
  )
  VALUES(p_target_conversation_id,auth.uid(),'text',v_source.body,v_source.id)
  RETURNING id INTO v_new_id;
  RETURN v_new_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.ammar_message_to_project_task(p_message_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE v_message public.ammar_messages%ROWTYPE;
        v_project_id text;
        v_project_type text;
        v_title text;
        v_id uuid;
BEGIN
  SELECT m.* INTO v_message
  FROM public.ammar_messages m
  WHERE m.id=p_message_id
    AND public.ammar_is_conversation_member(m.conversation_id);
  IF NOT FOUND THEN RAISE EXCEPTION 'Message not found or access denied'; END IF;
  SELECT c.context_id INTO v_project_id
  FROM public.ammar_conversations c
  WHERE c.id=v_message.conversation_id AND c.context_type='project';
  IF v_project_id IS NULL OR public.ammar_project_role(v_project_id) NOT IN ('owner','manager','supervisor','engineer') THEN
    RAISE EXCEPTION 'Only authorised members of a project conversation can create tasks';
  END IF;
  SELECT format_type(a.atttypid,a.atttypmod) INTO v_project_type
  FROM pg_attribute a WHERE a.attrelid='public.projects'::regclass AND a.attname='id' AND NOT a.attisdropped;
  IF v_project_type IS NULL THEN RAISE EXCEPTION 'Project identifier type not found'; END IF;
  v_title:=left(coalesce(nullif(trim(v_message.body),''),nullif(v_message.file_name,''),'مهمة من محادثة عَمِّر'),180);
  EXECUTE format(
    'INSERT INTO public.project_tasks(project_id,title,details,status) VALUES($1::%s,$2,$3,''todo'') RETURNING id',
    v_project_type
  ) INTO v_id USING v_project_id,v_title,coalesce(v_message.body,'تم إنشاء المهمة من رسالة داخل عَمِّر.');
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.ammar_message_to_change_order(
  p_message_id uuid,
  p_title text,
  p_reason text,
  p_cost_impact numeric DEFAULT 0,
  p_currency text DEFAULT 'SDG',
  p_days_impact integer DEFAULT 0
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public,pg_temp
AS $$
DECLARE v_message public.ammar_messages%ROWTYPE;
        v_project_id text;
        v_project_type text;
        v_id uuid;
BEGIN
  IF char_length(trim(coalesce(p_title,''))) NOT BETWEEN 1 AND 240
     OR char_length(trim(coalesce(p_reason,''))) NOT BETWEEN 1 AND 5000
     OR coalesce(p_cost_impact,0)<0 OR coalesce(p_days_impact,0)<0 THEN
    RAISE EXCEPTION 'Invalid change request details';
  END IF;
  SELECT m.* INTO v_message FROM public.ammar_messages m
  WHERE m.id=p_message_id AND public.ammar_is_conversation_member(m.conversation_id);
  IF NOT FOUND THEN RAISE EXCEPTION 'Message not found or access denied'; END IF;
  SELECT c.context_id INTO v_project_id
  FROM public.ammar_conversations c
  WHERE c.id=v_message.conversation_id AND c.context_type='project';
  IF v_project_id IS NULL OR public.ammar_project_role(v_project_id) NOT IN ('owner','manager','supervisor','engineer') THEN
    RAISE EXCEPTION 'Only authorised members of a project conversation can create change requests';
  END IF;
  SELECT format_type(a.atttypid,a.atttypmod) INTO v_project_type
  FROM pg_attribute a WHERE a.attrelid='public.projects'::regclass AND a.attname='id' AND NOT a.attisdropped;
  IF v_project_type IS NULL THEN RAISE EXCEPTION 'Project identifier type not found'; END IF;
  EXECUTE format(
    'INSERT INTO public.project_change_orders(project_id,title,reason,cost_impact,currency,days_impact,requested_by) VALUES($1::%s,$2,$3,$4,$5,$6,$7) RETURNING id',
    v_project_type
  ) INTO v_id USING v_project_id,trim(p_title),trim(p_reason),coalesce(p_cost_impact,0),p_currency,coalesce(p_days_impact,0),auth.uid();
  RETURN v_id;
END;
$$;

ALTER TABLE public.ammar_message_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_conversation_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_user_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_message_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_pinned_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_user_presence ENABLE ROW LEVEL SECURITY;

CREATE POLICY ammar_receipts_member_select ON public.ammar_message_receipts
FOR SELECT TO authenticated USING (
  user_id=auth.uid()
  OR EXISTS(SELECT 1 FROM public.ammar_messages m
    WHERE m.id=message_id AND public.ammar_is_conversation_member(m.conversation_id))
);
CREATE POLICY ammar_receipts_self_update ON public.ammar_message_receipts
FOR UPDATE TO authenticated USING(user_id=auth.uid()) WITH CHECK(user_id=auth.uid());

CREATE POLICY ammar_conversation_preferences_self_all ON public.ammar_conversation_preferences
FOR ALL TO authenticated USING(user_id=auth.uid() AND public.ammar_is_conversation_member(conversation_id))
WITH CHECK(user_id=auth.uid() AND public.ammar_is_conversation_member(conversation_id));

CREATE POLICY ammar_blocks_self_select ON public.ammar_user_blocks
FOR SELECT TO authenticated USING(blocker_id=auth.uid());
CREATE POLICY ammar_blocks_self_insert ON public.ammar_user_blocks
FOR INSERT TO authenticated WITH CHECK(blocker_id=auth.uid());
CREATE POLICY ammar_blocks_self_delete ON public.ammar_user_blocks
FOR DELETE TO authenticated USING(blocker_id=auth.uid());

CREATE POLICY ammar_message_reports_reporter_select ON public.ammar_message_reports
FOR SELECT TO authenticated USING(reporter_id=auth.uid());
CREATE POLICY ammar_message_reports_participant_insert ON public.ammar_message_reports
FOR INSERT TO authenticated WITH CHECK(
  reporter_id=auth.uid()
  AND public.ammar_is_conversation_member(conversation_id)
  AND EXISTS(SELECT 1 FROM public.ammar_messages m
    WHERE m.id=ammar_message_reports.message_id
      AND m.conversation_id=ammar_message_reports.conversation_id
      AND m.sender_id<>auth.uid())
);

CREATE POLICY ammar_pinned_messages_member_select ON public.ammar_pinned_messages
FOR SELECT TO authenticated USING(public.ammar_is_conversation_member(conversation_id));
CREATE POLICY ammar_pinned_messages_member_insert ON public.ammar_pinned_messages
FOR INSERT TO authenticated WITH CHECK(
  pinned_by=auth.uid()
  AND public.ammar_is_conversation_member(conversation_id)
  AND EXISTS(SELECT 1 FROM public.ammar_messages m WHERE m.id=message_id AND m.conversation_id=conversation_id)
);
CREATE POLICY ammar_pinned_messages_owner_delete ON public.ammar_pinned_messages
FOR DELETE TO authenticated USING(pinned_by=auth.uid());

CREATE POLICY ammar_presence_self_all ON public.ammar_user_presence
FOR ALL TO authenticated USING(user_id=auth.uid()) WITH CHECK(user_id=auth.uid());

GRANT SELECT,UPDATE ON public.ammar_message_receipts TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.ammar_conversation_preferences TO authenticated;
GRANT SELECT,INSERT,DELETE ON public.ammar_user_blocks TO authenticated;
GRANT SELECT,INSERT ON public.ammar_message_reports TO authenticated;
GRANT SELECT,INSERT,DELETE ON public.ammar_pinned_messages TO authenticated;
GRANT SELECT,INSERT,UPDATE ON public.ammar_user_presence TO authenticated;

REVOKE ALL ON FUNCTION public.ammar_users_blocked(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_guard_conversation_participant() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_guard_message_insert() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_record_message_receipts() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_mark_conversation_delivered(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_mark_conversation_read(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_set_presence(boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_get_conversation_presence(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_forward_message(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_message_to_project_task(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_message_to_change_order(uuid,text,text,numeric,text,integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.ammar_mark_conversation_delivered(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_mark_conversation_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_set_presence(boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_get_conversation_presence(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_forward_message(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_message_to_project_task(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_message_to_change_order(uuid,text,text,numeric,text,integer) TO authenticated;

UPDATE storage.buckets
SET file_size_limit=52428800,
    allowed_mime_types=ARRAY[
      'image/jpeg','image/png','image/webp','application/pdf',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'video/mp4','video/webm','video/quicktime'
    ]
WHERE id='ammar-chat-files';

-- Enable realtime for delivery receipts and presence where the publication is available.
DO $ammar_realtime_plus$
DECLARE t text;
BEGIN
  IF EXISTS(SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime') THEN
    FOREACH t IN ARRAY ARRAY['ammar_message_receipts','ammar_conversation_preferences','ammar_user_presence']
    LOOP
      IF NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename=t) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I',t);
      END IF;
    END LOOP;
  END IF;
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'Realtime messaging metadata publication could not be updated automatically.';
END
$ammar_realtime_plus$;

COMMIT;
