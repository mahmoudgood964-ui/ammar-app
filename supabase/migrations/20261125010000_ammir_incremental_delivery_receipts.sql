-- AMMIR incremental delivery receipts, rejection accounting and immutable commission entries.
-- Additive and reversible by migration rollback; no production rows are rewritten.

BEGIN;

ALTER TABLE public.ammir_project_delivery_items
  ADD COLUMN IF NOT EXISTS rejected_quantity numeric(18,3) NOT NULL DEFAULT 0
  CHECK (rejected_quantity >= 0);

ALTER TABLE public.ammir_project_delivery_items
  DROP CONSTRAINT IF EXISTS ammir_project_delivery_items_check;
ALTER TABLE public.ammir_project_delivery_items
  ADD CONSTRAINT ammir_delivery_item_quantities_accounted_check
  CHECK (
    received_quantity + damaged_quantity + missing_quantity + rejected_quantity
    <= expected_quantity + 0.0005
  );

CREATE TABLE IF NOT EXISTS public.ammir_project_delivery_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id uuid NOT NULL,
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  idempotency_key uuid NOT NULL,
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'array'),
  status text NOT NULL CHECK (status IN ('partially_received','received','exception')),
  evidence_id uuid REFERENCES public.ammir_project_delivery_evidence(id) ON DELETE SET NULL,
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ammir_delivery_receipt_delivery_fk
    FOREIGN KEY (delivery_id, project_id)
    REFERENCES public.ammir_project_deliveries(id, project_id) ON DELETE RESTRICT,
  UNIQUE (delivery_id, idempotency_key),
  UNIQUE (id, delivery_id, project_id)
);

CREATE TABLE IF NOT EXISTS public.ammir_project_delivery_receipt_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  receipt_id uuid NOT NULL,
  delivery_id uuid NOT NULL,
  project_id uuid NOT NULL,
  delivery_item_id uuid NOT NULL REFERENCES public.ammir_project_delivery_items(id) ON DELETE RESTRICT,
  received_quantity numeric(18,3) NOT NULL DEFAULT 0 CHECK (received_quantity >= 0),
  damaged_quantity numeric(18,3) NOT NULL DEFAULT 0 CHECK (damaged_quantity >= 0),
  missing_quantity numeric(18,3) NOT NULL DEFAULT 0 CHECK (missing_quantity >= 0),
  rejected_quantity numeric(18,3) NOT NULL DEFAULT 0 CHECK (rejected_quantity >= 0),
  condition_notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ammir_receipt_item_header_fk
    FOREIGN KEY (receipt_id, delivery_id, project_id)
    REFERENCES public.ammir_project_delivery_receipts(id, delivery_id, project_id) ON DELETE RESTRICT,
  UNIQUE (receipt_id, delivery_item_id),
  CHECK (received_quantity + damaged_quantity + missing_quantity + rejected_quantity >= 0)
);

CREATE INDEX IF NOT EXISTS ammir_delivery_receipts_delivery_idx
  ON public.ammir_project_delivery_receipts(delivery_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ammir_delivery_receipt_items_delivery_idx
  ON public.ammir_project_delivery_receipt_items(delivery_id, delivery_item_id);

ALTER TABLE public.ammir_project_delivery_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammir_project_delivery_receipt_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ammir_delivery_receipts_select ON public.ammir_project_delivery_receipts;
CREATE POLICY ammir_delivery_receipts_select
ON public.ammir_project_delivery_receipts
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.ammir_project_deliveries d
    WHERE d.id = ammir_project_delivery_receipts.delivery_id
      AND d.project_id = ammir_project_delivery_receipts.project_id
      AND (
        d.supplier_user_id = (SELECT auth.uid())
        OR app_private.ammar_project_role(d.project_id::text) IS NOT NULL
      )
  )
);

DROP POLICY IF EXISTS ammir_delivery_receipt_items_select ON public.ammir_project_delivery_receipt_items;
CREATE POLICY ammir_delivery_receipt_items_select
ON public.ammir_project_delivery_receipt_items
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.ammir_project_deliveries d
    WHERE d.id = ammir_project_delivery_receipt_items.delivery_id
      AND d.project_id = ammir_project_delivery_receipt_items.project_id
      AND (
        d.supplier_user_id = (SELECT auth.uid())
        OR app_private.ammar_project_role(d.project_id::text) IS NOT NULL
      )
  )
);

