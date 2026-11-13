-- AMMIR construction workflow: BOQ, multi-provider RFQ, quote privacy,
-- split awards, delivery reconciliation and private delivery evidence.
-- Additive only. Does not touch legacy bank milestone tables or their policies.

BEGIN;

CREATE TABLE IF NOT EXISTS public.ammir_project_boq_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  version_no integer NOT NULL CHECK (version_no > 0),
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 2 AND 180),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','archived')),
  revision_notes text,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  published_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(project_id, version_no),
  UNIQUE(id, project_id)
);

CREATE TABLE IF NOT EXISTS public.ammir_project_boq_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  boq_version_id uuid NOT NULL,
  parent_item_id uuid REFERENCES public.ammir_project_boq_items(id) ON DELETE SET NULL,
  item_code text,
  category text,
  description text NOT NULL CHECK (char_length(btrim(description)) BETWEEN 2 AND 1000),
  specification text,
  unit text NOT NULL CHECK (char_length(btrim(unit)) BETWEEN 1 AND 40),
  quantity numeric(18,3) NOT NULL CHECK (quantity > 0),
  unit_rate numeric(18,2) CHECK (unit_rate IS NULL OR unit_rate >= 0),
  currency text,
  estimated_total numeric(20,2) GENERATED ALWAYS AS (round(quantity * coalesce(unit_rate, 0), 2)) STORED,
  notes text,
  sort_order integer NOT NULL DEFAULT 0,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(id, project_id),
  CONSTRAINT ammir_boq_item_version_project_fk
    FOREIGN KEY (boq_version_id, project_id)
    REFERENCES public.ammir_project_boq_versions(id, project_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS public.ammir_project_rfqs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  boq_version_id uuid,
  reference_code text NOT NULL,
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 3 AND 180),
  scope_description text,
  delivery_location text,
  deadline_at timestamptz,
  currency text NOT NULL DEFAULT 'SDG',
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','open','closing','awarded','cancelled','closed')),
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(project_id, reference_code),
  UNIQUE(id, project_id),
  CONSTRAINT ammir_rfq_boq_version_project_fk
    FOREIGN KEY (boq_version_id, project_id)
    REFERENCES public.ammir_project_boq_versions(id, project_id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS public.ammir_project_rfq_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rfq_id uuid NOT NULL,
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  boq_item_id uuid,
  item_code text,
  description text NOT NULL CHECK (char_length(btrim(description)) BETWEEN 2 AND 1000),
  specification text,
  unit text NOT NULL CHECK (char_length(btrim(unit)) BETWEEN 1 AND 40),
  quantity numeric(18,3) NOT NULL CHECK (quantity > 0),
  notes text,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ammir_rfq_item_project_fk
    FOREIGN KEY (rfq_id, project_id)
    REFERENCES public.ammir_project_rfqs(id, project_id) ON DELETE CASCADE,
  CONSTRAINT ammir_rfq_item_boq_project_fk
    FOREIGN KEY (boq_item_id, project_id)
    REFERENCES public.ammir_project_boq_items(id, project_id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS public.ammir_project_rfq_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rfq_id uuid NOT NULL,
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  provider_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  provider_profile_id uuid,
  provider_type text NOT NULL DEFAULT 'service_provider'
    CHECK (provider_type IN ('supplier','service_provider','contractor','transport','other')),
  provider_name_snapshot text NOT NULL CHECK (char_length(btrim(provider_name_snapshot)) BETWEEN 2 AND 180),
  status text NOT NULL DEFAULT 'invited' CHECK (status IN ('invited','accepted','declined','withdrawn')),
  invited_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  invited_at timestamptz NOT NULL DEFAULT now(),
  responded_at timestamptz,
  CONSTRAINT ammir_rfq_invite_project_fk
    FOREIGN KEY (rfq_id, project_id)
    REFERENCES public.ammir_project_rfqs(id, project_id) ON DELETE CASCADE,
  UNIQUE(rfq_id, provider_user_id)
);

CREATE TABLE IF NOT EXISTS public.ammir_project_rfq_quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rfq_id uuid NOT NULL,
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  provider_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  currency text NOT NULL DEFAULT 'SDG',
  transport_cost numeric(18,2) NOT NULL DEFAULT 0 CHECK (transport_cost >= 0),
  loading_cost numeric(18,2) NOT NULL DEFAULT 0 CHECK (loading_cost >= 0),
  taxes numeric(18,2) NOT NULL DEFAULT 0 CHECK (taxes >= 0),
  other_costs numeric(18,2) NOT NULL DEFAULT 0 CHECK (other_costs >= 0),
  total_cost numeric(20,2) NOT NULL DEFAULT 0 CHECK (total_cost >= 0),
  delivery_days integer CHECK (delivery_days IS NULL OR delivery_days BETWEEN 0 AND 3650),
  valid_until date,
  warranty_terms text,
  exclusions text,
  notes text,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','submitted','withdrawn')),
  submitted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ammir_rfq_quote_project_fk
    FOREIGN KEY (rfq_id, project_id)
    REFERENCES public.ammir_project_rfqs(id, project_id) ON DELETE CASCADE,
  UNIQUE(rfq_id, provider_user_id),
  UNIQUE(id, project_id)
);

