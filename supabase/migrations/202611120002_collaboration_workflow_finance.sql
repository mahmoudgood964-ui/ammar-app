-- AMMAR collaboration, workflow, finance, audit and notification layer
-- Apply once in Supabase SQL Editor after the existing project_management migration.
-- Existing project and module records are preserved.

ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'planning',
  ADD COLUMN IF NOT EXISTS start_date date,
  ADD COLUMN IF NOT EXISTS target_end_date date,
  ADD COLUMN IF NOT EXISTS completed_at timestamptz,
  ADD COLUMN IF NOT EXISTS budget_amount numeric(14,2),
  ADD COLUMN IF NOT EXISTS budget_currency text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.projects'::regclass
      AND conname = 'projects_ammar_status_check'
  ) THEN
    ALTER TABLE public.projects
      ADD CONSTRAINT projects_ammar_status_check
      CHECK (status IN ('planning','approved','in_progress','on_hold','completed','cancelled')) NOT VALID;
  END IF;
END $$;

DO $$
DECLARE project_id_type text;
BEGIN
  SELECT format_type(a.atttypid, a.atttypmod)
    INTO project_id_type
  FROM pg_attribute a
  WHERE a.attrelid = 'public.projects'::regclass
    AND a.attname = 'id' AND NOT a.attisdropped;

  IF project_id_type IS NULL THEN
    RAISE EXCEPTION 'Could not determine public.projects.id type';
  END IF;

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_invitations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    email text NOT NULL,
    member_role text NOT NULL CHECK (member_role IN (''manager'',''supervisor'',''engineer'',''accountant'',''worker'',''viewer'')),
    invite_token text NOT NULL UNIQUE,
    status text NOT NULL DEFAULT ''pending'' CHECK (status IN (''pending'',''accepted'',''revoked'',''expired'')),
    expires_at timestamptz NOT NULL,
    created_by uuid NOT NULL DEFAULT auth.uid(),
    created_at timestamptz NOT NULL DEFAULT now(),
    accepted_by uuid,
    accepted_at timestamptz
  )', project_id_type);

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_activity (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    actor_id uuid DEFAULT auth.uid(),
    event_type text NOT NULL,
    summary text NOT NULL CHECK (char_length(summary) BETWEEN 1 AND 500),
    entity_type text,
    entity_id text,
    metadata jsonb NOT NULL DEFAULT ''{}''::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_comments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    author_id uuid NOT NULL DEFAULT auth.uid(),
    message text NOT NULL CHECK (char_length(message) BETWEEN 1 AND 4000),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_payments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    description text NOT NULL CHECK (char_length(description) BETWEEN 1 AND 240),
    amount numeric(14,2) NOT NULL CHECK (amount >= 0),
    currency text,
    due_date date,
    paid_on date,
    status text NOT NULL DEFAULT ''planned'' CHECK (status IN (''planned'',''paid'',''cancelled'')),
    payment_method text,
    reference text,
    notes text,
    created_by uuid DEFAULT auth.uid(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    user_id uuid NOT NULL,
    actor_id uuid,
    title text NOT NULL,
    body text,
    read_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);
END $$;

CREATE INDEX IF NOT EXISTS project_invitations_project_idx ON public.project_invitations(project_id, created_at DESC);
CREATE INDEX IF NOT EXISTS project_activity_project_idx ON public.project_activity(project_id, created_at DESC);
CREATE INDEX IF NOT EXISTS project_comments_project_idx ON public.project_comments(project_id, created_at DESC);
CREATE INDEX IF NOT EXISTS project_payments_project_idx ON public.project_payments(project_id, due_date DESC);
CREATE INDEX IF NOT EXISTS project_notifications_user_idx ON public.project_notifications(user_id, created_at DESC);

-- Store the invited email on the membership record so the roster is usable without exposing auth.users.
ALTER TABLE public.project_members ADD COLUMN IF NOT EXISTS member_email text;

-- Keep modification timestamps reliable even when writes come from another client.
CREATE OR REPLACE FUNCTION public.ammar_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammar_projects_touch_updated_at ON public.projects;
CREATE TRIGGER ammar_projects_touch_updated_at
BEFORE UPDATE ON public.projects
FOR EACH ROW EXECUTE FUNCTION public.ammar_touch_updated_at();

DROP TRIGGER IF EXISTS ammar_project_tasks_touch_updated_at ON public.project_tasks;
CREATE TRIGGER ammar_project_tasks_touch_updated_at
BEFORE UPDATE ON public.project_tasks
FOR EACH ROW EXECUTE FUNCTION public.ammar_touch_updated_at();

DROP TRIGGER IF EXISTS ammar_project_comments_touch_updated_at ON public.project_comments;
CREATE TRIGGER ammar_project_comments_touch_updated_at
BEFORE UPDATE ON public.project_comments
FOR EACH ROW EXECUTE FUNCTION public.ammar_touch_updated_at();

DROP TRIGGER IF EXISTS ammar_project_payments_touch_updated_at ON public.project_payments;
CREATE TRIGGER ammar_project_payments_touch_updated_at
BEFORE UPDATE ON public.project_payments
FOR EACH ROW EXECUTE FUNCTION public.ammar_touch_updated_at();

CREATE OR REPLACE FUNCTION public.ammar_set_project_completion_time()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status='completed' AND OLD.status IS DISTINCT FROM 'completed' AND NEW.completed_at IS NULL THEN
    NEW.completed_at := now();
  ELSIF NEW.status<>'completed' THEN
    NEW.completed_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammar_projects_completion_time ON public.projects;
CREATE TRIGGER ammar_projects_completion_time
BEFORE UPDATE OF status ON public.projects
FOR EACH ROW EXECUTE FUNCTION public.ammar_set_project_completion_time();

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.projects'::regclass AND conname='projects_ammar_budget_nonnegative') THEN
    ALTER TABLE public.projects ADD CONSTRAINT projects_ammar_budget_nonnegative
      CHECK (budget_amount IS NULL OR budget_amount >= 0) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.projects'::regclass AND conname='projects_ammar_dates_check') THEN
    ALTER TABLE public.projects ADD CONSTRAINT projects_ammar_dates_check
      CHECK (start_date IS NULL OR target_end_date IS NULL OR target_end_date >= start_date) NOT VALID;
  END IF;
END $$;

-- Resolve project membership in a SECURITY DEFINER function to avoid RLS recursion.
CREATE OR REPLACE FUNCTION public.ammar_project_role(p_project_id text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_role text;
BEGIN
  IF auth.uid() IS NULL OR p_project_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.projects p
    WHERE p.id::text = p_project_id AND p.client_id = auth.uid()
  ) THEN
    RETURN 'owner';
  END IF;

  SELECT pm.member_role::text
    INTO v_role
  FROM public.project_members pm
  WHERE pm.project_id::text = p_project_id
    AND pm.user_id = auth.uid()
  LIMIT 1;

  IF v_role IN ('admin','project_manager','owner') THEN RETURN 'manager'; END IF;
  IF v_role IN ('member','technician') THEN RETURN 'worker'; END IF;
  RETURN v_role;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ammar_project_role(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.ammar_create_project_invitation(
  p_project_id text,
  p_email text,
  p_role text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_token text;
  v_expires timestamptz := now() + interval '7 days';
  v_project_id text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.projects p
    WHERE p.id::text = p_project_id AND p.client_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Only the project owner can invite team members';
  END IF;
  IF p_role NOT IN ('manager','supervisor','engineer','accountant','worker','viewer') THEN
    RAISE EXCEPTION 'Invalid project role';
  END IF;
  IF p_email IS NULL OR length(trim(p_email)) < 5 OR position('@' in p_email) < 2 THEN
    RAISE EXCEPTION 'A valid email address is required';
  END IF;

  v_token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  INSERT INTO public.project_invitations(project_id,email,member_role,invite_token,expires_at,created_by)
  SELECT p.id, lower(trim(p_email)), p_role, v_token, v_expires, auth.uid()
  FROM public.projects p
  WHERE p.id::text = p_project_id AND p.client_id = auth.uid()
  RETURNING project_id::text INTO v_project_id;

  RETURN jsonb_build_object('token',v_token,'project_id',v_project_id,'expires_at',v_expires);
END;
$$;

CREATE OR REPLACE FUNCTION public.ammar_accept_project_invitation(p_token text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_inv public.project_invitations%ROWTYPE;
        v_email text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in before accepting an invitation'; END IF;
  v_email := lower(coalesce(auth.jwt()->>'email',''));
  SELECT * INTO v_inv
  FROM public.project_invitations
  WHERE invite_token = p_token
    AND status = 'pending'
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Invitation is invalid, expired, or already used'; END IF;
  IF v_inv.expires_at <= now() THEN
    RAISE EXCEPTION 'Invitation has expired';
  END IF;
  IF v_email <> lower(v_inv.email) THEN
    RAISE EXCEPTION 'Sign in with the email address that received this invitation';
  END IF;

  INSERT INTO public.project_members(project_id,user_id,member_role,member_email)
  SELECT v_inv.project_id,auth.uid(),v_inv.member_role,v_email
  WHERE NOT EXISTS (
    SELECT 1 FROM public.project_members pm
    WHERE pm.project_id::text = v_inv.project_id::text AND pm.user_id = auth.uid()
  );

  UPDATE public.project_invitations
  SET status='accepted',accepted_by=auth.uid(),accepted_at=now()
  WHERE id=v_inv.id;

  INSERT INTO public.project_activity(project_id,actor_id,event_type,summary,entity_type,metadata)
  VALUES(v_inv.project_id,auth.uid(),'member_joined','انضم عضو جديد إلى فريق المشروع','team',
         jsonb_build_object('email',v_inv.email,'role',v_inv.member_role));

  RETURN jsonb_build_object('project_id',v_inv.project_id::text,'role',v_inv.member_role);
END;
$$;

CREATE OR REPLACE FUNCTION public.ammar_update_project_member_role(
  p_project_id text,
  p_user_id uuid,
  p_role text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.projects p
    WHERE p.id::text=p_project_id AND p.client_id=auth.uid()
  ) THEN RAISE EXCEPTION 'Only the project owner can change team roles'; END IF;
  IF p_role NOT IN ('manager','supervisor','engineer','accountant','worker','viewer') THEN
    RAISE EXCEPTION 'Invalid project role';
  END IF;
  UPDATE public.project_members
  SET member_role=p_role
  WHERE project_id::text=p_project_id AND user_id=p_user_id;
  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.ammar_remove_project_member(
  p_project_id text,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.projects p
    WHERE p.id::text=p_project_id AND p.client_id=auth.uid()
  ) THEN RAISE EXCEPTION 'Only the project owner can remove team members'; END IF;
  DELETE FROM public.project_members
  WHERE project_id::text=p_project_id AND user_id=p_user_id;
  RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ammar_create_project_invitation(text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_accept_project_invitation(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_update_project_member_role(text,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_remove_project_member(text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.ammar_revoke_project_invitation(
  p_project_id text,
  p_invitation_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_project_id text;
        v_email text;
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.projects p
    WHERE p.id::text=p_project_id AND p.client_id=auth.uid()
  ) THEN RAISE EXCEPTION 'Only the project owner can revoke invitations'; END IF;

  UPDATE public.project_invitations
  SET status='revoked'
  WHERE id=p_invitation_id
    AND project_id::text=p_project_id
    AND status='pending'
  RETURNING project_id::text,email INTO v_project_id,v_email;

  IF NOT FOUND THEN RAISE EXCEPTION 'Pending invitation not found'; END IF;

  INSERT INTO public.project_activity(project_id,actor_id,event_type,summary,entity_type,metadata)
  SELECT p.id,auth.uid(),'invitation_revoked','تم إلغاء دعوة عضو: '||v_email,'team',
         jsonb_build_object('email',v_email)
  FROM public.projects p WHERE p.id::text=p_project_id;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.ammar_revoke_project_invitation(text,uuid) TO authenticated;

-- Replace legacy owner-only module policies with role-aware policies.
DO $$
DECLARE t text;
        pol record;
        v_insert text;
        v_update text;
        v_delete text;
BEGIN
  FOREACH t IN ARRAY ARRAY['project_tasks','project_expenses','project_quotes','project_updates','project_documents']
  LOOP
    FOR pol IN SELECT policyname FROM pg_policies
      WHERE schemaname='public' AND tablename=t
    LOOP
      EXECUTE format('DROP POLICY %I ON public.%I',pol.policyname,t);
    END LOOP;

    IF t='project_tasks' THEN
      v_insert := '''owner'',''manager'',''supervisor'',''engineer'',''worker''';
    ELSIF t IN ('project_expenses','project_quotes') THEN
      v_insert := '''owner'',''manager'',''accountant''';
    ELSIF t='project_updates' THEN
      v_insert := '''owner'',''manager'',''supervisor'',''engineer'',''worker''';
    ELSE
      v_insert := '''owner'',''manager'',''supervisor'',''engineer'',''accountant'',''worker''';
    END IF;

    EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (public.ammar_project_role(project_id::text) IS NOT NULL)',t||'_member_select',t);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR INSERT TO authenticated WITH CHECK (public.ammar_project_role(project_id::text) IN (%s))',t||'_role_insert',t,v_insert);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR UPDATE TO authenticated USING (public.ammar_project_role(project_id::text) IN (%s)) WITH CHECK (public.ammar_project_role(project_id::text) IN (%s))',t||'_role_update',t,v_insert,v_insert);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR DELETE TO authenticated USING (public.ammar_project_role(project_id::text) IN (''owner'',''manager''))',t||'_role_delete',t);
  END LOOP;
END $$;

-- Team membership visibility: members see their own row; owners can see the whole roster.
ALTER TABLE public.project_members ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol record;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies
    WHERE schemaname='public' AND tablename='project_members'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.project_members',pol.policyname);
  END LOOP;
END $$;

DROP POLICY IF EXISTS project_members_self_select ON public.project_members;
DROP POLICY IF EXISTS project_members_owner_select ON public.project_members;
CREATE POLICY project_members_project_read ON public.project_members
FOR SELECT TO authenticated USING (
  public.ammar_project_role(project_id::text) IS NOT NULL
);

-- Project invitations are private and administered only through the SECURITY DEFINER RPCs.
ALTER TABLE public.project_invitations ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS project_invitations_owner_select ON public.project_invitations;
CREATE POLICY project_invitations_owner_select ON public.project_invitations
FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.projects p
          WHERE p.id=project_invitations.project_id AND p.client_id=auth.uid())
);

-- Shared projects are visible to their members; existing owner policies remain in place.
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS projects_member_select ON public.projects;
CREATE POLICY projects_member_select ON public.projects
FOR SELECT TO authenticated USING (public.ammar_project_role(id::text) IS NOT NULL);

-- Collaboration and finance data.
ALTER TABLE public.project_activity ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS project_activity_member_select ON public.project_activity;
DROP POLICY IF EXISTS project_activity_member_insert ON public.project_activity;
CREATE POLICY project_activity_member_select ON public.project_activity
FOR SELECT TO authenticated USING (public.ammar_project_role(project_id::text) IS NOT NULL);
CREATE POLICY project_activity_member_insert ON public.project_activity
FOR INSERT TO authenticated WITH CHECK (
  actor_id=auth.uid()
  AND public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer','accountant','worker')
);

ALTER TABLE public.project_comments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS project_comments_member_select ON public.project_comments;
DROP POLICY IF EXISTS project_comments_member_insert ON public.project_comments;
DROP POLICY IF EXISTS project_comments_author_delete ON public.project_comments;
CREATE POLICY project_comments_member_select ON public.project_comments
FOR SELECT TO authenticated USING (public.ammar_project_role(project_id::text) IS NOT NULL);
CREATE POLICY project_comments_member_insert ON public.project_comments
FOR INSERT TO authenticated WITH CHECK (
  author_id=auth.uid()
  AND public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer','accountant','worker')
);
CREATE POLICY project_comments_author_delete ON public.project_comments
FOR DELETE TO authenticated USING (
  author_id=auth.uid() OR public.ammar_project_role(project_id::text) IN ('owner','manager')
);

ALTER TABLE public.project_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS project_payments_member_select ON public.project_payments;
DROP POLICY IF EXISTS project_payments_finance_insert ON public.project_payments;
DROP POLICY IF EXISTS project_payments_finance_update ON public.project_payments;
DROP POLICY IF EXISTS project_payments_finance_delete ON public.project_payments;
CREATE POLICY project_payments_member_select ON public.project_payments
FOR SELECT TO authenticated USING (public.ammar_project_role(project_id::text) IS NOT NULL);
CREATE POLICY project_payments_finance_insert ON public.project_payments
FOR INSERT TO authenticated WITH CHECK (
  created_by=auth.uid()
  AND public.ammar_project_role(project_id::text) IN ('owner','manager','accountant')
);
CREATE POLICY project_payments_finance_update ON public.project_payments
FOR UPDATE TO authenticated USING (
  public.ammar_project_role(project_id::text) IN ('owner','manager','accountant')
) WITH CHECK (
  public.ammar_project_role(project_id::text) IN ('owner','manager','accountant')
);
CREATE POLICY project_payments_finance_delete ON public.project_payments
FOR DELETE TO authenticated USING (
  public.ammar_project_role(project_id::text) IN ('owner','manager')
);

ALTER TABLE public.project_notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS project_notifications_self_select ON public.project_notifications;
DROP POLICY IF EXISTS project_notifications_self_update ON public.project_notifications;
CREATE POLICY project_notifications_self_select ON public.project_notifications
FOR SELECT TO authenticated USING (user_id=auth.uid());
CREATE POLICY project_notifications_self_update ON public.project_notifications
FOR UPDATE TO authenticated USING (user_id=auth.uid()) WITH CHECK (user_id=auth.uid());

-- Notify project owners and team members whenever a timeline event is recorded.
CREATE OR REPLACE FUNCTION public.ammar_notify_project_activity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.project_notifications(project_id,user_id,actor_id,title,body)
  SELECT NEW.project_id, recipients.user_id, NEW.actor_id,
         'تحديث في مشروع عَمِّر', NEW.summary
  FROM (
    SELECT p.client_id AS user_id
    FROM public.projects p WHERE p.id=NEW.project_id
    UNION
    SELECT pm.user_id
    FROM public.project_members pm WHERE pm.project_id=NEW.project_id
  ) recipients
  WHERE recipients.user_id IS NOT NULL
    AND recipients.user_id IS DISTINCT FROM NEW.actor_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammar_project_activity_notify ON public.project_activity;
CREATE TRIGGER ammar_project_activity_notify
AFTER INSERT ON public.project_activity
FOR EACH ROW EXECUTE FUNCTION public.ammar_notify_project_activity();

-- Storage access follows project membership. Paths remain user-id/project-id/file.
DROP POLICY IF EXISTS ammar_project_files_owner_select ON storage.objects;
DROP POLICY IF EXISTS ammar_project_files_owner_insert ON storage.objects;
DROP POLICY IF EXISTS ammar_project_files_owner_delete ON storage.objects;
DROP POLICY IF EXISTS ammar_project_files_member_select ON storage.objects;
DROP POLICY IF EXISTS ammar_project_files_member_insert ON storage.objects;
DROP POLICY IF EXISTS ammar_project_files_member_delete ON storage.objects;

CREATE POLICY ammar_project_files_member_select ON storage.objects
FOR SELECT TO authenticated USING (
  bucket_id='ammar-project-files'
  AND public.ammar_project_role((storage.foldername(name))[2]) IS NOT NULL
);
CREATE POLICY ammar_project_files_member_insert ON storage.objects
FOR INSERT TO authenticated WITH CHECK (
  bucket_id='ammar-project-files'
  AND (storage.foldername(name))[1]=auth.uid()::text
  AND public.ammar_project_role((storage.foldername(name))[2]) IN ('owner','manager','supervisor','engineer','accountant','worker')
);
CREATE POLICY ammar_project_files_member_delete ON storage.objects
FOR DELETE TO authenticated USING (
  bucket_id='ammar-project-files'
  AND public.ammar_project_role((storage.foldername(name))[2]) IN ('owner','manager')
);

GRANT SELECT, INSERT ON public.project_activity, public.project_comments TO authenticated;
GRANT DELETE ON public.project_comments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.project_payments TO authenticated;
REVOKE ALL ON public.project_notifications FROM authenticated;
GRANT SELECT ON public.project_notifications TO authenticated;
GRANT UPDATE (read_at) ON public.project_notifications TO authenticated;
REVOKE ALL ON public.project_invitations FROM authenticated;
GRANT SELECT (id, project_id, email, member_role, status, expires_at, created_at) ON public.project_invitations TO authenticated;
GRANT SELECT ON public.project_members TO authenticated;
GRANT SELECT ON public.project_activity, public.project_comments, public.project_payments, public.project_notifications TO authenticated;

-- Keep all SECURITY DEFINER entry points unavailable to anonymous/public callers.
REVOKE EXECUTE ON FUNCTION public.ammar_project_role(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ammar_create_project_invitation(text,text,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ammar_accept_project_invitation(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ammar_update_project_member_role(text,uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ammar_remove_project_member(text,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ammar_revoke_project_invitation(text,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ammar_notify_project_activity() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ammar_touch_updated_at() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ammar_set_project_completion_time() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.ammar_project_role(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_create_project_invitation(text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_accept_project_invitation(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_update_project_member_role(text,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_remove_project_member(text,uuid) TO authenticated;