REVOKE ALL ON public.ammir_project_delivery_receipts FROM anon, authenticated;
REVOKE ALL ON public.ammir_project_delivery_receipt_items FROM anon, authenticated;
GRANT SELECT ON public.ammir_project_delivery_receipts TO authenticated;
GRANT SELECT ON public.ammir_project_delivery_receipt_items TO authenticated;

-- Delivery item quantities become append-only aggregates. Only the private receipt
-- RPC may update them; direct client writes cannot rewrite an accepted receipt.
CREATE OR REPLACE FUNCTION public.ammir_guard_delivery_item_receipt_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_setting('app.ammir_receipt_write', true) IS DISTINCT FROM 'on' THEN
    RAISE EXCEPTION 'Delivery quantities can only be changed through the receipt workflow';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Delivery item history cannot be deleted';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammir_guard_delivery_item_receipt_write_trigger
  ON public.ammir_project_delivery_items;
CREATE TRIGGER ammir_guard_delivery_item_receipt_write_trigger
BEFORE UPDATE OR DELETE ON public.ammir_project_delivery_items
FOR EACH ROW EXECUTE FUNCTION public.ammir_guard_delivery_item_receipt_write();

REVOKE UPDATE, DELETE ON public.ammir_project_delivery_items FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.ammir_guard_delivery_item_receipt_write() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ammir_guard_delivery_reconciliation_state() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ammir_validate_delivery_item() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ammir_reconcile_project_delivery(uuid,jsonb,text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.ammir_validate_delivery_item()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_awarded numeric(18,3);
  v_existing numeric(18,3);
  v_award_project uuid;
  v_delivery_status text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.award_item_id::text, 0));

  SELECT ai.awarded_quantity, ai.project_id
    INTO v_awarded, v_award_project
  FROM public.ammir_project_award_items ai
  WHERE ai.id = NEW.award_item_id;
  IF v_awarded IS NULL OR v_award_project <> NEW.project_id THEN
    RAISE EXCEPTION 'Delivery item must reference an award item in this project';
  END IF;

  SELECT d.status INTO v_delivery_status
  FROM public.ammir_project_deliveries d
  WHERE d.id = NEW.delivery_id AND d.project_id = NEW.project_id;
  IF v_delivery_status IS NULL OR (TG_OP = 'INSERT' AND v_delivery_status <> 'planned') THEN
    RAISE EXCEPTION 'Delivery items can only be created for a planned delivery';
  END IF;

  SELECT coalesce(sum(di.expected_quantity),0) INTO v_existing
  FROM public.ammir_project_delivery_items di
  WHERE di.award_item_id = NEW.award_item_id AND di.project_id = NEW.project_id
    AND di.id IS DISTINCT FROM NEW.id;
  IF v_existing + NEW.expected_quantity > v_awarded + 0.0005 THEN
    RAISE EXCEPTION 'Cumulative dispatched quantity exceeds the awarded quantity';
  END IF;

  IF NEW.received_quantity + NEW.damaged_quantity + NEW.missing_quantity + NEW.rejected_quantity
     > NEW.expected_quantity + 0.0005 THEN
    RAISE EXCEPTION 'Received, damaged, missing and rejected quantities cannot exceed dispatched quantity';
  END IF;
  RETURN NEW;
END;
$$;

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
  v_rejected numeric(20,3);