CREATE TABLE IF NOT EXISTS public.ammir_project_rfq_quote_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id uuid NOT NULL,
  rfq_item_id uuid NOT NULL REFERENCES public.ammir_project_rfq_items(id) ON DELETE RESTRICT,
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  quoted_quantity numeric(18,3) NOT NULL CHECK (quoted_quantity > 0),
  unit_rate numeric(18,2) NOT NULL CHECK (unit_rate >= 0),
  line_total numeric(20,2) GENERATED ALWAYS AS (round(quoted_quantity * unit_rate, 2)) STORED,
  availability_status text NOT NULL DEFAULT 'confirmed'
    CHECK (availability_status IN ('confirmed','partial','subject_to_confirmation','unavailable')),
  lead_time_days integer CHECK (lead_time_days IS NULL OR lead_time_days BETWEEN 0 AND 3650),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ammir_quote_item_project_fk
    FOREIGN KEY (quote_id, project_id)
    REFERENCES public.ammir_project_rfq_quotes(id, project_id) ON DELETE CASCADE,
  UNIQUE(quote_id, rfq_item_id)
);

CREATE TABLE IF NOT EXISTS public.ammir_project_awards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rfq_id uuid NOT NULL,
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  supplier_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  award_reference text NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','issued','accepted','rejected','cancelled','completed')),
  terms text,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  issued_at timestamptz,
  accepted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ammir_award_project_fk
    FOREIGN KEY (rfq_id, project_id)
    REFERENCES public.ammir_project_rfqs(id, project_id) ON DELETE RESTRICT,
  UNIQUE(project_id, award_reference),
  UNIQUE(id, project_id)
);

CREATE TABLE IF NOT EXISTS public.ammir_project_award_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  award_id uuid NOT NULL,
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  rfq_item_id uuid NOT NULL REFERENCES public.ammir_project_rfq_items(id) ON DELETE RESTRICT,
  quote_item_id uuid NOT NULL REFERENCES public.ammir_project_rfq_quote_items(id) ON DELETE RESTRICT,
  awarded_quantity numeric(18,3) NOT NULL CHECK (awarded_quantity > 0),
  unit_rate numeric(18,2) NOT NULL CHECK (unit_rate >= 0),
  currency text NOT NULL DEFAULT 'SDG',
  awarded_total numeric(20,2) GENERATED ALWAYS AS (round(awarded_quantity * unit_rate, 2)) STORED,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ammir_award_item_project_fk
    FOREIGN KEY (award_id, project_id)
    REFERENCES public.ammir_project_awards(id, project_id) ON DELETE CASCADE,
  UNIQUE(award_id, rfq_item_id)
);

CREATE TABLE IF NOT EXISTS public.ammir_project_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  award_id uuid NOT NULL,
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  supplier_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  delivery_reference text NOT NULL,
  status text NOT NULL DEFAULT 'planned'
    CHECK (status IN ('planned','dispatched','partially_received','received','exception','cancelled')),
  scheduled_at date,
  dispatched_at timestamptz,
  received_at timestamptz,
  received_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  vehicle_or_carrier text,
  notes text,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ammir_delivery_project_fk
    FOREIGN KEY (award_id, project_id)
    REFERENCES public.ammir_project_awards(id, project_id) ON DELETE CASCADE,
  UNIQUE(project_id, delivery_reference),
  UNIQUE(id, project_id)
);

