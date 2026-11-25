-- AMMIR delivery claims and dispute workflow.
-- This records operational claims and an immutable event trail only.
-- It does not alter receipts, award quantities, commission, or settlement balances.

BEGIN;

CREATE TABLE IF NOT EXISTS public.ammir_project_delivery_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL REFERENCES public.projects(id) ON DELETE RESTRICT,
  delivery_id uuid NOT NULL,
  receipt_item_id uuid REFERENCES public.ammir_project_delivery_receipt_items(id) ON DELETE RESTRICT,
  claimant_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  claimant_side text NOT NULL CHECK (claimant_side IN ('project','supplier')),
  claim_type text NOT NULL CHECK (claim_type IN (
    'damaged_goods','missing_goods','rejected_goods','quality','wrong_item','documentation','other'
  )),
  claimed_quantity numeric(18,3),
  description text NOT NULL CHECK (char_length(btrim(description)) BETWEEN 20 AND 4000),
  status text NOT NULL DEFAULT 'open' CHECK (status IN (
    'open','under_review','response_requested','accepted','rejected','withdrawn','closed'
  )),
  resolution_note text,
  resolved_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ammir_delivery_claim_delivery_fk
    FOREIGN KEY (delivery_id,project_id)
    REFERENCES public.ammir_project_deliveries(id,project_id) ON DELETE RESTRICT,
  CHECK (claimed_quantity IS NULL OR claimed_quantity > 0),
  CHECK (
    (claim_type IN ('damaged_goods','missing_goods','rejected_goods','quality','wrong_item')
      AND claimed_quantity IS NOT NULL)
    OR (claim_type IN ('documentation','other'))
  ),
  CHECK (
    (status IN ('accepted','rejected') AND resolved_by IS NOT NULL AND resolved_at IS NOT NULL
      AND nullif(btrim(resolution_note),'') IS NOT NULL)
    OR (status NOT IN ('accepted','rejected') AND resolved_by IS NULL AND resolved_at IS NULL)
  )
);

CREATE INDEX IF NOT EXISTS ammir_delivery_claims_delivery_idx
  ON public.ammir_project_delivery_claims(delivery_id,created_at DESC);
CREATE INDEX IF NOT EXISTS ammir_delivery_claims_project_status_idx
  ON public.ammir_project_delivery_claims(project_id,status,created_at DESC);

CREATE TABLE IF NOT EXISTS public.ammir_project_delivery_claim_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  claim_id uuid NOT NULL REFERENCES public.ammir_project_delivery_claims(id) ON DELETE RESTRICT,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  event_type text NOT NULL CHECK (event_type IN (
    'opened','message','status_changed','resolved','withdrawn','evidence_added'
  )),
  from_status text,
  to_status text,
  body text,
  evidence_id uuid REFERENCES public.ammir_project_delivery_evidence(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (body IS NULL OR char_length(body) <= 4000)
);

CREATE INDEX IF NOT EXISTS ammir_delivery_claim_events_claim_idx
  ON public.ammir_project_delivery_claim_events(claim_id,created_at,id);

ALTER TABLE public.ammir_project_delivery_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammir_project_delivery_claim_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ammir_delivery_claims_select ON public.ammir_project_delivery_claims;
CREATE POLICY ammir_delivery_claims_select
ON public.ammir_project_delivery_claims
FOR SELECT TO authenticated
USING (
  claimant_id=(SELECT auth.uid())
  OR EXISTS (
    SELECT 1 FROM public.ammir_project_deliveries d
    WHERE d.id=ammir_project_delivery_claims.delivery_id
      AND d.project_id=ammir_project_delivery_claims.project_id
      AND (
        d.supplier_user_id=(SELECT auth.uid())
        OR app_private.ammar_project_role(d.project_id::text) IS NOT NULL
      )
  )
);

DROP POLICY IF EXISTS ammir_delivery_claim_events_select ON public.ammir_project_delivery_claim_events;
CREATE POLICY ammir_delivery_claim_events_select
ON public.ammir_project_delivery_claim_events
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.ammir_project_delivery_claims c
    JOIN public.ammir_project_deliveries d
      ON d.id=c.delivery_id AND d.project_id=c.project_id
    WHERE c.id=ammir_project_delivery_claim_events.claim_id
      AND (
        c.claimant_id=(SELECT auth.uid())
        OR d.supplier_user_id=(SELECT auth.uid())
        OR app_private.ammar_project_role(d.project_id::text) IS NOT NULL
      )
  )
);

