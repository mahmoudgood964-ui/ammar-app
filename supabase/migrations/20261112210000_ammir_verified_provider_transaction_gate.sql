-- AMMIR transaction eligibility gate
-- Verification is required before a supplier or service provider can receive a formal order/award
-- Browsing and direct enquiries remain possible; transaction creation/acceptance is guarded server-side

BEGIN;

DROP POLICY IF EXISTS ammir_market_requests_insert ON public.ammar_market_requests;
CREATE POLICY ammir_market_requests_insert
ON public.ammar_market_requests
FOR INSERT TO authenticated
WITH CHECK (
  buyer_id = (SELECT auth.uid())
  AND EXISTS (
    SELECT 1
    FROM public.ammar_market_suppliers AS s
    WHERE s.id = ammar_market_requests.supplier_id
      AND s.status = 'active'
      AND s.is_verified = true
  )
  AND (
    project_id IS NULL
    OR public.ammar_project_role(project_id::text) IS NOT NULL
  )
);

DROP POLICY IF EXISTS ammar_service_offers_insert ON public.ammar_service_offers;
CREATE POLICY ammar_service_offers_insert
ON public.ammar_service_offers
FOR INSERT TO authenticated
WITH CHECK (
  created_by = (SELECT auth.uid())
  AND EXISTS (
    SELECT 1
    FROM public.ammar_service_providers AS sp
    WHERE sp.id = ammar_service_offers.provider_id
      AND sp.owner_id = (SELECT auth.uid())
      AND sp.status = 'active'
      AND sp.is_verified = true
  )
  AND EXISTS (
    SELECT 1
    FROM public.ammar_service_requests AS r
    WHERE r.id = ammar_service_offers.request_id
      AND r.status = 'open'
  )
);

CREATE OR REPLACE FUNCTION public.ammar_create_market_request(
  p_supplier_id uuid,
  p_product_id uuid,
  p_quantity numeric,
  p_project_id text DEFAULT NULL,
  p_buyer_note text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_project_id_type text;
  v_request_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero' USING ERRCODE = '22023';
  END IF;

  SELECT format_type(a.atttypid, a.atttypmod)
  INTO v_project_id_type
  FROM pg_attribute AS a
  WHERE a.attrelid = 'public.projects'::regclass
    AND a.attname = 'id'
    AND NOT a.attisdropped;

  IF v_project_id_type IS NULL THEN
    RAISE EXCEPTION 'Project identifier type could not be determined';
  END IF;

  IF nullif(trim(coalesce(p_project_id, '')), '') IS NOT NULL
     AND public.ammar_project_role(p_project_id) IS NULL THEN
    RAISE EXCEPTION 'You are not a member of the selected project'
      USING ERRCODE = '42501';
  END IF;

  EXECUTE format($query$
    INSERT INTO public.ammar_market_requests(
      buyer_id, supplier_id, project_id, currency, buyer_note
    )
    SELECT $1, $2,
           CASE WHEN nullif($3, '') IS NULL THEN NULL::%1$s ELSE $3::%1$s END,
           p.currency, $4
    FROM public.ammar_market_products AS p
    JOIN public.ammar_market_suppliers AS s ON s.id = p.supplier_id
    WHERE p.id = $5
      AND p.supplier_id = $2
      AND p.is_active = true
      AND p.availability IN ('available', 'limited')
      AND (p.quantity_available IS NULL OR p.quantity_available >= $6)
      AND s.status = 'active'
      AND s.is_verified = true
      AND s.owner_id <> $1
    RETURNING id
  $query$, v_project_id_type)
  INTO v_request_id
  USING auth.uid(), p_supplier_id, p_project_id, p_buyer_note, p_product_id, p_quantity;

  IF v_request_id IS NULL THEN
    RAISE EXCEPTION 'The supplier must be active and AMMIR-verified before a purchase request can be placed'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.ammar_market_request_items(
    request_id, product_id, product_title, unit, quantity, requested_unit_price
  )
  SELECT v_request_id, p.id, p.title, p.unit, p_quantity, p.price
  FROM public.ammar_market_products AS p
  WHERE p.id = p_product_id;

  INSERT INTO public.ammar_transaction_events(
    request_id, actor_id, event_type, summary, payload
  )
  VALUES (
    v_request_id,
    auth.uid(),
    'request_created',
    'تم إنشاء طلب شراء من سوق عَمِّر.',
    jsonb_build_object('product_id', p_product_id, 'quantity', p_quantity)
  );

  RETURN v_request_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ammar_accept_market_quote(p_quote_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  q public.ammar_market_quotes%ROWTYPE;
  r public.ammar_market_requests%ROWTYPE;
BEGIN
  SELECT *
  INTO q
  FROM public.ammar_market_quotes
  WHERE id = p_quote_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Quote not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT *
  INTO r
  FROM public.ammar_market_requests
  WHERE id = q.request_id
  FOR UPDATE;

  IF NOT FOUND OR r.buyer_id <> auth.uid() THEN
    RAISE EXCEPTION 'Only the buyer can accept this quote' USING ERRCODE = '42501';
  END IF;

  IF r.status NOT IN ('submitted', 'quoted') OR q.status <> 'proposed' THEN
    RAISE EXCEPTION 'This quote can no longer be accepted';
  END IF;

  IF q.supplier_id <> r.supplier_id OR NOT EXISTS (
    SELECT 1
    FROM public.ammar_market_suppliers AS s
    WHERE s.id = r.supplier_id
      AND s.status = 'active'
      AND s.is_verified = true
  ) THEN
    RAISE EXCEPTION 'Supplier must remain active and AMMIR-verified to accept a quote'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.ammar_market_quotes
  SET status = CASE WHEN id = q.id THEN 'accepted' ELSE 'rejected' END
  WHERE request_id = r.id
    AND status = 'proposed';

  UPDATE public.ammar_market_requests
  SET status = 'accepted',
      agreed_total = q.total_amount,
      currency = q.currency
  WHERE id = r.id;

  INSERT INTO public.ammar_transaction_events(
    request_id, actor_id, event_type, summary, payload
  )
  VALUES (
    r.id,
    auth.uid(),
    'quote_accepted',
    'تم قبول عرض المورد.',
    jsonb_build_object('quote_id', q.id, 'amount', q.total_amount, 'currency', q.currency)
  );

  RETURN r.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.ammar_accept_service_offer(p_offer_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  o public.ammar_service_offers%ROWTYPE;
  r public.ammar_service_requests%ROWTYPE;
BEGIN
  SELECT *
  INTO o
  FROM public.ammar_service_offers
  WHERE id = p_offer_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Offer not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT *
  INTO r
  FROM public.ammar_service_requests
  WHERE id = o.request_id
  FOR UPDATE;

  IF NOT FOUND
     OR r.requester_id <> auth.uid()
     OR r.status <> 'open'
     OR o.status <> 'proposed' THEN
    RAISE EXCEPTION 'Only the requester can accept an offer for an open request'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.ammar_service_providers AS sp
    WHERE sp.id = o.provider_id
      AND sp.status = 'active'
      AND sp.is_verified = true
  ) THEN
    RAISE EXCEPTION 'Service provider must be active and AMMIR-verified before an offer can be accepted'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.ammar_service_offers
  SET status = CASE WHEN id = o.id THEN 'accepted' ELSE 'rejected' END
  WHERE request_id = r.id
    AND status = 'proposed';

  UPDATE public.ammar_service_requests
  SET status = 'awarded'
  WHERE id = r.id;

  RETURN r.id;
END;
$function$;

COMMIT;