CREATE TABLE IF NOT EXISTS public.ammir_project_delivery_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid NOT NULL,
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  award_item_id uuid NOT NULL REFERENCES public.ammir_project_award_items(id) ON DELETE RESTRICT,
  expected_quantity numeric(18,3) NOT NULL CHECK (expected_quantity > 0),
  received_quantity numeric(18,3) NOT NULL DEFAULT 0 CHECK (received_quantity >= 0),
  damaged_quantity numeric(18,3) NOT NULL DEFAULT 0 CHECK (damaged_quantity >= 0),
  missing_quantity numeric(18,3) NOT NULL DEFAULT 0 CHECK (missing_quantity >= 0),
  condition_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ammir_delivery_item_project_fk
    FOREIGN KEY (delivery_id, project_id)
    REFERENCES public.ammir_project_deliveries(id, project_id) ON DELETE CASCADE,
  CHECK (received_quantity + damaged_quantity + missing_quantity <= expected_quantity + 0.0005)
);

CREATE TABLE IF NOT EXISTS public.ammir_project_delivery_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid NOT NULL,
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  object_path text NOT NULL,
  file_name text NOT NULL,
  mime_type text,
  caption text,
  uploaded_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ammir_delivery_evidence_project_fk
    FOREIGN KEY (delivery_id, project_id)
    REFERENCES public.ammir_project_deliveries(id, project_id) ON DELETE CASCADE
);

CREATE OR REPLACE FUNCTION public.ammir_boq_item_draft_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE v_version_id uuid;
DECLARE v_status text;
BEGIN
  v_version_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.boq_version_id ELSE NEW.boq_version_id END;
  SELECT status INTO v_status FROM public.ammir_project_boq_versions WHERE id = v_version_id;
  IF v_status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'BOQ versions can only be edited while in draft status';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammir_boq_item_draft_guard_trigger ON public.ammir_project_boq_items;
CREATE TRIGGER ammir_boq_item_draft_guard_trigger
BEFORE INSERT OR UPDATE OR DELETE ON public.ammir_project_boq_items
FOR EACH ROW EXECUTE FUNCTION public.ammir_boq_item_draft_guard();

CREATE OR REPLACE FUNCTION public.ammir_validate_quote_item()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $
DECLARE v_requested numeric(18,3);
DECLARE v_rfq uuid;
BEGIN
  SELECT i.quantity, i.rfq_id INTO v_requested, v_rfq
  FROM public.ammir_project_rfq_items i
  WHERE i.id = NEW.rfq_item_id AND i.project_id = NEW.project_id;
  IF v_requested IS NULL THEN RAISE EXCEPTION 'Quote item must reference an RFQ item in the same project'; END IF;
  IF NEW.quoted_quantity > v_requested + 0.0005 THEN
    RAISE EXCEPTION 'Quoted quantity cannot exceed the requested quantity';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.ammir_project_rfq_quotes q
    WHERE q.id = NEW.quote_id AND q.project_id = NEW.project_id
      AND q.rfq_id = v_rfq AND q.status = 'draft'
  ) THEN
    RAISE EXCEPTION 'Quote items can only be added to a draft quote for the same RFQ';
  END IF;
  RETURN NEW;
END;
$;

DROP TRIGGER IF EXISTS ammir_validate_quote_item_trigger ON public.ammir_project_rfq_quote_items;
CREATE TRIGGER ammir_validate_quote_item_trigger
BEFORE INSERT OR UPDATE ON public.ammir_project_rfq_quote_items
FOR EACH ROW EXECUTE FUNCTION public.ammir_validate_quote_item();

