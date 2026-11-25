-- AMMIR accepted returns and proportional commission adjustment proposals.
-- A return is a separate, manager-approved event; accepting a claim alone never reverses commission.
-- Original commission ledger rows and payment/settlement records are never updated.

BEGIN;

CREATE TABLE public.ammir_project_delivery_returns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE RESTRICT,
  delivery_id uuid NOT NULL,
  claim_id uuid NOT NULL REFERENCES public.ammir_project_delivery_claims(id) ON DELETE RESTRICT,
  receipt_item_id uuid NOT NULL REFERENCES public.ammir_project_delivery_receipt_items(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL,
  returned_quantity numeric(18,3) NOT NULL CHECK (returned_quantity > 0),
  unit_rate_snapshot numeric(18,4) NOT NULL CHECK (unit_rate_snapshot >= 0),
  gross_return_value numeric(14,2) NOT NULL CHECK (gross_return_value >= 0),
  currency text NOT NULL,
  return_note text NOT NULL CHECK (char_length(btrim(return_note)) BETWEEN 10 AND 1000),
  accepted_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ammir_delivery_return_delivery_fk
    FOREIGN KEY (delivery_id, project_id)
    REFERENCES public.ammir_project_deliveries(id, project_id) ON DELETE RESTRICT,
  UNIQUE (claim_id, idempotency_key),
  UNIQUE (id, delivery_id, project_id)
);

CREATE INDEX ammir_delivery_returns_receipt_item_idx
  ON public.ammir_project_delivery_returns(receipt_item_id, created_at);
CREATE INDEX ammir_delivery_returns_claim_idx
  ON public.ammir_project_delivery_returns(claim_id, created_at);

CREATE TABLE public.ammar_commission_adjustments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  original_ledger_id uuid NOT NULL REFERENCES public.ammar_commission_ledger(id) ON DELETE RESTRICT,
  return_id uuid NOT NULL REFERENCES public.ammir_project_delivery_returns(id) ON DELETE RESTRICT,
  currency text NOT NULL,
  adjustment_amount numeric(14,2) NOT NULL CHECK (adjustment_amount > 0),
  status text NOT NULL DEFAULT 'pending_review'
    CHECK (status IN ('pending_review')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (return_id, original_ledger_id)
);

CREATE INDEX ammar_commission_adjustments_ledger_idx
  ON public.ammar_commission_adjustments(original_ledger_id, created_at);

ALTER TABLE public.ammir_project_delivery_returns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_commission_adjustments ENABLE ROW LEVEL SECURITY;

CREATE POLICY ammir_delivery_returns_select
ON public.ammir_project_delivery_returns
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.ammir_project_deliveries d
    WHERE d.id = ammir_project_delivery_returns.delivery_id
      AND d.project_id = ammir_project_delivery_returns.project_id
      AND (
        d.supplier_user_id = (SELECT auth.uid())
        OR app_private.ammar_project_role(d.project_id::text) IS NOT NULL
        OR (SELECT public.is_admin())
      )
  )
);

CREATE POLICY ammar_commission_adjustments_select
ON public.ammar_commission_adjustments
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.ammir_project_delivery_returns r
    JOIN public.ammir_project_deliveries d
      ON d.id = r.delivery_id AND d.project_id = r.project_id
    WHERE r.id = ammar_commission_adjustments.return_id
      AND (
        d.supplier_user_id = (SELECT auth.uid())
        OR app_private.ammar_project_role(d.project_id::text) IS NOT NULL
        OR (SELECT public.is_admin())
      )
  )
);

REVOKE ALL ON public.ammir_project_delivery_returns FROM anon, authenticated;
REVOKE ALL ON public.ammar_commission_adjustments FROM anon, authenticated;
GRANT SELECT ON public.ammir_project_delivery_returns TO authenticated;
GRANT SELECT ON public.ammar_commission_adjustments TO authenticated;

CREATE OR REPLACE FUNCTION public.ammir_guard_delivery_return_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'Accepted delivery return history is immutable';
END;
$$;

CREATE OR REPLACE FUNCTION public.ammar_guard_commission_adjustment_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'Commission adjustment proposals are immutable';
END;
$$;

CREATE TRIGGER ammir_delivery_return_immutable_trigger
BEFORE UPDATE OR DELETE ON public.ammir_project_delivery_returns
FOR EACH ROW EXECUTE FUNCTION public.ammir_guard_delivery_return_immutable();

