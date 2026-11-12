-- AMMAR global operations release: field reports, issue control, change governance and handover.
-- Safe additive migration. Existing projects and records are preserved.
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

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_site_reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    report_date date NOT NULL DEFAULT CURRENT_DATE,
    weather text,
    crew_count integer NOT NULL DEFAULT 0 CHECK (crew_count BETWEEN 0 AND 10000),
    progress_percent integer CHECK (progress_percent BETWEEN 0 AND 100),
    completed_work text NOT NULL CHECK (char_length(completed_work) BETWEEN 1 AND 5000),
    blockers text,
    safety_notes text,
    created_by uuid NOT NULL DEFAULT auth.uid(),
    created_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_issues (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 240),
    description text,
    location text,
    severity text NOT NULL DEFAULT ''medium'' CHECK (severity IN (''low'',''medium'',''high'',''critical'')),
    status text NOT NULL DEFAULT ''open'' CHECK (status IN (''open'',''in_progress'',''resolved'',''verified'')),
    assigned_to uuid,
    due_date date,
    created_by uuid NOT NULL DEFAULT auth.uid(),
    resolved_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_change_orders (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 240),
    reason text NOT NULL CHECK (char_length(reason) BETWEEN 1 AND 5000),
    cost_impact numeric(14,2) NOT NULL DEFAULT 0 CHECK (cost_impact >= 0),
    currency text,
    days_impact integer NOT NULL DEFAULT 0 CHECK (days_impact BETWEEN 0 AND 3650),
    status text NOT NULL DEFAULT ''submitted'' CHECK (status IN (''submitted'',''under_review'',''approved'',''rejected'')),
    decision_note text,
    requested_by uuid NOT NULL DEFAULT auth.uid(),
    decided_by uuid,
    decided_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);

  EXECUTE format('CREATE TABLE IF NOT EXISTS public.project_handover_items (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id %s NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    category text NOT NULL DEFAULT ''general'',
    title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 240),
    status text NOT NULL DEFAULT ''pending'' CHECK (status IN (''pending'',''passed'',''failed'')),
    notes text,
    checked_by uuid,
    checked_at timestamptz,
    created_by uuid NOT NULL DEFAULT auth.uid(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
  )', project_id_type);
END $$;

-- Enrich existing supplier quotations; old rows remain valid.
ALTER TABLE public.project_quotes
  ADD COLUMN IF NOT EXISTS contact_email text,
  ADD COLUMN IF NOT EXISTS contact_phone text,
  ADD COLUMN IF NOT EXISTS duration_days integer,
  ADD COLUMN IF NOT EXISTS warranty_months integer,
  ADD COLUMN IF NOT EXISTS valid_until date,
  ADD COLUMN IF NOT EXISTS inclusions text,
  ADD COLUMN IF NOT EXISTS exclusions text;

