-- Verify provider eligibility at transaction points and derive submitted quote totals.
BEGIN;

DROP POLICY IF EXISTS ammir_rfq_invites_insert ON public.ammir_project_rfq_invites;
CREATE POLICY ammir_rfq_invites_insert ON public.ammir_project_rfq_invites
FOR INSERT TO authenticated
WITH CHECK (
  public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
  AND (
    EXISTS (
      SELECT 1 FROM public.ammar_market_suppliers s
      WHERE s.owner_id = provider_user_id AND s.status = 'active' AND s.is_verified = true
    )
    OR EXISTS (
      SELECT 1 FROM public.ammar_service_providers sp
      WHERE sp.owner_id = provider_user_id AND sp.status = 'active' AND sp.is_verified = true
    )
  )
);

DROP POLICY IF EXISTS ammir_rfq_quotes_insert ON public.ammir_project_rfq_quotes;
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
  AND (
    EXISTS (SELECT 1 FROM public.ammar_market_suppliers s
      WHERE s.owner_id = (SELECT auth.uid()) AND s.status = 'active' AND s.is_verified = true)
    OR EXISTS (SELECT 1 FROM public.ammar_service_providers sp
      WHERE sp.owner_id = (SELECT auth.uid()) AND sp.status = 'active' AND sp.is_verified = true)
  )
);

DROP POLICY IF EXISTS ammir_awards_insert ON public.ammir_project_awards;
CREATE POLICY ammir_awards_insert ON public.ammir_project_awards
FOR INSERT TO authenticated WITH CHECK (
  public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
  AND (
    EXISTS (SELECT 1 FROM public.ammar_market_suppliers s
      WHERE s.owner_id = supplier_user_id AND s.status = 'active' AND s.is_verified = true)
    OR EXISTS (SELECT 1 FROM public.ammar_service_providers sp
      WHERE sp.owner_id = supplier_user_id AND sp.status = 'active' AND sp.is_verified = true)
  )
);

CREATE OR REPLACE FUNCTION public.ammir_derive_submitted_quote_total()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE v_items_total numeric(20,2);
BEGIN
  IF NEW.status = 'submitted' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'submitted') THEN
    SELECT coalesce(sum(qi.line_total),0)
      INTO v_items_total
    FROM public.ammir_project_rfq_quote_items qi
    WHERE qi.quote_id = NEW.id AND qi.project_id = NEW.project_id;
    IF v_items_total <= 0 THEN
      RAISE EXCEPTION 'A submitted quote must include at least one priced item';
    END IF;
    NEW.total_cost := round(
      v_items_total + NEW.transport_cost + NEW.loading_cost + NEW.taxes + NEW.other_costs, 2
    );
    NEW.submitted_at := coalesce(NEW.submitted_at, now());
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammir_derive_submitted_quote_total_trigger ON public.ammir_project_rfq_quotes;
CREATE TRIGGER ammir_derive_submitted_quote_total_trigger
BEFORE INSERT OR UPDATE ON public.ammir_project_rfq_quotes
FOR EACH ROW EXECUTE FUNCTION public.ammir_derive_submitted_quote_total();

CREATE OR REPLACE FUNCTION public.ammir_validate_award_price()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE v_quote_rate numeric(18,2);
DECLARE v_quote_currency text;
DECLARE v_quote_quantity numeric(18,3);
BEGIN
  SELECT qi.unit_rate, q.currency, qi.quoted_quantity
    INTO v_quote_rate, v_quote_currency, v_quote_quantity
  FROM public.ammir_project_rfq_quote_items qi
  JOIN public.ammir_project_rfq_quotes q ON q.id = qi.quote_id
  WHERE qi.id = NEW.quote_item_id
    AND qi.rfq_item_id = NEW.rfq_item_id
    AND qi.project_id = NEW.project_id
    AND q.status = 'submitted';
  IF v_quote_rate IS NULL THEN
    RAISE EXCEPTION 'Award must reference an item in a submitted provider quote';
  END IF;
  IF NEW.awarded_quantity > v_quote_quantity + 0.0005 THEN
    RAISE EXCEPTION 'Award quantity exceeds the provider quoted quantity';
  END IF;
  IF NEW.unit_rate <> v_quote_rate OR upper(NEW.currency) <> upper(v_quote_currency) THEN
    RAISE EXCEPTION 'Award price and currency must match the submitted quote item';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammir_validate_award_price_trigger ON public.ammir_project_award_items;
CREATE TRIGGER ammir_validate_award_price_trigger
BEFORE INSERT OR UPDATE ON public.ammir_project_award_items
FOR EACH ROW EXECUTE FUNCTION public.ammir_validate_award_price();

REVOKE ALL ON FUNCTION public.ammir_derive_submitted_quote_total() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ammir_validate_award_price() FROM PUBLIC, anon, authenticated;

COMMIT;