BEGIN
  IF NEW.status IN ('received','partially_received','exception') THEN
    SELECT count(*),
           coalesce(sum(expected_quantity),0),
           coalesce(sum(received_quantity),0),
           coalesce(sum(damaged_quantity),0),
           coalesce(sum(missing_quantity),0),
           coalesce(sum(rejected_quantity),0)
      INTO v_line_count,v_expected,v_received,v_damaged,v_missing,v_rejected
    FROM public.ammir_project_delivery_items
    WHERE delivery_id = NEW.id AND project_id = NEW.project_id;

    IF v_line_count = 0 THEN
      RAISE EXCEPTION 'A delivery cannot be reconciled before delivery items are recorded';
    END IF;

    IF NEW.status = 'received' AND
       (abs(v_received - v_expected) > 0.0005 OR v_damaged > 0 OR v_missing > 0 OR v_rejected > 0) THEN
      RAISE EXCEPTION 'A fully received delivery must account for every unit as accepted and good';
    END IF;

    IF NEW.status = 'partially_received' AND
       (v_damaged > 0 OR v_missing > 0 OR v_rejected > 0 OR v_received >= v_expected - 0.0005) THEN
      RAISE EXCEPTION 'Partially received status requires an outstanding balance with no damaged, missing or rejected quantity';
    END IF;

    IF NEW.status = 'exception' AND (v_damaged <= 0 AND v_missing <= 0 AND v_rejected <= 0) THEN
      RAISE EXCEPTION 'Exception status requires a damaged, missing or rejected quantity';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- Permit repeated manager reconciliation after a partial/exception receipt, but
-- prohibit cancellation once any receipt batch or quantity has been recorded.
CREATE OR REPLACE FUNCTION public.ammir_guard_delivery_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role text;
BEGIN
  v_role := app_private.ammar_project_role(OLD.project_id::text);

  IF OLD.status = 'planned' AND NEW.status = 'dispatched'
     AND OLD.supplier_user_id = auth.uid() THEN
    IF NEW.id IS DISTINCT FROM OLD.id
       OR NEW.award_id IS DISTINCT FROM OLD.award_id
       OR NEW.project_id IS DISTINCT FROM OLD.project_id
       OR NEW.supplier_user_id IS DISTINCT FROM OLD.supplier_user_id
       OR NEW.delivery_reference IS DISTINCT FROM OLD.delivery_reference
       OR NEW.scheduled_at IS DISTINCT FROM OLD.scheduled_at
       OR NEW.received_at IS DISTINCT FROM OLD.received_at
       OR NEW.received_by IS DISTINCT FROM OLD.received_by
       OR NEW.vehicle_or_carrier IS DISTINCT FROM OLD.vehicle_or_carrier
       OR NEW.notes IS DISTINCT FROM OLD.notes
       OR NEW.created_by IS DISTINCT FROM OLD.created_by
       OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
      RAISE EXCEPTION 'Supplier dispatch may only change delivery status';
    END IF;
    NEW.dispatched_at := now();
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  IF v_role IN ('owner','manager','supervisor','engineer') THEN
    IF OLD.status IN ('planned','dispatched') AND NEW.status = 'cancelled' THEN
      IF EXISTS (SELECT 1 FROM public.ammir_project_delivery_receipts r WHERE r.delivery_id = OLD.id)
         OR EXISTS (
           SELECT 1 FROM public.ammir_project_delivery_items i
           WHERE i.delivery_id = OLD.id
             AND (i.received_quantity > 0 OR i.damaged_quantity > 0 OR i.missing_quantity > 0 OR i.rejected_quantity > 0)
         ) THEN
        RAISE EXCEPTION 'A delivery with recorded receipt quantities cannot be cancelled; use the return workflow';
      END IF;
      NEW.updated_at := now();
      RETURN NEW;
    END IF;

    IF current_setting('app.ammir_receipt_write', true) = 'on'
       AND OLD.status IN ('dispatched','partially_received','exception')
       AND NEW.status IN ('received','partially_received','exception') THEN
      NEW.updated_at := now();
      RETURN NEW;
    END IF;
  END IF;

  RAISE EXCEPTION 'Invalid delivery status transition';
END;
$$;
DROP TRIGGER IF EXISTS ammir_guard_delivery_status_trigger ON public.ammir_project_deliveries;
CREATE TRIGGER ammir_guard_delivery_status_trigger
BEFORE UPDATE OF status ON public.ammir_project_deliveries
FOR EACH ROW EXECUTE FUNCTION public.ammir_guard_delivery_status();

REVOKE ALL ON FUNCTION public.ammir_guard_delivery_status() FROM PUBLIC, anon, authenticated;

