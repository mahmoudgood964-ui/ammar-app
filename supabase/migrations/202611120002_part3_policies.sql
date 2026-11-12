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
