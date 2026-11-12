-- Performance-only RLS normalization.
-- Wrap direct auth.uid() calls in scalar SELECTs so PostgreSQL can evaluate them
-- once per statement instead of once per candidate row.
-- The duplicate projects_member_select policy is redundant: projects_read already
-- covers the project owner, project_members, and admins through equivalent checks.
-- The deferred bank milestone/event tables are intentionally excluded.

DO $ammar_rls_uid_initplan$
DECLARE
  p record;
  v_qual text;
  v_check text;
BEGIN
  FOR p IN
    SELECT schemaname,tablename,policyname,qual,with_check
    FROM pg_policies
    WHERE schemaname='public'
      AND tablename NOT IN ('project_payment_milestones','project_payment_events')
      AND (
        coalesce(qual,'') LIKE '%auth.uid()%'
        OR coalesce(with_check,'') LIKE '%auth.uid()%'
      )
  LOOP
    v_qual := p.qual;
    v_check := p.with_check;

    IF v_qual IS NOT NULL THEN
      v_qual := replace(v_qual,'( SELECT auth.uid() AS uid)','__AUTH_UID_CACHED__');
      v_qual := replace(v_qual,'auth.uid()','(SELECT auth.uid())');
      v_qual := replace(v_qual,'__AUTH_UID_CACHED__','(SELECT auth.uid())');
      IF v_qual IS DISTINCT FROM p.qual THEN
        EXECUTE format('ALTER POLICY %I ON %I.%I USING (%s)',
          p.policyname,p.schemaname,p.tablename,v_qual);
      END IF;
    END IF;

    IF v_check IS NOT NULL THEN
      v_check := replace(v_check,'( SELECT auth.uid() AS uid)','__AUTH_UID_CACHED__');
      v_check := replace(v_check,'auth.uid()','(SELECT auth.uid())');
      v_check := replace(v_check,'__AUTH_UID_CACHED__','(SELECT auth.uid())');
      IF v_check IS DISTINCT FROM p.with_check THEN
        EXECUTE format('ALTER POLICY %I ON %I.%I WITH CHECK (%s)',
          p.policyname,p.schemaname,p.tablename,v_check);
      END IF;
    END IF;
  END LOOP;
END
$ammar_rls_uid_initplan$;

DROP POLICY IF EXISTS projects_member_select ON public.projects;
