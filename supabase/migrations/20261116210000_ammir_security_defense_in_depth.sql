-- AMMIR: defense-in-depth for exposed RPCs and future public-schema objects.

-- This migration does not change payment workflow logic or add payment policies.

BEGIN;

CREATE OR REPLACE FUNCTION public.ammar_accept_agreement(p_agreement_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  a public.ammar_agreements%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO a FROM public.ammar_agreements WHERE id = p_agreement_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() NOT IN (a.client_id, a.provider_id) THEN
    RAISE EXCEPTION 'Agreement not found or access denied';
  END IF;
  IF a.status IN ('cancelled','rejected') THEN
    RAISE EXCEPTION 'This agreement can no longer be accepted';
  END IF;

  IF auth.uid() = a.client_id THEN
    UPDATE public.ammar_agreements
    SET client_accepted_at = coalesce(client_accepted_at, now())
    WHERE id = p_agreement_id
    RETURNING * INTO a;
  ELSE
    UPDATE public.ammar_agreements
    SET provider_accepted_at = coalesce(provider_accepted_at, now())
    WHERE id = p_agreement_id
    RETURNING * INTO a;
  END IF;

  IF a.client_accepted_at IS NOT NULL AND a.provider_accepted_at IS NOT NULL THEN
    UPDATE public.ammar_agreements SET status = 'accepted' WHERE id = p_agreement_id;
    INSERT INTO public.ammar_agreement_events(agreement_id, actor_id, event_type, note)
    VALUES (p_agreement_id, auth.uid(), 'accepted', 'Both parties accepted the agreement.');
    RETURN 'accepted';
  ELSE
    UPDATE public.ammar_agreements SET status = 'partially_accepted' WHERE id = p_agreement_id;
    INSERT INTO public.ammar_agreement_events(agreement_id, actor_id, event_type, note)
    VALUES (p_agreement_id, auth.uid(), 'accepted', 'One party accepted the agreement.');
    RETURN 'partially_accepted';
  END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.ammar_accept_market_quote(p_quote_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  q public.ammar_market_quotes%ROWTYPE;
  r public.ammar_market_requests%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO q FROM public.ammar_market_quotes WHERE id = p_quote_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Quote not found' USING ERRCODE = 'P0002'; END IF;

  SELECT * INTO r FROM public.ammar_market_requests WHERE id = q.request_id FOR UPDATE;
  IF NOT FOUND OR r.buyer_id <> auth.uid() THEN
    RAISE EXCEPTION 'Only the buyer can accept this quote' USING ERRCODE = '42501';
  END IF;
  IF r.status NOT IN ('submitted', 'quoted') OR q.status <> 'proposed' THEN
    RAISE EXCEPTION 'This quote can no longer be accepted';
  END IF;
  IF q.supplier_id <> r.supplier_id OR NOT EXISTS (
    SELECT 1 FROM public.ammar_market_suppliers AS s
    WHERE s.id = r.supplier_id AND s.status = 'active' AND s.is_verified = true
  ) THEN
    RAISE EXCEPTION 'Supplier must remain active and AMMIR-verified to accept a quote' USING ERRCODE = '42501';
  END IF;

  UPDATE public.ammar_market_quotes
  SET status = CASE WHEN id = q.id THEN 'accepted' ELSE 'rejected' END
  WHERE request_id = r.id AND status = 'proposed';

  UPDATE public.ammar_market_requests
  SET status = 'accepted', agreed_total = q.total_amount, currency = q.currency
  WHERE id = r.id;

  INSERT INTO public.ammar_transaction_events(request_id, actor_id, event_type, summary, payload)
  VALUES (r.id, auth.uid(), 'quote_accepted', 'تم قبول عرض المورد.',
    jsonb_build_object('quote_id', q.id, 'amount', q.total_amount, 'currency', q.currency));

  RETURN r.id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.ammar_accept_service_offer(p_offer_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  o public.ammar_service_offers%ROWTYPE;
  r public.ammar_service_requests%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO o FROM public.ammar_service_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Offer not found' USING ERRCODE = 'P0002'; END IF;

  SELECT * INTO r FROM public.ammar_service_requests WHERE id = o.request_id FOR UPDATE;
  IF NOT FOUND OR r.requester_id <> auth.uid() OR r.status <> 'open' OR o.status <> 'proposed' THEN
    RAISE EXCEPTION 'Only the requester can accept an offer for an open request' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.ammar_service_providers AS sp
    WHERE sp.id = o.provider_id AND sp.status = 'active' AND sp.is_verified = true
  ) THEN
    RAISE EXCEPTION 'Service provider must be active and AMMIR-verified before an offer can be accepted' USING ERRCODE = '42501';
  END IF;

  UPDATE public.ammar_service_offers
  SET status = CASE WHEN id = o.id THEN 'accepted' ELSE 'rejected' END
  WHERE request_id = r.id AND status = 'proposed';

  UPDATE public.ammar_service_requests SET status = 'awarded' WHERE id = r.id;
  RETURN r.id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.ammar_complete_service_request(p_request_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  r public.ammar_service_requests%ROWTYPE;
  o public.ammar_service_offers%ROWTYPE;
  v_provider_owner uuid;
  v_provider_type text;
  v_activity text;
  v_rate numeric(5,2);
  v_payer_side text;
  v_payer uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO r
  FROM public.ammar_service_requests
  WHERE id = p_request_id
  FOR UPDATE;
  IF NOT FOUND OR r.requester_id <> auth.uid() THEN
    RAISE EXCEPTION 'Only the service requester can confirm completion';
  END IF;
  IF r.status <> 'awarded' THEN
    RAISE EXCEPTION 'Only an awarded service request can be completed';
  END IF;

  SELECT * INTO o
  FROM public.ammar_service_offers
  WHERE request_id = r.id AND status = 'accepted'
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'An accepted service offer is required';
  END IF;

  SELECT owner_id, provider_type
  INTO v_provider_owner, v_provider_type
  FROM public.ammar_service_providers
  WHERE id = o.provider_id;

  UPDATE public.ammar_service_requests
  SET status = 'closed', updated_at = now()
  WHERE id = r.id;

  IF r.project_id IS NOT NULL THEN
    INSERT INTO public.project_expenses(
      project_id, description, amount, currency, spent_on, notes
    )
    VALUES (
      r.project_id,
      left('خدمة من عَمِّر - ' || r.title, 240),
      o.amount,
      o.currency,
      CURRENT_DATE,
      'AMMAR service offer: ' || o.id::text || '. Automatically recorded after requester confirmed completion.'
    );
  END IF;

  v_activity := CASE
    WHEN v_provider_type = 'contractor' THEN 'contracting'
    WHEN v_provider_type = 'maintenance' THEN 'maintenance'
    WHEN v_provider_type = 'engineering' THEN 'engineering'
    ELSE 'other'
  END;

  SELECT rate_percent, payer_side
  INTO v_rate, v_payer_side
  FROM public.ammar_commission_rules
  WHERE activity_type = v_activity AND is_active = true
  LIMIT 1;

  IF v_rate IS NOT NULL THEN
    v_payer := CASE WHEN v_payer_side = 'customer'
                    THEN r.requester_id ELSE v_provider_owner END;
    INSERT INTO public.ammar_commission_ledger(
      request_id, activity_type, source_type, source_id,
      gross_amount, currency, rate_percent, commission_amount, payer_id, status
    )
    VALUES (
      NULL, v_activity, 'service_offer', o.id::text,
      o.amount, o.currency, v_rate,
      round(o.amount * v_rate / 100, 2), v_payer, 'due'
    )
    ON CONFLICT (source_type, source_id) DO NOTHING;
  END IF;

  RETURN 'closed';
END;
$function$
;

ALTER FUNCTION public.ammar_accept_agreement(uuid) SET search_path = '';

ALTER FUNCTION public.ammar_accept_market_quote(uuid) SET search_path = '';

ALTER FUNCTION public.ammar_accept_project_invitation(text) SET search_path = '';

ALTER FUNCTION public.ammar_accept_service_offer(uuid) SET search_path = '';

ALTER FUNCTION public.ammar_admin_list_message_reports(integer) SET search_path = '';

ALTER FUNCTION public.ammar_admin_review_provider(text, uuid, text, text, text) SET search_path = '';

ALTER FUNCTION public.ammar_advance_market_request(uuid, text, text) SET search_path = '';

ALTER FUNCTION public.ammar_complete_service_request(uuid) SET search_path = '';

ALTER FUNCTION public.ammar_create_market_request(uuid, uuid, numeric, text, text) SET search_path = '';

ALTER FUNCTION public.ammar_create_project_invitation(text, text, text) SET search_path = '';

ALTER FUNCTION public.ammar_forward_message(uuid, uuid) SET search_path = '';

ALTER FUNCTION public.ammar_get_conversation_presence(uuid, uuid) SET search_path = '';

ALTER FUNCTION public.ammar_is_conversation_member(uuid) SET search_path = '';

ALTER FUNCTION public.ammar_mark_conversation_delivered(uuid) SET search_path = '';

ALTER FUNCTION public.ammar_mark_conversation_read(uuid) SET search_path = '';

ALTER FUNCTION public.ammar_message_to_change_order(uuid, text, text, numeric, text, integer) SET search_path = '';

ALTER FUNCTION public.ammar_message_to_project_task(uuid) SET search_path = '';

ALTER FUNCTION public.ammar_project_role(text) SET search_path = '';

ALTER FUNCTION public.ammar_remove_project_member(text, uuid) SET search_path = '';

ALTER FUNCTION public.ammar_revoke_project_invitation(text, uuid) SET search_path = '';

ALTER FUNCTION public.ammar_set_presence(boolean) SET search_path = '';

ALTER FUNCTION public.ammar_start_conversation(uuid, text, text, text) SET search_path = '';

ALTER FUNCTION public.ammar_update_project_member_role(text, uuid, text) SET search_path = '';

ALTER FUNCTION public.is_admin() SET search_path = '';

ALTER FUNCTION public.is_project_member(uuid) SET search_path = '';

DO $ammir_payment_table_lockdown$
BEGIN
  -- The bank-milestone feature remains paused. Lock direct API table access only
  -- when these legacy tables exist; do not create them or change their workflow.
  IF to_regclass('public.project_payment_milestones') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON TABLE public.project_payment_milestones FROM anon, authenticated';
  END IF;
  IF to_regclass('public.project_payment_events') IS NOT NULL THEN
    EXECUTE 'REVOKE ALL ON TABLE public.project_payment_events FROM anon, authenticated';
  END IF;
END
$ammir_payment_table_lockdown$;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;

COMMIT;