CREATE OR REPLACE FUNCTION public.ammir_validate_award_item()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE v_requested numeric(18,3);
DECLARE v_quote_provider uuid;
DECLARE v_quote_rfq uuid;
DECLARE v_award_supplier uuid;
DECLARE v_quote_status text;
DECLARE v_existing numeric(18,3);
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.rfq_item_id::text, 0));

  SELECT i.quantity INTO v_requested
  FROM public.ammir_project_rfq_items i
  WHERE i.id = NEW.rfq_item_id AND i.project_id = NEW.project_id;
  IF v_requested IS NULL THEN RAISE EXCEPTION 'RFQ item does not belong to this project'; END IF;

  SELECT q.provider_user_id, q.rfq_id, q.status
    INTO v_quote_provider, v_quote_rfq, v_quote_status
  FROM public.ammir_project_rfq_quotes q
  JOIN public.ammir_project_rfq_quote_items qi ON qi.quote_id = q.id
  WHERE qi.id = NEW.quote_item_id AND qi.rfq_item_id = NEW.rfq_item_id
    AND qi.project_id = NEW.project_id;
  IF v_quote_provider IS NULL OR v_quote_status <> 'submitted' THEN
    RAISE EXCEPTION 'Award must reference a submitted quote for the same RFQ item';
  END IF;

  SELECT a.supplier_user_id INTO v_award_supplier
  FROM public.ammir_project_awards a
  WHERE a.id = NEW.award_id AND a.project_id = NEW.project_id AND a.rfq_id = v_quote_rfq;
  IF v_award_supplier IS NULL OR v_award_supplier <> v_quote_provider THEN
    RAISE EXCEPTION 'Award supplier must match the quoted provider';
  END IF;

  SELECT coalesce(sum(ai.awarded_quantity),0) INTO v_existing
  FROM public.ammir_project_award_items ai
  WHERE ai.rfq_item_id = NEW.rfq_item_id AND ai.project_id = NEW.project_id
    AND ai.id IS DISTINCT FROM NEW.id;
  IF v_existing + NEW.awarded_quantity > v_requested + 0.0005 THEN
    RAISE EXCEPTION 'Split awards exceed the requested BOQ/RFQ quantity';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammir_validate_award_item_trigger ON public.ammir_project_award_items;
CREATE TRIGGER ammir_validate_award_item_trigger
BEFORE INSERT OR UPDATE ON public.ammir_project_award_items
FOR EACH ROW EXECUTE FUNCTION public.ammir_validate_award_item();

CREATE OR REPLACE FUNCTION public.ammir_validate_delivery_item()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE v_awarded numeric(18,3);
DECLARE v_existing numeric(18,3);
DECLARE v_award_project uuid;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.award_item_id::text, 0));

  SELECT ai.awarded_quantity, ai.project_id
    INTO v_awarded, v_award_project
  FROM public.ammir_project_award_items ai
  WHERE ai.id = NEW.award_item_id;
  IF v_awarded IS NULL OR v_award_project <> NEW.project_id THEN
    RAISE EXCEPTION 'Delivery item must reference an award item in this project';
  END IF;

  SELECT coalesce(sum(di.expected_quantity),0) INTO v_existing
  FROM public.ammir_project_delivery_items di
  WHERE di.award_item_id = NEW.award_item_id AND di.project_id = NEW.project_id
    AND di.id IS DISTINCT FROM NEW.id;
  IF v_existing + NEW.expected_quantity > v_awarded + 0.0005 THEN
    RAISE EXCEPTION 'Cumulative dispatched quantity exceeds the awarded quantity';
  END IF;

  IF NEW.received_quantity + NEW.damaged_quantity + NEW.missing_quantity > NEW.expected_quantity + 0.0005 THEN
    RAISE EXCEPTION 'Received, damaged and missing quantities cannot exceed dispatched quantity';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammir_validate_delivery_item_trigger ON public.ammir_project_delivery_items;
CREATE TRIGGER ammir_validate_delivery_item_trigger
BEFORE INSERT OR UPDATE ON public.ammir_project_delivery_items
FOR EACH ROW EXECUTE FUNCTION public.ammir_validate_delivery_item();

CREATE INDEX IF NOT EXISTS ammir_boq_versions_project_idx
  ON public.ammir_project_boq_versions(project_id, version_no DESC);
CREATE INDEX IF NOT EXISTS ammir_boq_items_version_idx
  ON public.ammir_project_boq_items(project_id, boq_version_id, sort_order);