REVOKE ALL ON public.ammir_project_delivery_claims FROM anon,authenticated;
REVOKE ALL ON public.ammir_project_delivery_claim_events FROM anon,authenticated;
GRANT SELECT ON public.ammir_project_delivery_claims TO authenticated;
GRANT SELECT ON public.ammir_project_delivery_claim_events TO authenticated;

CREATE OR REPLACE FUNCTION public.ammir_guard_delivery_claim_event_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public,pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'Delivery claim event history is immutable';
END;
$$;
REVOKE ALL ON FUNCTION public.ammir_guard_delivery_claim_event_immutable() FROM PUBLIC,anon,authenticated;
DROP TRIGGER IF EXISTS ammir_delivery_claim_event_immutable_trigger
  ON public.ammir_project_delivery_claim_events;
CREATE TRIGGER ammir_delivery_claim_event_immutable_trigger
BEFORE UPDATE OR DELETE ON public.ammir_project_delivery_claim_events
FOR EACH ROW EXECUTE FUNCTION public.ammir_guard_delivery_claim_event_immutable();

CREATE OR REPLACE FUNCTION app_private.ammir_submit_project_delivery_claim(
  p_delivery_id uuid,
  p_receipt_item_id uuid,
  p_claim_type text,
  p_claimed_quantity numeric,
  p_description text,
  p_evidence_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_project_id uuid;
  v_delivery_status text;
  v_supplier_id uuid;
  v_role text;
  v_claimant_side text;
  v_claim_id uuid;
  v_recorded_quantity numeric(18,3);
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF p_claim_type NOT IN ('damaged_goods','missing_goods','rejected_goods','quality','wrong_item','documentation','other') THEN
    RAISE EXCEPTION 'Invalid delivery claim type';
  END IF;
  IF char_length(btrim(coalesce(p_description,''))) NOT BETWEEN 20 AND 4000 THEN
    RAISE EXCEPTION 'Claim description must contain 20 to 4000 characters';
  END IF;
  IF p_claim_type IN ('damaged_goods','missing_goods','rejected_goods','quality','wrong_item')
     AND (p_claimed_quantity IS NULL OR p_claimed_quantity<=0) THEN
    RAISE EXCEPTION 'A positive claimed quantity is required for this claim type';
  END IF;
  IF p_claimed_quantity IS NOT NULL AND p_claimed_quantity<=0 THEN
    RAISE EXCEPTION 'Claimed quantity must be positive';
  END IF;

  SELECT d.project_id,d.status,d.supplier_user_id
    INTO v_project_id,v_delivery_status,v_supplier_id
  FROM public.ammir_project_deliveries d
  WHERE d.id=p_delivery_id
  FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Delivery not found'; END IF;
  IF v_delivery_status IN ('planned','cancelled') THEN
    RAISE EXCEPTION 'Claims can only be opened for dispatched deliveries';
  END IF;

  v_role := app_private.ammar_project_role(v_project_id::text);
  IF v_role = ANY(ARRAY['owner','manager','supervisor','engineer']::text[]) THEN
    v_claimant_side := 'project';
  ELSIF v_supplier_id=auth.uid() THEN
    v_claimant_side := 'supplier';
  ELSE
    RAISE EXCEPTION 'Only the project team or assigned supplier may open a delivery claim';
  END IF;

  IF p_claim_type IN ('damaged_goods','missing_goods','rejected_goods','quality','wrong_item')
     AND p_receipt_item_id IS NULL THEN
    RAISE EXCEPTION 'A quantity-based claim must reference a recorded receipt line';
  END IF;
  IF p_receipt_item_id IS NOT NULL THEN
    SELECT CASE p_claim_type
      WHEN 'damaged_goods' THEN ri.damaged_quantity
      WHEN 'missing_goods' THEN ri.missing_quantity
      WHEN 'rejected_goods' THEN ri.rejected_quantity
      WHEN 'quality' THEN ri.received_quantity
      WHEN 'wrong_item' THEN ri.received_quantity
      ELSE NULL
    END
    INTO v_recorded_quantity
    FROM public.ammir_project_delivery_receipt_items ri
    WHERE ri.id=p_receipt_item_id AND ri.delivery_id=p_delivery_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Claim receipt item must belong to the selected delivery';
    END IF;
    IF v_recorded_quantity IS NOT NULL AND p_claimed_quantity>v_recorded_quantity+0.0005 THEN
      RAISE EXCEPTION 'Claimed quantity exceeds the quantity recorded on the selected receipt line';
    END IF;
  END IF;
  IF p_evidence_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.ammir_project_delivery_evidence e
    WHERE e.id=p_evidence_id AND e.delivery_id=p_delivery_id
      AND e.project_id=v_project_id AND e.uploaded_by=auth.uid()
  ) THEN
    RAISE EXCEPTION 'Claim evidence must belong to this delivery and be uploaded by the current user';
  END IF;

  INSERT INTO public.ammir_project_delivery_claims(
    project_id,delivery_id,receipt_item_id,claimant_id,claimant_side,
    claim_type,claimed_quantity,description
  ) VALUES (
    v_project_id,p_delivery_id,p_receipt_item_id,auth.uid(),v_claimant_side,
    p_claim_type,p_claimed_quantity,btrim(p_description)
  ) RETURNING id INTO v_claim_id;

  INSERT INTO public.ammir_project_delivery_claim_events(
    claim_id,actor_id,event_type,to_status,body,evidence_id
  ) VALUES (
    v_claim_id,auth.uid(),'opened','open',btrim(p_description),p_evidence_id
  );
  RETURN v_claim_id;
