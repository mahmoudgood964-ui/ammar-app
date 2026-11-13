-- Prevent mutation of published RFQs, issued awards and completed delivery records.
-- Complements ownership/RLS checks with immutable commercial snapshots.

BEGIN;

CREATE OR REPLACE FUNCTION public.ammir_guard_rfq_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP='INSERT' THEN
    IF NEW.status <> 'draft' THEN
      RAISE EXCEPTION 'RFQs must be created as drafts before they are published';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status <> 'draft' AND (
    NEW.project_id IS DISTINCT FROM OLD.project_id OR
    NEW.boq_version_id IS DISTINCT FROM OLD.boq_version_id OR
    NEW.reference_code IS DISTINCT FROM OLD.reference_code OR
    NEW.title IS DISTINCT FROM OLD.title OR
    NEW.scope_description IS DISTINCT FROM OLD.scope_description OR
    NEW.delivery_location IS DISTINCT FROM OLD.delivery_location OR
    NEW.deadline_at IS DISTINCT FROM OLD.deadline_at OR
    NEW.currency IS DISTINCT FROM OLD.currency OR
    NEW.created_by IS DISTINCT FROM OLD.created_by
  ) THEN
    RAISE EXCEPTION 'Published RFQ scope is immutable; create a new RFQ revision';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status AND NOT (
    (OLD.status='draft' AND NEW.status IN ('open','cancelled')) OR
    (OLD.status='open' AND NEW.status IN ('closing','awarded','cancelled','closed')) OR
    (OLD.status='closing' AND NEW.status IN ('awarded','cancelled','closed')) OR
    (OLD.status='awarded' AND NEW.status='closed')
  ) THEN
    RAISE EXCEPTION 'Invalid RFQ status transition: % -> %', OLD.status, NEW.status;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammir_guard_rfq_state_trigger ON public.ammir_project_rfqs;
CREATE TRIGGER ammir_guard_rfq_state_trigger
BEFORE INSERT OR UPDATE ON public.ammir_project_rfqs
FOR EACH ROW EXECUTE FUNCTION public.ammir_guard_rfq_state();

CREATE OR REPLACE FUNCTION public.ammir_guard_rfq_item_draft_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_rfq_id uuid;
  v_project_id uuid;
  v_status text;
BEGIN
  IF TG_OP='DELETE' THEN
    v_rfq_id := OLD.rfq_id;
    v_project_id := OLD.project_id;
  ELSE
    v_rfq_id := NEW.rfq_id;
    v_project_id := NEW.project_id;
  END IF;
  SELECT status INTO v_status
  FROM public.ammir_project_rfqs
  WHERE id=v_rfq_id AND project_id=v_project_id;
  IF v_status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'RFQ line items are immutable after the RFQ is published';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammir_guard_rfq_item_draft_state_trigger
  ON public.ammir_project_rfq_items;
CREATE TRIGGER ammir_guard_rfq_item_draft_state_trigger
BEFORE INSERT OR UPDATE OR DELETE ON public.ammir_project_rfq_items
FOR EACH ROW EXECUTE FUNCTION public.ammir_guard_rfq_item_draft_state();

CREATE OR REPLACE FUNCTION public.ammir_guard_award_item_draft_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_award_id uuid;
  v_project_id uuid;
  v_status text;
BEGIN
  IF TG_OP='DELETE' THEN
    v_award_id := OLD.award_id;
    v_project_id := OLD.project_id;
  ELSE
    v_award_id := NEW.award_id;
    v_project_id := NEW.project_id;
  END IF;
  SELECT status INTO v_status
  FROM public.ammir_project_awards
  WHERE id=v_award_id AND project_id=v_project_id;
  IF v_status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'Award line items are immutable after an award is issued';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammir_guard_award_item_draft_state_trigger
  ON public.ammir_project_award_items;
CREATE TRIGGER ammir_guard_award_item_draft_state_trigger
BEFORE INSERT OR UPDATE OR DELETE ON public.ammir_project_award_items
FOR EACH ROW EXECUTE FUNCTION public.ammir_guard_award_item_draft_state();

CREATE OR REPLACE FUNCTION public.ammir_guard_award_header_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP='INSERT' THEN
    IF NEW.status <> 'draft' THEN
      RAISE EXCEPTION 'Awards must be created as drafts before issuance';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP='DELETE' THEN
    IF OLD.status <> 'draft' THEN
      RAISE EXCEPTION 'An issued award cannot be deleted; cancel it and preserve the audit record';
    END IF;
    RETURN OLD;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status AND NOT (
    (OLD.status='draft' AND NEW.status IN ('issued','cancelled')) OR
    (OLD.status='issued' AND NEW.status IN ('accepted','rejected','cancelled')) OR
    (OLD.status='accepted' AND NEW.status IN ('completed','cancelled'))
  ) THEN
    RAISE EXCEPTION 'Invalid award status transition: % -> %', OLD.status, NEW.status;
  END IF;

  IF OLD.status <> 'draft' AND (
    NEW.rfq_id IS DISTINCT FROM OLD.rfq_id OR
    NEW.project_id IS DISTINCT FROM OLD.project_id OR
    NEW.supplier_user_id IS DISTINCT FROM OLD.supplier_user_id OR
    NEW.award_reference IS DISTINCT FROM OLD.award_reference OR
    NEW.terms IS DISTINCT FROM OLD.terms OR
    NEW.created_by IS DISTINCT FROM OLD.created_by
  ) THEN
    RAISE EXCEPTION 'Issued award terms and supplier are immutable';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammir_guard_award_header_state_trigger
  ON public.ammir_project_awards;