CREATE INDEX IF NOT EXISTS ammir_rfqs_project_idx
  ON public.ammir_project_rfqs(project_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ammir_rfq_items_lookup_idx
  ON public.ammir_project_rfq_items(rfq_id, sort_order);
CREATE INDEX IF NOT EXISTS ammir_rfq_invites_user_idx
  ON public.ammir_project_rfq_invites(provider_user_id, status);
CREATE INDEX IF NOT EXISTS ammir_rfq_quotes_provider_idx
  ON public.ammir_project_rfq_quotes(provider_user_id, rfq_id, status);
CREATE INDEX IF NOT EXISTS ammir_rfq_quote_items_quote_idx
  ON public.ammir_project_rfq_quote_items(quote_id);
CREATE INDEX IF NOT EXISTS ammir_awards_project_idx
  ON public.ammir_project_awards(project_id, rfq_id, status);
CREATE INDEX IF NOT EXISTS ammir_award_items_rfq_item_idx
  ON public.ammir_project_award_items(rfq_item_id);
CREATE INDEX IF NOT EXISTS ammir_deliveries_project_idx
  ON public.ammir_project_deliveries(project_id, award_id, status);
CREATE INDEX IF NOT EXISTS ammir_delivery_items_award_idx
  ON public.ammir_project_delivery_items(award_item_id);
CREATE INDEX IF NOT EXISTS ammir_delivery_evidence_delivery_idx
  ON public.ammir_project_delivery_evidence(delivery_id);

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'ammir_project_boq_versions','ammir_project_boq_items',
    'ammir_project_rfqs','ammir_project_rfq_items','ammir_project_rfq_invites',
    'ammir_project_rfq_quotes','ammir_project_rfq_quote_items',
    'ammir_project_awards','ammir_project_award_items',
    'ammir_project_deliveries','ammir_project_delivery_items',
    'ammir_project_delivery_evidence'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

-- Project team access to core BOQ, RFQ, award and delivery records
CREATE POLICY ammir_boq_versions_select ON public.ammir_project_boq_versions
FOR SELECT TO authenticated USING (public.ammar_project_role(project_id::text) IS NOT NULL);
CREATE POLICY ammir_boq_versions_write ON public.ammir_project_boq_versions
FOR ALL TO authenticated
USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));

CREATE POLICY ammir_boq_items_select ON public.ammir_project_boq_items
FOR SELECT TO authenticated USING (public.ammar_project_role(project_id::text) IS NOT NULL);
CREATE POLICY ammir_boq_items_write ON public.ammir_project_boq_items
FOR ALL TO authenticated
USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));

CREATE POLICY ammir_rfqs_select ON public.ammir_project_rfqs
FOR SELECT TO authenticated USING (
  public.ammar_project_role(project_id::text) IS NOT NULL
  OR EXISTS (
    SELECT 1 FROM public.ammir_project_rfq_invites i
    WHERE i.rfq_id = public.ammir_project_rfqs.id AND i.provider_user_id = (SELECT auth.uid()) AND i.status IN ('invited','accepted')
  )
);
CREATE POLICY ammir_rfqs_write ON public.ammir_project_rfqs
FOR ALL TO authenticated
USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));

CREATE POLICY ammir_rfq_items_select ON public.ammir_project_rfq_items
FOR SELECT TO authenticated USING (
  public.ammar_project_role(project_id::text) IS NOT NULL
  OR EXISTS (
    SELECT 1 FROM public.ammir_project_rfq_invites i
    WHERE i.rfq_id = public.ammir_project_rfq_items.rfq_id AND i.provider_user_id = (SELECT auth.uid()) AND i.status IN ('invited','accepted')
  )
);
CREATE POLICY ammir_rfq_items_write ON public.ammir_project_rfq_items
FOR ALL TO authenticated
USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));