END;
$function$;

CREATE OR REPLACE FUNCTION app_private.ammir_add_project_delivery_claim_message(
  p_claim_id uuid,
  p_message text,
  p_evidence_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_delivery_id uuid;
  v_project_id uuid;
  v_supplier_id uuid;
  v_claimant_id uuid;
  v_status text;
  v_event_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF char_length(btrim(coalesce(p_message,''))) NOT BETWEEN 1 AND 4000 THEN
    RAISE EXCEPTION 'Claim message must contain 1 to 4000 characters';
  END IF;

  SELECT c.delivery_id,c.project_id,c.claimant_id,c.status,d.supplier_user_id
    INTO v_delivery_id,v_project_id,v_claimant_id,v_status,v_supplier_id
  FROM public.ammir_project_delivery_claims c
  JOIN public.ammir_project_deliveries d
    ON d.id=c.delivery_id AND d.project_id=c.project_id
  WHERE c.id=p_claim_id
  FOR UPDATE OF c;
  IF NOT FOUND THEN RAISE EXCEPTION 'Delivery claim not found'; END IF;
  IF v_status IN ('accepted','rejected','withdrawn','closed') THEN
    RAISE EXCEPTION 'This delivery claim is closed for new messages';
  END IF;
  IF v_claimant_id<>auth.uid()
     AND v_supplier_id<>auth.uid()
     AND app_private.ammar_project_role(v_project_id::text) IS NULL THEN
    RAISE EXCEPTION 'Only claim parties may add a message';
  END IF;
  IF p_evidence_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.ammir_project_delivery_evidence e
    WHERE e.id=p_evidence_id AND e.delivery_id=v_delivery_id
      AND e.project_id=v_project_id AND e.uploaded_by=auth.uid()
  ) THEN
    RAISE EXCEPTION 'Claim evidence must belong to this delivery and be uploaded by the current user';
  END IF;

  INSERT INTO public.ammir_project_delivery_claim_events(
    claim_id,actor_id,event_type,body,evidence_id
  ) VALUES (
    p_claim_id,auth.uid(),CASE WHEN p_evidence_id IS NULL THEN 'message' ELSE 'evidence_added' END,
    btrim(p_message),p_evidence_id
  ) RETURNING id INTO v_event_id;
  RETURN v_event_id;
END;
$function$;

