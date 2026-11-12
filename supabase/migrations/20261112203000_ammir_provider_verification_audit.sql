-- Audited supplier and service-provider verification decisions
-- Only administrators can decide verification, suspension, or reinstatement
-- Decisions and evidence references are recorded in an append-only audit table

BEGIN;

CREATE TABLE IF NOT EXISTS public.ammar_provider_verification_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type text NOT NULL
    CHECK (entity_type IN ('supplier','service_provider')),
  entity_id uuid NOT NULL,
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  business_name_snapshot text NOT NULL,
  decision text NOT NULL
    CHECK (decision IN ('approved','rejected','suspended','reactivated','verification_revoked')),
  reason text NOT NULL
    CHECK (char_length(btrim(reason)) BETWEEN 5 AND 2000),
  evidence_reference text
    CHECK (evidence_reference IS NULL OR char_length(evidence_reference) <= 2000),
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.ammar_provider_verification_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ammir_admin_provider_verification_events_select
ON public.ammar_provider_verification_events;
CREATE POLICY ammir_admin_provider_verification_events_select
ON public.ammar_provider_verification_events
FOR SELECT TO authenticated
USING (public.is_admin());

DROP POLICY IF EXISTS ammir_admin_provider_verification_events_insert
ON public.ammar_provider_verification_events;
CREATE POLICY ammir_admin_provider_verification_events_insert
ON public.ammar_provider_verification_events
FOR INSERT TO authenticated
WITH CHECK (public.is_admin() AND actor_id = (SELECT auth.uid()));

CREATE INDEX IF NOT EXISTS ammir_provider_verification_events_entity_idx
ON public.ammar_provider_verification_events(entity_type, entity_id, created_at DESC);

CREATE INDEX IF NOT EXISTS ammir_provider_verification_events_actor_idx
ON public.ammar_provider_verification_events(actor_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.ammar_admin_review_provider(
  p_entity_type text,
  p_entity_id uuid,
  p_decision text,
  p_reason text,
  p_evidence_reference text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_owner_id uuid;
  v_business_name text;
  v_event_id uuid;
  v_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'administrator access required'
      USING ERRCODE = '42501';
  END IF;

  IF p_entity_type NOT IN ('supplier','service_provider') THEN
    RAISE EXCEPTION 'unsupported provider type' USING ERRCODE = '22023';
  END IF;

  IF p_decision NOT IN ('approved','rejected','suspended','reactivated','verification_revoked') THEN
    RAISE EXCEPTION 'unsupported review decision' USING ERRCODE = '22023';
  END IF;

  IF p_reason IS NULL OR char_length(btrim(p_reason)) NOT BETWEEN 5 AND 2000 THEN
    RAISE EXCEPTION 'a review reason between 5 and 2000 characters is required'
      USING ERRCODE = '22023';
  END IF;

  IF p_evidence_reference IS NOT NULL AND char_length(p_evidence_reference) > 2000 THEN
    RAISE EXCEPTION 'evidence reference is too long' USING ERRCODE = '22023';
  END IF;

  IF p_entity_type = 'supplier' THEN
    SELECT s.owner_id, s.business_name, s.status
    INTO v_owner_id, v_business_name, v_status
    FROM public.ammar_market_suppliers AS s
    WHERE s.id = p_entity_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'supplier not found' USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.ammar_market_suppliers AS s
    SET
      is_verified = CASE
        WHEN p_decision = 'approved' THEN true
        WHEN p_decision IN ('rejected','verification_revoked') THEN false
        ELSE s.is_verified
      END,
      verified_at = CASE
        WHEN p_decision = 'approved' THEN now()
        WHEN p_decision IN ('rejected','verification_revoked') THEN NULL
        ELSE s.verified_at
      END,
      status = CASE
        WHEN p_decision IN ('rejected','suspended') THEN 'suspended'
        WHEN p_decision = 'reactivated' THEN 'active'
        WHEN p_decision = 'approved' AND s.status = 'suspended' THEN 'active'
        ELSE s.status
      END,
      updated_at = now()
    WHERE s.id = p_entity_id;
  ELSE
    SELECT p.owner_id, p.business_name, p.status
    INTO v_owner_id, v_business_name, v_status
    FROM public.ammar_service_providers AS p
    WHERE p.id = p_entity_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'service provider not found' USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.ammar_service_providers AS p
    SET
      is_verified = CASE
        WHEN p_decision = 'approved' THEN true
        WHEN p_decision IN ('rejected','verification_revoked') THEN false
        ELSE p.is_verified
      END,
      verified_at = CASE
        WHEN p_decision = 'approved' THEN now()
        WHEN p_decision IN ('rejected','verification_revoked') THEN NULL
        ELSE p.verified_at
      END,
      status = CASE
        WHEN p_decision IN ('rejected','suspended') THEN 'suspended'
        WHEN p_decision = 'reactivated' THEN 'active'
        WHEN p_decision = 'approved' AND p.status = 'suspended' THEN 'active'
        ELSE p.status
      END,
      updated_at = now()
    WHERE p.id = p_entity_id;
  END IF;

  INSERT INTO public.ammar_provider_verification_events(
    entity_type, entity_id, owner_id, business_name_snapshot,
    decision, reason, evidence_reference, actor_id
  ) VALUES (
    p_entity_type, p_entity_id, v_owner_id, v_business_name,
    p_decision, btrim(p_reason), NULLIF(btrim(p_evidence_reference),''), auth.uid()
  )
  RETURNING id INTO v_event_id;

  RETURN v_event_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.ammar_admin_review_provider(text,uuid,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_admin_review_provider(text,uuid,text,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.ammar_admin_review_provider(text,uuid,text,text,text) TO authenticated;

COMMENT ON TABLE public.ammar_provider_verification_events
IS 'Append-only admin audit log for supplier and service-provider verification decisions';

COMMIT;