CREATE POLICY ammir_rfq_invites_select ON public.ammir_project_rfq_invites
FOR SELECT TO authenticated USING (
  provider_user_id = (SELECT auth.uid())
  OR public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
);
CREATE POLICY ammir_rfq_invites_write ON public.ammir_project_rfq_invites
FOR ALL TO authenticated
USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_rfq_invites_provider_response ON public.ammir_project_rfq_invites
FOR UPDATE TO authenticated
USING (provider_user_id = (SELECT auth.uid()) AND status = 'invited')
WITH CHECK (provider_user_id = (SELECT auth.uid()) AND status IN ('accepted','declined'));

-- Suppliers can only read their own quotes. Project team can compare all quotes.
CREATE POLICY ammir_rfq_quotes_select ON public.ammir_project_rfq_quotes
FOR SELECT TO authenticated USING (
  provider_user_id = (SELECT auth.uid())
  OR public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer','accountant')
);
CREATE POLICY ammir_rfq_quotes_insert ON public.ammir_project_rfq_quotes
FOR INSERT TO authenticated WITH CHECK (
  provider_user_id = (SELECT auth.uid())
  AND status = 'draft'
  AND EXISTS (
    SELECT 1 FROM public.ammir_project_rfq_invites i
    JOIN public.ammir_project_rfqs r ON r.id = i.rfq_id
    WHERE i.rfq_id = ammir_project_rfq_quotes.rfq_id
      AND i.provider_user_id = (SELECT auth.uid())
      AND i.status IN ('invited','accepted')
      AND r.status = 'open'
  )
);
CREATE POLICY ammir_rfq_quotes_update_provider ON public.ammir_project_rfq_quotes
FOR UPDATE TO authenticated
USING (provider_user_id = (SELECT auth.uid()) AND status = 'draft')
WITH CHECK (provider_user_id = (SELECT auth.uid()) AND status IN ('draft','submitted'));

CREATE POLICY ammir_rfq_quote_items_select ON public.ammir_project_rfq_quote_items
FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM public.ammir_project_rfq_quotes q
    WHERE q.id = quote_id AND (
      q.provider_user_id = (SELECT auth.uid())
      OR public.ammar_project_role(q.project_id::text) IN ('owner','manager','supervisor','engineer','accountant')
    )
  )
);
CREATE POLICY ammir_rfq_quote_items_insert ON public.ammir_project_rfq_quote_items
FOR INSERT TO authenticated WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.ammir_project_rfq_quotes q
    WHERE q.id = public.ammir_project_rfq_quote_items.quote_id AND q.project_id = public.ammir_project_rfq_quote_items.project_id
      AND q.provider_user_id = (SELECT auth.uid()) AND q.status = 'draft'
  )
);
CREATE POLICY ammir_rfq_quote_items_update ON public.ammir_project_rfq_quote_items
FOR UPDATE TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.ammir_project_rfq_quotes q
    WHERE q.id = quote_id AND q.provider_user_id = (SELECT auth.uid()) AND q.status = 'draft'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.ammir_project_rfq_quotes q
    WHERE q.id = quote_id AND q.provider_user_id = (SELECT auth.uid()) AND q.status = 'draft'
  )
);
CREATE POLICY ammir_rfq_quote_items_delete ON public.ammir_project_rfq_quote_items
FOR DELETE TO authenticated USING (
  EXISTS (
    SELECT 1 FROM public.ammir_project_rfq_quotes q
    WHERE q.id = quote_id AND q.provider_user_id = (SELECT auth.uid()) AND q.status = 'draft'
  )
);

CREATE POLICY ammir_awards_select ON public.ammir_project_awards
FOR SELECT TO authenticated USING (
  supplier_user_id = (SELECT auth.uid())
  OR public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer','accountant')
);
CREATE POLICY ammir_awards_write ON public.ammir_project_awards
FOR ALL TO authenticated
USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_awards_provider_response ON public.ammir_project_awards
FOR UPDATE TO authenticated
USING (supplier_user_id = (SELECT auth.uid()) AND status = 'issued')
WITH CHECK (supplier_user_id = (SELECT auth.uid()) AND status IN ('accepted','rejected'));

CREATE POLICY ammir_award_items_select ON public.ammir_project_award_items
FOR SELECT TO authenticated USING (
  public.ammar_project_role(project_id::text) IS NOT NULL
  OR EXISTS (
    SELECT 1 FROM public.ammir_project_awards a
    WHERE a.id = award_id AND a.supplier_user_id = (SELECT auth.uid())
  )
);
CREATE POLICY ammir_award_items_write ON public.ammir_project_award_items
FOR ALL TO authenticated
USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));