CREATE OR REPLACE FUNCTION app_private.ammir_transition_project_delivery_claim(
  p_claim_id uuid,
  p_new_status text,
  p_resolution_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_project_id uuid;
  v_claimant_id uuid;
  v_status text;
  v_role text;
  v_new_status text := p_new_status;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF v_new_status NOT IN ('under_review','response_requested','accepted','rejected','withdrawn','closed') THEN
    RAISE EXCEPTION 'Invalid delivery claim status';
  END IF;

  SELECT c.project_id,c.claimant_id,c.status
    INTO v_project_id,v_claimant_id,v_status
  FROM public.ammir_project_delivery_claims c
  WHERE c.id=p_claim_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Delivery claim not found'; END IF;

  v_role := app_private.ammar_project_role(v_project_id::text);
  IF v_new_status='withdrawn' AND v_claimant_id=auth.uid()
     AND v_status IN ('open','under_review','response_requested') THEN
    UPDATE public.ammir_project_delivery_claims
    SET status='withdrawn',updated_at=now()
    WHERE id=p_claim_id;
  ELSIF v_role=ANY(ARRAY['owner','manager','supervisor','engineer']::text[])
     AND (
       (v_status='open' AND v_new_status IN ('under_review','response_requested','accepted','rejected','closed'))
       OR (v_status='under_review' AND v_new_status IN ('response_requested','accepted','rejected','closed'))
       OR (v_status='response_requested' AND v_new_status IN ('under_review','accepted','rejected','closed'))
     ) THEN
    IF v_new_status IN ('accepted','rejected')
       AND char_length(btrim(coalesce(p_resolution_note,'')))<10 THEN
      RAISE EXCEPTION 'A resolution note of at least 10 characters is required';
    END IF;
    UPDATE public.ammir_project_delivery_claims
    SET status=v_new_status,
        resolution_note=CASE WHEN v_new_status IN ('accepted','rejected') THEN btrim(p_resolution_note) ELSE NULL END,
        resolved_by=CASE WHEN v_new_status IN ('accepted','rejected') THEN auth.uid() ELSE NULL END,
        resolved_at=CASE WHEN v_new_status IN ('accepted','rejected') THEN now() ELSE NULL END,
        updated_at=now()
    WHERE id=p_claim_id;
  ELSE
    RAISE EXCEPTION 'Invalid delivery claim status transition or permission denied';
  END IF;

  INSERT INTO public.ammir_project_delivery_claim_events(
    claim_id,actor_id,event_type,from_status,to_status,body
  ) VALUES (
    p_claim_id,auth.uid(),
    CASE WHEN v_new_status IN ('accepted','rejected') THEN 'resolved'
         WHEN v_new_status='withdrawn' THEN 'withdrawn'
         ELSE 'status_changed' END,
    v_status,v_new_status,
    CASE WHEN v_new_status IN ('accepted','rejected') THEN btrim(p_resolution_note) ELSE NULL END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.ammir_submit_delivery_claim(
  p_delivery_id uuid,
  p_receipt_item_id uuid,
  p_claim_type text,
  p_claimed_quantity numeric,
  p_description text,
  p_evidence_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT app_private.ammir_submit_project_delivery_claim(
    p_delivery_id,p_receipt_item_id,p_claim_type,p_claimed_quantity,p_description,p_evidence_id
  );
$function$;

CREATE OR REPLACE FUNCTION public.ammir_add_delivery_claim_message(
  p_claim_id uuid,
  p_message text,
  p_evidence_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT app_private.ammir_add_project_delivery_claim_message(
    p_claim_id,p_message,p_evidence_id
  );
$function$;

CREATE OR REPLACE FUNCTION public.ammir_transition_delivery_claim(
  p_claim_id uuid,
  p_new_status text,
  p_resolution_note text DEFAULT NULL
)
RETURNS void
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT app_private.ammir_transition_project_delivery_claim(
    p_claim_id,p_new_status,p_resolution_note
  );
$function$;

REVOKE ALL ON FUNCTION app_private.ammir_submit_project_delivery_claim(uuid,uuid,text,numeric,text,uuid)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION app_private.ammir_add_project_delivery_claim_message(uuid,text,uuid)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION app_private.ammir_transition_project_delivery_claim(uuid,text,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION app_private.ammir_submit_project_delivery_claim(uuid,uuid,text,numeric,text,uuid)
  TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION app_private.ammir_add_project_delivery_claim_message(uuid,text,uuid)
  TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION app_private.ammir_transition_project_delivery_claim(uuid,text,text)
  TO authenticated,service_role;

REVOKE ALL ON FUNCTION public.ammir_submit_delivery_claim(uuid,uuid,text,numeric,text,uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ammir_add_delivery_claim_message(uuid,text,uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.ammir_transition_delivery_claim(uuid,text,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ammir_submit_delivery_claim(uuid,uuid,text,numeric,text,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammir_add_delivery_claim_message(uuid,text,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammir_transition_delivery_claim(uuid,text,text)
  TO authenticated;

COMMIT;