-- Protect future quotation records while retaining any historical values.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.project_quotes'::regclass
      AND conname='project_quotes_duration_days_ammar_check'
  ) THEN
    ALTER TABLE public.project_quotes
      ADD CONSTRAINT project_quotes_duration_days_ammar_check
      CHECK (duration_days IS NULL OR duration_days BETWEEN 1 AND 3650) NOT VALID;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.project_quotes'::regclass
      AND conname='project_quotes_warranty_months_ammar_check'
  ) THEN
    ALTER TABLE public.project_quotes
      ADD CONSTRAINT project_quotes_warranty_months_ammar_check
      CHECK (warranty_months IS NULL OR warranty_months BETWEEN 0 AND 600) NOT VALID;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS project_site_reports_project_date_idx
  ON public.project_site_reports(project_id, report_date DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS project_issues_project_status_idx
  ON public.project_issues(project_id, status, severity);
CREATE INDEX IF NOT EXISTS project_change_orders_project_status_idx
  ON public.project_change_orders(project_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS project_handover_items_project_status_idx
  ON public.project_handover_items(project_id, status, created_at);

ALTER TABLE public.project_site_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_issues ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_change_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_handover_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS project_site_reports_member_select ON public.project_site_reports;
DROP POLICY IF EXISTS project_site_reports_member_insert ON public.project_site_reports;
DROP POLICY IF EXISTS project_site_reports_author_update ON public.project_site_reports;
DROP POLICY IF EXISTS project_site_reports_manager_delete ON public.project_site_reports;
CREATE POLICY project_site_reports_member_select ON public.project_site_reports
FOR SELECT TO authenticated USING (public.ammar_project_role(project_id::text) IS NOT NULL);
CREATE POLICY project_site_reports_member_insert ON public.project_site_reports
FOR INSERT TO authenticated WITH CHECK (
  created_by = auth.uid()
  AND public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer','worker')
);
CREATE POLICY project_site_reports_author_update ON public.project_site_reports
FOR UPDATE TO authenticated USING (
  public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer','worker')
  AND (created_by = auth.uid() OR public.ammar_project_role(project_id::text) IN ('owner','manager'))
) WITH CHECK (
  public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer','worker')
  AND (created_by = auth.uid() OR public.ammar_project_role(project_id::text) IN ('owner','manager'))
);
CREATE POLICY project_site_reports_manager_delete ON public.project_site_reports
FOR DELETE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager'));

DROP POLICY IF EXISTS project_issues_member_select ON public.project_issues;
DROP POLICY IF EXISTS project_issues_member_insert ON public.project_issues;
DROP POLICY IF EXISTS project_issues_manager_update ON public.project_issues;
DROP POLICY IF EXISTS project_issues_manager_delete ON public.project_issues;
CREATE POLICY project_issues_member_select ON public.project_issues
FOR SELECT TO authenticated USING (public.ammar_project_role(project_id::text) IS NOT NULL);
CREATE POLICY project_issues_member_insert ON public.project_issues
FOR INSERT TO authenticated WITH CHECK (
  created_by = auth.uid()
  AND public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer','worker')
);
CREATE POLICY project_issues_manager_update ON public.project_issues
FOR UPDATE TO authenticated USING (
  public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
) WITH CHECK (
  public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
);
CREATE POLICY project_issues_manager_delete ON public.project_issues
FOR DELETE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager'));

DROP POLICY IF EXISTS project_change_orders_member_select ON public.project_change_orders;
DROP POLICY IF EXISTS project_change_orders_member_insert ON public.project_change_orders;
DROP POLICY IF EXISTS project_change_orders_owner_decide ON public.project_change_orders;
DROP POLICY IF EXISTS project_change_orders_owner_delete ON public.project_change_orders;
CREATE POLICY project_change_orders_member_select ON public.project_change_orders
FOR SELECT TO authenticated USING (public.ammar_project_role(project_id::text) IS NOT NULL);
CREATE POLICY project_change_orders_member_insert ON public.project_change_orders
FOR INSERT TO authenticated WITH CHECK (
  requested_by = auth.uid()
  AND public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
);
CREATE POLICY project_change_orders_owner_decide ON public.project_change_orders
FOR UPDATE TO authenticated USING (
  public.ammar_project_role(project_id::text) IN ('owner','manager')
) WITH CHECK (
  public.ammar_project_role(project_id::text) IN ('owner','manager')
);
CREATE POLICY project_change_orders_owner_delete ON public.project_change_orders
FOR DELETE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager'));

DROP POLICY IF EXISTS project_handover_member_select ON public.project_handover_items;
DROP POLICY IF EXISTS project_handover_member_insert ON public.project_handover_items;
DROP POLICY IF EXISTS project_handover_member_update ON public.project_handover_items;
DROP POLICY IF EXISTS project_handover_manager_delete ON public.project_handover_items;
CREATE POLICY project_handover_member_select ON public.project_handover_items
FOR SELECT TO authenticated USING (public.ammar_project_role(project_id::text) IS NOT NULL);
CREATE POLICY project_handover_member_insert ON public.project_handover_items
FOR INSERT TO authenticated WITH CHECK (
  created_by = auth.uid()
  AND public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
);
CREATE POLICY project_handover_member_update ON public.project_handover_items
FOR UPDATE TO authenticated USING (
  public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
) WITH CHECK (
  public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
);
CREATE POLICY project_handover_manager_delete ON public.project_handover_items
FOR DELETE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager'));

DROP TRIGGER IF EXISTS ammar_project_issues_touch_updated_at ON public.project_issues;
CREATE TRIGGER ammar_project_issues_touch_updated_at
BEFORE UPDATE ON public.project_issues
FOR EACH ROW EXECUTE FUNCTION public.ammar_touch_updated_at();
DROP TRIGGER IF EXISTS ammar_project_change_orders_touch_updated_at ON public.project_change_orders;
CREATE TRIGGER ammar_project_change_orders_touch_updated_at
BEFORE UPDATE ON public.project_change_orders
FOR EACH ROW EXECUTE FUNCTION public.ammar_touch_updated_at();
DROP TRIGGER IF EXISTS ammar_project_handover_items_touch_updated_at ON public.project_handover_items;
CREATE TRIGGER ammar_project_handover_items_touch_updated_at
BEFORE UPDATE ON public.project_handover_items
FOR EACH ROW EXECUTE FUNCTION public.ammar_touch_updated_at();

GRANT SELECT, INSERT, UPDATE, DELETE ON
  public.project_site_reports,
  public.project_issues,
  public.project_change_orders,
  public.project_handover_items
TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.project_quotes TO authenticated;

-- Keep public/anonymous callers out of the new project data.
REVOKE ALL ON public.project_site_reports, public.project_issues,
  public.project_change_orders, public.project_handover_items FROM anon;
