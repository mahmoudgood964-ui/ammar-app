-- Additional integrity and state guards for the AMMIR project execution workflow.
-- No changes to legacy payment milestone tables or their policies.

BEGIN;

-- BOQ parent references must stay within the same project. The older simple FK
-- still clears parent_item_id on delete; the composite FK prevents cross-project links.
ALTER TABLE public.ammir_project_boq_items
  ADD CONSTRAINT ammir_boq_parent_same_project_fk
  FOREIGN KEY (parent_item_id, project_id)
  REFERENCES public.ammir_project_boq_items(id, project_id);

-- A draft quote may only be amended while its RFQ is open and the provider's
-- invitation remains valid. This closes the gap between initial insert and submit.
DROP POLICY IF EXISTS ammir_rfq_quotes_update_provider ON public.ammir_project_rfq_quotes;
CREATE POLICY ammir_rfq_quotes_update_provider ON public.ammir_project_rfq_quotes
FOR UPDATE TO authenticated
USING (
  provider_user_id = (SELECT auth.uid())
  AND status = 'draft'
)
WITH CHECK (
  provider_user_id = (SELECT auth.uid())
  AND status IN ('draft','submitted')
  AND EXISTS (
    SELECT 1
    FROM public.ammir_project_rfq_invites i
    JOIN public.ammir_project_rfqs r ON r.id = i.rfq_id
    WHERE i.rfq_id = ammir_project_rfq_quotes.rfq_id
      AND i.provider_user_id = (SELECT auth.uid())
      AND i.status IN ('invited','accepted')
      AND r.project_id = ammir_project_rfq_quotes.project_id
      AND r.status = 'open'
  )
  AND (
    EXISTS (
      SELECT 1 FROM public.ammar_market_suppliers s
      WHERE s.owner_id = (SELECT auth.uid()) AND s.status = 'active' AND s.is_verified = true
    )
    OR EXISTS (
      SELECT 1 FROM public.ammar_service_providers sp
      WHERE sp.owner_id = (SELECT auth.uid()) AND sp.status = 'active' AND sp.is_verified = true
    )
  )
);

CREATE OR REPLACE FUNCTION public.ammir_guard_delivery_reconciliation_state()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_line_count integer;
  v_expected numeric(20,3);
  v_received numeric(20,3);
  v_damaged numeric(20,3);
  v_missing numeric(20,3);
BEGIN
  IF NEW.status IN ('received','partially_received','exception') THEN
    SELECT count(*),
           coalesce(sum(expected_quantity),0),
           coalesce(sum(received_quantity),0),
           coalesce(sum(damaged_quantity),0),
           coalesce(sum(missing_quantity),0)
      INTO v_line_count,v_expected,v_received,v_damaged,v_missing
    FROM public.ammir_project_delivery_items
    WHERE delivery_id = NEW.id AND project_id = NEW.project_id;

    IF v_line_count = 0 THEN
      RAISE EXCEPTION 'A delivery cannot be reconciled before delivery items are recorded';
    END IF;

    IF NEW.status = 'received' AND
       (abs(v_received - v_expected) > 0.0005 OR v_damaged > 0 OR v_missing > 0) THEN
      RAISE EXCEPTION 'A fully received delivery must account for every unit as received with no damaged or missing quantity';
    END IF;

    IF NEW.status = 'partially_received' AND
       (v_damaged > 0 OR v_missing > 0 OR v_received >= v_expected - 0.0005) THEN
      RAISE EXCEPTION 'Partially received status requires an outstanding balance and no damaged or missing quantity';
    END IF;

    IF NEW.status = 'exception' AND (v_damaged <= 0 AND v_missing <= 0) THEN
      RAISE EXCEPTION 'Exception status requires a damaged or missing quantity';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammir_guard_delivery_reconciliation_state_trigger
  ON public.ammir_project_deliveries;
CREATE TRIGGER ammir_guard_delivery_reconciliation_state_trigger
BEFORE INSERT OR UPDATE OF status ON public.ammir_project_deliveries
FOR EACH ROW EXECUTE FUNCTION public.ammir_guard_delivery_reconciliation_state();

REVOKE ALL ON FUNCTION public.ammir_guard_delivery_reconciliation_state() FROM PUBLIC, anon, authenticated;

CREATE INDEX IF NOT EXISTS ammir_boq_parent_project_lookup_idx
  ON public.ammir_project_boq_items(parent_item_id, project_id);

COMMIT;
