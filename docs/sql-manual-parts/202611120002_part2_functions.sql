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
  IF EXISTS (
    SELECT 1 FROM public.projects p
    WHERE p.id::text=v_inv.project_id::text AND p.client_id=auth.uid()
  ) THEN
    RAISE EXCEPTION 'The project owner does not need to accept a team invitation';
  END IF;

  UPDATE public.project_members
  SET member_role=v_inv.member_role,member_email=v_email
  WHERE project_id::text=v_inv.project_id::text AND user_id=auth.uid();

  IF NOT FOUND THEN
    INSERT INTO public.project_members(project_id,user_id,member_role,member_email)
    VALUES(v_inv.project_id,auth.uid(),v_inv.member_role,v_email);
  END IF;

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
