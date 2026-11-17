BEGIN;

ALTER TABLE public.ammar_conversations
  DROP CONSTRAINT IF EXISTS ammar_conversations_context_type_007_check;

ALTER TABLE public.ammar_conversations
  ADD CONSTRAINT ammar_conversations_context_type_007_check
  CHECK (context_type IN (
    'project','market_product','supplier','service_provider',
    'market_request','service_offer','market_quote','agreement'
  ));

CREATE OR REPLACE FUNCTION app_private.ammar_start_conversation(p_other_user uuid, p_context_type text, p_context_id text, p_subject text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_conversation uuid;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_other_user IS NULL OR p_other_user=v_user THEN
    RAISE EXCEPTION 'A different participant is required';
  END IF;
  IF p_context_type IS NULL OR p_context_type NOT IN (
    'project','market_product','supplier','service_provider','market_request','service_offer',
    'market_quote','agreement'
  ) OR coalesce(trim(p_context_id),'')='' THEN
    RAISE EXCEPTION 'A valid conversation context is required';
  END IF;

  IF p_context_type='project' THEN
    IF public.ammar_project_role(p_context_id) IS NULL THEN
      RAISE EXCEPTION 'You are not a member of this project';
    END IF;
    IF NOT EXISTS(
      SELECT 1 FROM public.projects p
      WHERE p.id::text=p_context_id
        AND (
          p.client_id=p_other_user
          OR EXISTS(
            SELECT 1 FROM public.project_members pm
            WHERE pm.project_id::text=p_context_id AND pm.user_id=p_other_user
          )
        )
    ) THEN
      RAISE EXCEPTION 'The other participant is not a member of this project';
    END IF;
  ELSIF p_context_type='market_product' THEN
    IF NOT EXISTS(
      SELECT 1 FROM public.ammar_market_products mp
      JOIN public.ammar_market_suppliers s ON s.id=mp.supplier_id
      WHERE mp.id::text=p_context_id AND s.owner_id=p_other_user
        AND mp.is_active=true AND s.status='active'
    ) THEN
      RAISE EXCEPTION 'The product does not belong to this supplier';
    END IF;
  ELSIF p_context_type='supplier' THEN
    IF NOT EXISTS(
      SELECT 1 FROM public.ammar_market_suppliers s
      WHERE s.id::text=p_context_id AND s.owner_id=p_other_user AND s.status='active'
    ) THEN
      RAISE EXCEPTION 'Supplier profile not found';
    END IF;
  ELSIF p_context_type='service_provider' THEN
    IF NOT EXISTS(
      SELECT 1 FROM public.ammar_service_providers sp
      WHERE sp.id::text=p_context_id AND sp.owner_id=p_other_user AND sp.status='active'
    ) THEN
      RAISE EXCEPTION 'Service provider profile not found';
    END IF;
  ELSIF p_context_type='market_request' THEN
    IF NOT EXISTS(
      SELECT 1 FROM public.ammar_market_requests r
      JOIN public.ammar_market_suppliers s ON s.id=r.supplier_id
      WHERE r.id::text=p_context_id
        AND (
          (r.buyer_id=v_user AND s.owner_id=p_other_user)
          OR (r.buyer_id=p_other_user AND s.owner_id=v_user)
        )
    ) THEN
      RAISE EXCEPTION 'You are not a party to this market request';
    END IF;
  ELSIF p_context_type='service_offer' THEN
    IF NOT EXISTS(
      SELECT 1 FROM public.ammar_service_offers o
      JOIN public.ammar_service_requests r ON r.id=o.request_id
      JOIN public.ammar_service_providers sp ON sp.id=o.provider_id
      WHERE o.id::text=p_context_id
        AND (
          (r.requester_id=v_user AND sp.owner_id=p_other_user)
          OR (r.requester_id=p_other_user AND sp.owner_id=v_user)
        )
    ) THEN
      RAISE EXCEPTION 'You are not a party to this service offer';
    END IF;
  ELSIF p_context_type='market_quote' THEN
    IF NOT EXISTS(
      SELECT 1
      FROM public.ammar_market_quotes q
      JOIN public.ammar_market_requests r ON r.id=q.request_id
      JOIN public.ammar_market_suppliers s ON s.id=q.supplier_id
      WHERE q.id::text=p_context_id
        AND (
          (r.buyer_id=v_user AND s.owner_id=p_other_user)
          OR (r.buyer_id=p_other_user AND s.owner_id=v_user)
        )
    ) THEN
      RAISE EXCEPTION 'You are not a party to this market quote';
    END IF;
  ELSIF p_context_type='agreement' THEN
    IF NOT EXISTS(
      SELECT 1 FROM public.ammar_agreements a
      WHERE a.id::text=p_context_id
        AND (
          (a.client_id=v_user AND a.provider_id=p_other_user)
          OR (a.client_id=p_other_user AND a.provider_id=v_user)
        )
    ) THEN
      RAISE EXCEPTION 'You are not a party to this agreement';
    END IF;
  END IF;

  SELECT c.id INTO v_conversation
  FROM public.ammar_conversations c
  WHERE c.context_type=p_context_type
    AND c.context_id=p_context_id
    AND EXISTS(
      SELECT 1 FROM public.ammar_conversation_participants cp
      WHERE cp.conversation_id=c.id AND cp.user_id=v_user
    )
    AND EXISTS(
      SELECT 1 FROM public.ammar_conversation_participants cp
      WHERE cp.conversation_id=c.id AND cp.user_id=p_other_user
    )
  ORDER BY c.created_at DESC LIMIT 1;

  IF v_conversation IS NULL THEN
    INSERT INTO public.ammar_conversations(context_type,context_id,subject,created_by)
    VALUES(p_context_type,p_context_id,nullif(trim(p_subject),''),v_user)
    RETURNING id INTO v_conversation;

    INSERT INTO public.ammar_conversation_participants(conversation_id,user_id,participant_role)
    VALUES
      (v_conversation,v_user,'customer'),
      (v_conversation,p_other_user,'provider')
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN v_conversation;
END;
$function$
;

COMMIT;