CREATE POLICY ammir_deliveries_select ON public.ammir_project_deliveries
FOR SELECT TO authenticated USING (
  supplier_user_id = (SELECT auth.uid())
  OR public.ammar_project_role(project_id::text) IS NOT NULL
);
CREATE POLICY ammir_deliveries_write ON public.ammir_project_deliveries
FOR ALL TO authenticated
USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));

CREATE POLICY ammir_delivery_items_select ON public.ammir_project_delivery_items
FOR SELECT TO authenticated USING (
  public.ammar_project_role(project_id::text) IS NOT NULL
  OR EXISTS (
    SELECT 1 FROM public.ammir_project_deliveries d
    WHERE d.id = delivery_id AND d.supplier_user_id = (SELECT auth.uid())
  )
);
CREATE POLICY ammir_delivery_items_write ON public.ammir_project_delivery_items
FOR ALL TO authenticated
USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));

CREATE POLICY ammir_delivery_evidence_select ON public.ammir_project_delivery_evidence
FOR SELECT TO authenticated USING (
  public.ammar_project_role(project_id::text) IS NOT NULL
  OR EXISTS (
    SELECT 1 FROM public.ammir_project_deliveries d
    WHERE d.id = delivery_id AND d.supplier_user_id = (SELECT auth.uid())
  )
);
CREATE POLICY ammir_delivery_evidence_write ON public.ammir_project_delivery_evidence
FOR ALL TO authenticated
USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));

-- Explicit Data API grants: new public-schema tables are not auto-exposed on Supabase projects.
GRANT SELECT, INSERT, UPDATE, DELETE ON
  public.ammir_project_boq_versions, public.ammir_project_boq_items,
  public.ammir_project_rfqs, public.ammir_project_rfq_items, public.ammir_project_rfq_invites,
  public.ammir_project_rfq_quotes, public.ammir_project_rfq_quote_items,
  public.ammir_project_awards, public.ammir_project_award_items,
  public.ammir_project_deliveries, public.ammir_project_delivery_items,
  public.ammir_project_delivery_evidence TO authenticated;

REVOKE ALL ON FUNCTION public.ammir_boq_item_draft_guard() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ammir_boq_item_draft_guard() TO authenticated;
REVOKE ALL ON FUNCTION public.ammir_validate_quote_item() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.ammir_validate_award_item() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.ammir_validate_delivery_item() FROM PUBLIC, anon;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'ammir-delivery-evidence','ammir-delivery-evidence',false,15728640,
  ARRAY['image/jpeg','image/png','image/webp','application/pdf']
)
ON CONFLICT (id) DO UPDATE SET public=false, file_size_limit=15728640,
  allowed_mime_types=EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS ammir_delivery_evidence_storage_select ON storage.objects;
CREATE POLICY ammir_delivery_evidence_storage_select ON storage.objects
FOR SELECT TO authenticated USING (
  bucket_id = 'ammir-delivery-evidence'
  AND public.ammar_project_role((storage.foldername(name))[1]) IS NOT NULL
);
DROP POLICY IF EXISTS ammir_delivery_evidence_storage_insert ON storage.objects;
CREATE POLICY ammir_delivery_evidence_storage_insert ON storage.objects
FOR INSERT TO authenticated WITH CHECK (
  bucket_id = 'ammir-delivery-evidence'
  AND public.ammar_project_role((storage.foldername(name))[1]) IN ('owner','manager','supervisor','engineer')
);
DROP POLICY IF EXISTS ammir_delivery_evidence_storage_delete ON storage.objects;
CREATE POLICY ammir_delivery_evidence_storage_delete ON storage.objects
FOR DELETE TO authenticated USING (
  bucket_id = 'ammir-delivery-evidence'
  AND (
    owner_id = (SELECT auth.uid())::text
    OR public.ammar_project_role((storage.foldername(name))[1]) IN ('owner','manager','supervisor','engineer')
  )
);

COMMIT;