-- Existing aggregate triggers could rewrite a previously paid commission row when
-- a later partial receipt arrived. Replace them with one immutable commission
-- entry per receipt batch. Each batch has a unique source_id and is idempotent.
DROP TRIGGER IF EXISTS ammir_project_delivery_commission_sync ON public.ammir_project_deliveries;
DROP TRIGGER IF EXISTS ammir_project_delivery_items_commission_sync ON public.ammir_project_delivery_items;

CREATE OR REPLACE FUNCTION app_private.ammir_record_project_delivery_receipt_commission(p_receipt_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_delivery_id uuid;
  v_project_id uuid;
  v_supplier_user_id uuid;
  v_activity_type text;
  v_provider_type text;
  v_is_supplier boolean := false;
  v_project_client_id uuid;
  v_currency text;
  v_gross numeric(14,2);
  v_rate numeric(5,2);
  v_payer_side text;
  v_payer_id uuid;
  v_source_id text;
  v_commission numeric(14,2);
BEGIN
  SELECT r.delivery_id, r.project_id, d.supplier_user_id
    INTO v_delivery_id, v_project_id, v_supplier_user_id
  FROM public.ammir_project_delivery_receipts r
  JOIN public.ammir_project_deliveries d ON d.id = r.delivery_id
  WHERE r.id = p_receipt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Delivery receipt batch not found'; END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.ammar_market_suppliers s
    WHERE s.owner_id = v_supplier_user_id
  ) INTO v_is_supplier;

  IF v_is_supplier THEN
    v_activity_type := 'market_materials';
  ELSE
    SELECT p.provider_type INTO v_provider_type
    FROM public.ammar_service_providers p
    WHERE p.owner_id = v_supplier_user_id
    LIMIT 1;
    v_activity_type := CASE
      WHEN v_provider_type = 'contractor' THEN 'contracting'
      WHEN v_provider_type = 'maintenance' THEN 'maintenance'
      WHEN v_provider_type = 'engineering' THEN 'engineering'
      ELSE 'other'
    END;
  END IF;

  SELECT pr.client_id INTO v_project_client_id
  FROM public.projects pr WHERE pr.id = v_project_id;

  FOR v_currency, v_gross IN
    SELECT coalesce(nullif(ai.currency,''),'SDG'),
           round(sum(ri.received_quantity * ai.unit_rate),2)
    FROM public.ammir_project_delivery_receipt_items ri
    JOIN public.ammir_project_award_items ai
      ON ai.id = (SELECT di.award_item_id
                  FROM public.ammir_project_delivery_items di
                  WHERE di.id = ri.delivery_item_id
                    AND di.delivery_id = ri.delivery_id
                    AND di.project_id = ri.project_id)
     AND ai.project_id = ri.project_id
    WHERE ri.receipt_id = p_receipt_id
    GROUP BY coalesce(nullif(ai.currency,''),'SDG')
    HAVING sum(ri.received_quantity * ai.unit_rate) > 0
  LOOP
    SELECT r.rate_percent, r.payer_side
      INTO v_rate, v_payer_side
    FROM public.ammar_commission_rules r
    WHERE r.activity_type = v_activity_type AND r.is_active = true
    ORDER BY r.effective_from DESC NULLS LAST
    LIMIT 1;
    IF NOT FOUND THEN CONTINUE; END IF;

    v_payer_id := CASE WHEN v_payer_side = 'customer'
      THEN v_project_client_id ELSE v_supplier_user_id END;
    IF v_payer_id IS NULL THEN
      RAISE EXCEPTION 'Cannot determine the payer for AMMIR project delivery commission';
    END IF;

    v_source_id := v_delivery_id::text || ':' || v_currency || ':' || p_receipt_id::text;
    v_commission := round(v_gross * v_rate / 100,2);

    INSERT INTO public.ammar_commission_ledger (
      request_id,activity_type,source_type,source_id,gross_amount,currency,
      rate_percent,commission_amount,payer_id,status
    ) VALUES (
      NULL,v_activity_type,'project_delivery',v_source_id,v_gross,v_currency,
      v_rate,v_commission,v_payer_id,'due'
    ) ON CONFLICT (source_type,source_id) DO NOTHING;

    IF NOT EXISTS (
      SELECT 1 FROM public.ammar_commission_ledger l
      WHERE l.source_type='project_delivery' AND l.source_id=v_source_id
        AND l.gross_amount=v_gross AND l.currency=v_currency
        AND l.rate_percent=v_rate AND l.commission_amount=v_commission
        AND l.payer_id=v_payer_id
    ) THEN
      RAISE EXCEPTION 'Delivery receipt commission source conflicts with an existing ledger entry';
    END IF;
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION app_private.ammir_record_project_delivery_receipt_commission(uuid)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION app_private.ammir_record_project_delivery_receipt(
  p_delivery_id uuid,
  p_items jsonb,
  p_status text,
  p_idempotency_key uuid,
  p_evidence_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_project_id uuid;
  v_current_status text;
  v_role text;
  v_receipt_id uuid;
  v_existing_payload jsonb;
  v_existing_status text;
  v_existing_evidence uuid;
  v_line_count integer;
  v_input_count integer;
  v_updated_count integer;
  v_expected numeric(20,3);
  v_received numeric(20,3);
  v_damaged numeric(20,3);
  v_missing numeric(20,3);
  v_rejected numeric(20,3);
  v_previous_setting text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'Receipt idempotency key is required'; END IF;
  IF p_status NOT IN ('received','partially_received','exception') THEN RAISE EXCEPTION 'Invalid receipt status'; END IF;
  IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Receipt lines must be a JSON array'; END IF;

  SELECT d.project_id,d.status INTO v_project_id,v_current_status
  FROM public.ammir_project_deliveries d
  WHERE d.id=p_delivery_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;

  v_role := app_private.ammar_project_role(v_project_id::text);
  IF coalesce(v_role = ANY(ARRAY['owner','manager','supervisor','engineer']::text[]),false) IS NOT TRUE THEN
    RAISE EXCEPTION 'Project manager permission required';
  END IF;

  SELECT r.id,r.payload,r.status,r.evidence_id
    INTO v_receipt_id,v_existing_payload,v_existing_status,v_existing_evidence
  FROM public.ammir_project_delivery_receipts r
  WHERE r.delivery_id=p_delivery_id AND r.idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF v_existing_payload=p_items AND v_existing_status=p_status
       AND v_existing_evidence IS NOT DISTINCT FROM p_evidence_id THEN
      RETURN v_receipt_id;
    END IF;
    RAISE EXCEPTION 'Receipt idempotency key was already used with a different payload';
  END IF;

  IF v_current_status NOT IN ('dispatched','partially_received','exception') THEN
    RAISE EXCEPTION 'Only dispatched or previously reconciled deliveries can receive another receipt batch';
  END IF;

  IF p_evidence_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.ammir_project_delivery_evidence e
    WHERE e.id=p_evidence_id AND e.delivery_id=p_delivery_id
      AND e.project_id=v_project_id AND e.uploaded_by=auth.uid()
  ) THEN
    RAISE EXCEPTION 'Receipt evidence must belong to this delivery and be uploaded by the current user';
  END IF;

  SELECT count(*) INTO v_line_count
  FROM public.ammir_project_delivery_items di
  WHERE di.delivery_id=p_delivery_id AND di.project_id=v_project_id;

  SELECT count(*) INTO v_input_count
  FROM jsonb_to_recordset(p_items) AS x(
    delivery_item_id uuid,received_quantity numeric,damaged_quantity numeric,
    missing_quantity numeric,rejected_quantity numeric,condition_notes text
  );

  IF v_line_count=0 OR v_input_count<>v_line_count THEN
    RAISE EXCEPTION 'Submit exactly one receipt row for every delivery item';
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_to_recordset(p_items) AS x(
      delivery_item_id uuid,received_quantity numeric,damaged_quantity numeric,
      missing_quantity numeric,rejected_quantity numeric,condition_notes text
    )
    GROUP BY delivery_item_id HAVING count(*)>1
  ) THEN RAISE EXCEPTION 'Duplicate delivery item in receipt'; END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_to_recordset(p_items) AS x(
      delivery_item_id uuid,received_quantity numeric,damaged_quantity numeric,
      missing_quantity numeric,rejected_quantity numeric,condition_notes text
    )
    LEFT JOIN public.ammir_project_delivery_items di
      ON di.id=x.delivery_item_id AND di.delivery_id=p_delivery_id AND di.project_id=v_project_id
    WHERE di.id IS NULL
       OR x.received_quantity IS NULL OR x.received_quantity<0
       OR x.damaged_quantity IS NULL OR x.damaged_quantity<0
       OR x.missing_quantity IS NULL OR x.missing_quantity<0
       OR x.rejected_quantity IS NULL OR x.rejected_quantity<0
       OR x.received_quantity+x.damaged_quantity+x.missing_quantity+x.rejected_quantity
          > di.expected_quantity-di.received_quantity-di.damaged_quantity-di.missing_quantity-di.rejected_quantity+0.0005
       OR (x.rejected_quantity>0 AND coalesce(nullif(btrim(x.condition_notes),''),'')='')
  ) THEN RAISE EXCEPTION 'Invalid receipt quantities, reason or delivery item reference'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM jsonb_to_recordset(p_items) AS x(
      delivery_item_id uuid,received_quantity numeric,damaged_quantity numeric,
      missing_quantity numeric,rejected_quantity numeric,condition_notes text
    )
    WHERE x.received_quantity+x.damaged_quantity+x.missing_quantity+x.rejected_quantity>0
  ) THEN RAISE EXCEPTION 'A receipt batch must record at least one quantity'; END IF;

  SELECT coalesce(sum(di.expected_quantity),0),
         coalesce(sum(di.received_quantity),0),
         coalesce(sum(di.damaged_quantity),0),
         coalesce(sum(di.missing_quantity),0),
         coalesce(sum(di.rejected_quantity),0)
    INTO v_expected,v_received,v_damaged,v_missing,v_rejected
  FROM public.ammir_project_delivery_items di
  WHERE di.delivery_id=p_delivery_id AND di.project_id=v_project_id;

  SELECT v_expected,
         v_received + coalesce(sum(x.received_quantity),0),
         v_damaged + coalesce(sum(x.damaged_quantity),0),
         v_missing + coalesce(sum(x.missing_quantity),0),
         v_rejected + coalesce(sum(x.rejected_quantity),0)
    INTO v_expected,v_received,v_damaged,v_missing,v_rejected
  FROM jsonb_to_recordset(p_items) AS x(
    delivery_item_id uuid,received_quantity numeric,damaged_quantity numeric,
    missing_quantity numeric,rejected_quantity numeric,condition_notes text
  );

  IF p_status='received' AND
     (abs(v_received-v_expected)>0.0005 OR v_damaged>0 OR v_missing>0 OR v_rejected>0) THEN
    RAISE EXCEPTION 'Fully received status requires all outstanding units to be accepted and good';
  END IF;
  IF p_status='partially_received' AND
     (v_damaged>0 OR v_missing>0 OR v_rejected>0 OR v_received>=v_expected-0.0005) THEN
    RAISE EXCEPTION 'Partial receipt requires remaining units and no damaged, missing or rejected units';
  END IF;
  IF p_status='exception' AND (v_damaged<=0 AND v_missing<=0 AND v_rejected<=0) THEN
    RAISE EXCEPTION 'Exception status requires a damaged, missing or rejected quantity';
  END IF;

  INSERT INTO public.ammir_project_delivery_receipts(
    delivery_id,project_id,idempotency_key,payload,status,evidence_id,created_by
  ) VALUES (
    p_delivery_id,v_project_id,p_idempotency_key,p_items,p_status,p_evidence_id,auth.uid()
  ) RETURNING id INTO v_receipt_id;

  INSERT INTO public.ammir_project_delivery_receipt_items(
    receipt_id,delivery_id,project_id,delivery_item_id,received_quantity,
    damaged_quantity,missing_quantity,rejected_quantity,condition_notes
  )
  SELECT v_receipt_id,p_delivery_id,v_project_id,x.delivery_item_id,
         x.received_quantity,x.damaged_quantity,x.missing_quantity,x.rejected_quantity,
         nullif(btrim(x.condition_notes),'')
  FROM jsonb_to_recordset(p_items) AS x(
    delivery_item_id uuid,received_quantity numeric,damaged_quantity numeric,
    missing_quantity numeric,rejected_quantity numeric,condition_notes text
  );

  v_previous_setting := current_setting('app.ammir_receipt_write',true);
  PERFORM set_config('app.ammir_receipt_write','on',true);

  UPDATE public.ammir_project_delivery_items di
  SET received_quantity=di.received_quantity+x.received_quantity,
      damaged_quantity=di.damaged_quantity+x.damaged_quantity,
      missing_quantity=di.missing_quantity+x.missing_quantity,
      rejected_quantity=di.rejected_quantity+x.rejected_quantity,
      condition_notes=coalesce(nullif(btrim(x.condition_notes),''),di.condition_notes),
      updated_at=now()
  FROM jsonb_to_recordset(p_items) AS x(
    delivery_item_id uuid,received_quantity numeric,damaged_quantity numeric,
    missing_quantity numeric,rejected_quantity numeric,condition_notes text
  )
  WHERE di.id=x.delivery_item_id AND di.delivery_id=p_delivery_id AND di.project_id=v_project_id;
  GET DIAGNOSTICS v_updated_count=ROW_COUNT;
  IF v_updated_count<>v_line_count THEN RAISE EXCEPTION 'Receipt batch did not update every delivery line'; END IF;

  UPDATE public.ammir_project_deliveries
  SET status=p_status,received_at=now(),received_by=auth.uid(),updated_at=now()
  WHERE id=p_delivery_id AND project_id=v_project_id;

  PERFORM app_private.ammir_record_project_delivery_receipt_commission(v_receipt_id);
  PERFORM set_config('app.ammir_receipt_write',coalesce(v_previous_setting,''),true);
  RETURN v_receipt_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ammir_record_delivery_receipt(
  p_delivery_id uuid,
  p_items jsonb,
  p_status text,
  p_idempotency_key uuid,
  p_evidence_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT app_private.ammir_record_project_delivery_receipt(
    p_delivery_id,p_items,p_status,p_idempotency_key,p_evidence_id
  );
$function$;

REVOKE ALL ON FUNCTION app_private.ammir_record_project_delivery_receipt(uuid,jsonb,text,uuid,uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ammir_record_delivery_receipt(uuid,jsonb,text,uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ammir_record_delivery_receipt(uuid,jsonb,text,uuid,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.ammir_void_cancelled_delivery_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.status='cancelled' AND OLD.status IS DISTINCT FROM NEW.status THEN
    IF EXISTS (SELECT 1 FROM public.ammir_project_delivery_receipts r WHERE r.delivery_id=NEW.id) THEN
      RAISE EXCEPTION 'A delivery with receipt history cannot be cancelled';
    END IF;
    UPDATE public.ammar_commission_ledger l
    SET status='void'
    WHERE l.source_type='project_delivery'
      AND l.source_id LIKE NEW.id::text || ':%'
      AND l.status<>'paid';
  END IF;
  RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION public.ammir_void_cancelled_delivery_commission() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS ammir_void_cancelled_delivery_commission_trigger ON public.ammir_project_deliveries;
CREATE TRIGGER ammir_void_cancelled_delivery_commission_trigger
AFTER UPDATE OF status ON public.ammir_project_deliveries
FOR EACH ROW EXECUTE FUNCTION public.ammir_void_cancelled_delivery_commission();

-- A supplier may attach evidence to later batches as well as the first dispatch.
DROP POLICY IF EXISTS ammir_delivery_evidence_insert ON public.ammir_project_delivery_evidence;
CREATE POLICY ammir_delivery_evidence_insert
ON public.ammir_project_delivery_evidence
FOR INSERT TO authenticated
WITH CHECK (
  app_private.ammar_project_role(project_id::text) = ANY(ARRAY['owner','manager','supervisor','engineer']::text[])
  OR (
    uploaded_by=(SELECT auth.uid())
    AND EXISTS (
      SELECT 1 FROM public.ammir_project_deliveries d
      WHERE d.id=ammir_project_delivery_evidence.delivery_id
        AND d.project_id=ammir_project_delivery_evidence.project_id
        AND d.supplier_user_id=(SELECT auth.uid())
        AND d.status IN ('planned','dispatched','partially_received','exception')
    )
  )
);

COMMIT;