CREATE TRIGGER ammir_guard_award_header_state_trigger
BEFORE INSERT OR UPDATE OR DELETE ON public.ammir_project_awards
FOR EACH ROW EXECUTE FUNCTION public.ammir_guard_award_header_state();

CREATE OR REPLACE FUNCTION public.ammir_validate_delivery_supplier()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_award_supplier uuid;
  v_award_status text;
BEGIN
  IF TG_OP='INSERT' AND NEW.status <> 'planned' THEN
    RAISE EXCEPTION 'Deliveries must be created in planned state';
  END IF;

  SELECT supplier_user_id,status INTO v_award_supplier,v_award_status
  FROM public.ammir_project_awards
  WHERE id=NEW.award_id AND project_id=NEW.project_id;

  IF v_award_supplier IS NULL OR v_award_supplier IS DISTINCT FROM NEW.supplier_user_id THEN
    RAISE EXCEPTION 'Delivery supplier must match the awarded provider for this project';
  END IF;
  IF v_award_status NOT IN ('issued','accepted','completed') THEN
    RAISE EXCEPTION 'Delivery can only be created for an issued or accepted award';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammir_validate_delivery_supplier_trigger
  ON public.ammir_project_deliveries;
CREATE TRIGGER ammir_validate_delivery_supplier_trigger
BEFORE INSERT OR UPDATE OF award_id,project_id,supplier_user_id ON public.ammir_project_deliveries
FOR EACH ROW EXECUTE FUNCTION public.ammir_validate_delivery_supplier();

CREATE OR REPLACE FUNCTION public.ammir_guard_delivery_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.status NOT IN ('planned','cancelled')
     OR EXISTS (SELECT 1 FROM public.ammir_project_delivery_evidence e WHERE e.delivery_id=OLD.id)
     OR EXISTS (
       SELECT 1 FROM public.ammir_project_delivery_items i
       WHERE i.delivery_id=OLD.id AND
         (i.received_quantity>0 OR i.damaged_quantity>0 OR i.missing_quantity>0)
     ) THEN
    RAISE EXCEPTION 'A dispatched or evidenced delivery cannot be deleted; preserve the delivery audit trail';
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS ammir_guard_delivery_delete_trigger
  ON public.ammir_project_deliveries;
CREATE TRIGGER ammir_guard_delivery_delete_trigger
BEFORE DELETE ON public.ammir_project_deliveries
FOR EACH ROW EXECUTE FUNCTION public.ammir_guard_delivery_delete();


CREATE OR REPLACE FUNCTION public.ammir_guard_boq_version_insert()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status <> 'draft' THEN
    RAISE EXCEPTION 'BOQ versions must be created as drafts before publication';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammir_guard_boq_version_insert_trigger
  ON public.ammir_project_boq_versions;
CREATE TRIGGER ammir_guard_boq_version_insert_trigger
BEFORE INSERT ON public.ammir_project_boq_versions
FOR EACH ROW EXECUTE FUNCTION public.ammir_guard_boq_version_insert();

-- Authenticated project roles may create only draft records. Publication and
-- issuance must occur through the reviewed state transitions above.
DROP POLICY IF EXISTS ammir_boq_versions_insert ON public.ammir_project_boq_versions;
CREATE POLICY ammir_boq_versions_insert ON public.ammir_project_boq_versions
FOR INSERT TO authenticated
WITH CHECK (
  status='draft'
  AND public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
);

DROP POLICY IF EXISTS ammir_rfqs_insert ON public.ammir_project_rfqs;
CREATE POLICY ammir_rfqs_insert ON public.ammir_project_rfqs
FOR INSERT TO authenticated
WITH CHECK (
  status='draft'
  AND public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
);

DROP POLICY IF EXISTS ammir_rfq_invites_insert ON public.ammir_project_rfq_invites;
CREATE POLICY ammir_rfq_invites_insert ON public.ammir_project_rfq_invites
FOR INSERT TO authenticated
WITH CHECK (
  status='invited'
  AND public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
  AND (
    EXISTS (SELECT 1 FROM public.ammar_market_suppliers s
      WHERE s.owner_id=provider_user_id AND s.status='active' AND s.is_verified=true)
    OR EXISTS (SELECT 1 FROM public.ammar_service_providers sp
      WHERE sp.owner_id=provider_user_id AND sp.status='active' AND sp.is_verified=true)
  )
);

DROP POLICY IF EXISTS ammir_awards_insert ON public.ammir_project_awards;
CREATE POLICY ammir_awards_insert ON public.ammir_project_awards
FOR INSERT TO authenticated
WITH CHECK (
  status='draft'
  AND public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
  AND (
    EXISTS (SELECT 1 FROM public.ammar_market_suppliers s
      WHERE s.owner_id=supplier_user_id AND s.status='active' AND s.is_verified=true)
    OR EXISTS (SELECT 1 FROM public.ammar_service_providers sp
      WHERE sp.owner_id=supplier_user_id AND sp.status='active' AND sp.is_verified=true)
  )
);

DROP POLICY IF EXISTS ammir_deliveries_insert ON public.ammir_project_deliveries;
CREATE POLICY ammir_deliveries_insert ON public.ammir_project_deliveries
FOR INSERT TO authenticated
WITH CHECK (
  status='planned'
  AND public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
);

REVOKE ALL ON FUNCTION public.ammir_guard_boq_version_insert() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ammir_guard_rfq_state() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ammir_guard_rfq_item_draft_state() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ammir_guard_award_item_draft_state() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ammir_guard_award_header_state() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ammir_validate_delivery_supplier() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ammir_guard_delivery_delete() FROM PUBLIC, anon, authenticated;

COMMIT;
