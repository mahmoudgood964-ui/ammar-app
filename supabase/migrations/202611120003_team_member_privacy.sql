-- Tighten team roster privacy after the collaboration policies migration.
-- Owners can view the full roster; each team member can view only their own membership row.
DROP POLICY IF EXISTS project_members_project_read ON public.project_members;
DROP POLICY IF EXISTS project_members_owner_or_self_select ON public.project_members;

CREATE POLICY project_members_owner_or_self_select ON public.project_members
FOR SELECT TO authenticated USING (
  user_id = auth.uid()
  OR public.ammar_project_role(project_id::text) = 'owner'
);

GRANT SELECT ON public.project_members TO authenticated;