CREATE TRIGGER ammar_commission_adjustment_immutable_trigger
BEFORE UPDATE OR DELETE ON public.ammar_commission_adjustments
FOR EACH ROW EXECUTE FUNCTION public.ammar_guard_commission_adjustment_immutable();

REVOKE ALL ON FUNCTION public.ammir_guard_delivery_return_immutable()
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ammar_guard_commission_adjustment_immutable()
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION app_private.ammir_record_project_delivery_return(
  p_claim_id uuid,
  p_returned_quantity numeric,
  p_idempotency_key uuid,
  p_return_note text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_project_id uuid;
  v_delivery_id uuid;
  v_receipt_item_id uuid;
  v_claim_type text;
  v_claim_status text;
  v_claimed_quantity numeric(18,3);
  v_existing_id uuid;
  v_existing_quantity numeric(18,3);
  v_existing_note text;
  v_received_quantity numeric(18,3);
  v_item_returned numeric(18,3);
  v_claim_returned numeric(18,3);
  v_receipt_id uuid;
  v_unit_rate numeric(18,4);
  v_currency text;
  v_gross_return_value numeric(14,2);
  v_return_id uuid;
  v_ledger_id uuid;
  v_ledger_gross numeric(14,2);
  v_ledger_commission numeric(14,2);
  v_ledger_currency text;
  v_ledger_status text;
  v_total_returned_gross numeric(14,2);
  v_target_adjustment numeric(14,2);
  v_existing_adjustment numeric(14,2);
  v_adjustment_delta numeric(14,2);
  v_role text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_idempotency_key IS NULL THEN
    RAISE EXCEPTION 'Return idempotency key is required';
  END IF;
  IF p_returned_quantity IS NULL OR p_returned_quantity <= 0 THEN
    RAISE EXCEPTION 'Returned quantity must be positive';
  END IF;
  IF char_length(btrim(coalesce(p_return_note,''))) NOT BETWEEN 10 AND 1000 THEN
    RAISE EXCEPTION 'A return note of 10 to 1000 characters is required';
  END IF;

  SELECT c.project_id, c.delivery_id, c.receipt_item_id,
         c.claim_type, c.status, c.claimed_quantity
    INTO v_project_id, v_delivery_id, v_receipt_item_id,
         v_claim_type, v_claim_status, v_claimed_quantity
  FROM public.ammir_project_delivery_claims c
  WHERE c.id = p_claim_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Delivery claim not found';
  END IF;

  v_role := app_private.ammar_project_role(v_project_id::text);
  IF coalesce(v_role = ANY(ARRAY['owner','manager','supervisor','engineer']::text[]), false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Project manager permission required to accept a return';
  END IF;
  IF v_claim_status <> 'accepted' THEN
    RAISE EXCEPTION 'Only an accepted delivery claim can be converted into an accepted return';
  END IF;
  IF v_claim_type NOT IN ('quality','wrong_item') OR v_receipt_item_id IS NULL THEN
    RAISE EXCEPTION 'Only accepted quality or wrong-item claims against received goods can create a commission return';
  END IF;

  SELECT r.id, r.returned_quantity, r.return_note
    INTO v_existing_id, v_existing_quantity, v_existing_note
  FROM public.ammir_project_delivery_returns r
  WHERE r.claim_id = p_claim_id AND r.idempotency_key = p_idempotency_key;
  IF FOUND THEN
    IF v_existing_quantity = p_returned_quantity
       AND v_existing_note = btrim(p_return_note) THEN
      RETURN v_existing_id;
    END IF;
    RAISE EXCEPTION 'Return idempotency key was already used with a different payload';
  END IF;

  SELECT ri.received_quantity, ri.receipt_id, ai.unit_rate,
         nullif(btrim(ai.currency),'')
    INTO v_received_quantity, v_receipt_id, v_unit_rate, v_currency
  FROM public.ammir_project_delivery_receipt_items ri
  JOIN public.ammir_project_delivery_items di
    ON di.id = ri.delivery_item_id
   AND di.delivery_id = ri.delivery_id
   AND di.project_id = ri.project_id
  JOIN public.ammir_project_award_items ai
    ON ai.id = di.award_item_id
   AND ai.project_id = di.project_id
  WHERE ri.id = v_receipt_item_id
    AND ri.delivery_id = v_delivery_id
    AND ri.project_id = v_project_id
  FOR UPDATE OF ri;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Claim receipt line does not belong to the claimed delivery and project';
  END IF;
  IF v_currency IS NULL THEN
    RAISE EXCEPTION 'Award item currency must be explicitly recorded before accepting a return';
  END IF;
  IF v_received_quantity <= 0 THEN
    RAISE EXCEPTION 'Only accepted-good received quantities can be returned for commission adjustment';
  END IF;

  SELECT coalesce(sum(r.returned_quantity),0)
    INTO v_item_returned
  FROM public.ammir_project_delivery_returns r
  WHERE r.receipt_item_id = v_receipt_item_id;
  SELECT coalesce(sum(r.returned_quantity),0)
    INTO v_claim_returned
  FROM public.ammir_project_delivery_returns r
  WHERE r.claim_id = p_claim_id;

  IF v_claim_returned + p_returned_quantity > v_claimed_quantity + 0.0005 THEN
    RAISE EXCEPTION 'Cumulative return quantity exceeds the accepted claim quantity';
  END IF;
  IF v_item_returned + p_returned_quantity > v_received_quantity + 0.0005 THEN
    RAISE EXCEPTION 'Cumulative return quantity exceeds the accepted-good receipt quantity';
  END IF;

  v_gross_return_value := round(p_returned_quantity * v_unit_rate, 2);

  INSERT INTO public.ammir_project_delivery_returns(
    project_id, delivery_id, claim_id, receipt_item_id, idempotency_key,
    returned_quantity, unit_rate_snapshot, gross_return_value, currency,
    return_note, accepted_by
  ) VALUES (
    v_project_id, v_delivery_id, p_claim_id, v_receipt_item_id, p_idempotency_key,
    p_returned_quantity, v_unit_rate, v_gross_return_value, v_currency,
    btrim(p_return_note), auth.uid()
  ) RETURNING id INTO v_return_id;

  -- The commission source is the immutable receipt batch that originally earned it.
  -- The original ledger row is locked only to serialize cumulative rounding; it is never updated.
  SELECT l.id, l.gross_amount, l.commission_amount, l.currency, l.status
    INTO v_ledger_id, v_ledger_gross, v_ledger_commission, v_ledger_currency, v_ledger_status
  FROM public.ammar_commission_ledger l
  WHERE l.source_type = 'project_delivery'
    AND l.source_id = v_delivery_id::text || ':' || v_currency || ':' || v_receipt_id::text
  FOR UPDATE;

  IF FOUND AND v_ledger_status IN ('due','paid') AND v_ledger_gross > 0
     AND v_ledger_commission > 0 AND v_ledger_currency = v_currency THEN
    SELECT coalesce(sum(r.gross_return_value),0)
      INTO v_total_returned_gross
    FROM public.ammir_project_delivery_returns r
    JOIN public.ammir_project_delivery_receipt_items ri ON ri.id = r.receipt_item_id
    WHERE ri.receipt_id = v_receipt_id
      AND r.currency = v_currency;

    v_target_adjustment := least(
      v_ledger_commission,
      round(v_ledger_commission * least(v_total_returned_gross, v_ledger_gross) / v_ledger_gross, 2)
    );

    SELECT coalesce(sum(a.adjustment_amount),0)
      INTO v_existing_adjustment
    FROM public.ammar_commission_adjustments a
    WHERE a.original_ledger_id = v_ledger_id;

    v_adjustment_delta := round(greatest(v_target_adjustment - v_existing_adjustment, 0), 2);
    IF v_adjustment_delta > 0 THEN
      INSERT INTO public.ammar_commission_adjustments(
        original_ledger_id, return_id, currency, adjustment_amount, status
      ) VALUES (
        v_ledger_id, v_return_id, v_currency, v_adjustment_delta, 'pending_review'
      );
    END IF;
  END IF;

  RETURN v_return_id;
END;
$function$;

REVOKE ALL ON FUNCTION app_private.ammir_record_project_delivery_return(uuid,numeric,uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION app_private.ammir_record_project_delivery_return(uuid,numeric,uuid,text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.ammir_record_delivery_return(
  p_claim_id uuid,
  p_returned_quantity numeric,
  p_idempotency_key uuid,
  p_return_note text
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT app_private.ammir_record_project_delivery_return(
    p_claim_id, p_returned_quantity, p_idempotency_key, p_return_note
  );
$function$;

REVOKE ALL ON FUNCTION public.ammir_record_delivery_return(uuid,numeric,uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ammir_record_delivery_return(uuid,numeric,uuid,text)
  TO authenticated;

COMMIT;
