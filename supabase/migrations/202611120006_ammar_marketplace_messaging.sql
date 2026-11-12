-- AMMAR ecosystem foundation: supplier marketplace, service RFQs, messaging,
-- agreements, trust records and configurable transaction commission.
-- Additive only: does not alter or delete existing AMMAR project records.
-- Apply after 202611120005_bank_payment_workflow.sql.

BEGIN;

CREATE TABLE IF NOT EXISTS public.ammar_market_suppliers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  business_name text NOT NULL CHECK (char_length(business_name) BETWEEN 2 AND 180),
  contact_name text,
  contact_phone text,
  whatsapp_phone text,
  governorate text,
  city text,
  area text,
  market_name text,
  address text,
  description text,
  logo_path text,
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','paused','suspended')),
  is_verified boolean NOT NULL DEFAULT false,
  verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ammar_market_products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id uuid NOT NULL REFERENCES public.ammar_market_suppliers(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (char_length(title) BETWEEN 2 AND 180),
  category text NOT NULL,
  brand text,
  description text,
  unit text NOT NULL,
  price numeric(14,2) NOT NULL CHECK (price >= 0),
  currency text NOT NULL DEFAULT 'SDG',
  quantity_available numeric(14,3) CHECK (quantity_available IS NULL OR quantity_available >= 0),
  availability text NOT NULL DEFAULT 'available'
    CHECK (availability IN ('available','limited','unavailable')),
  image_path text,
  is_active boolean NOT NULL DEFAULT true,
  price_updated_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ammar_service_providers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  business_name text NOT NULL CHECK (char_length(business_name) BETWEEN 2 AND 180),
  provider_type text NOT NULL
    CHECK (provider_type IN ('contractor','maintenance','engineering','transport','equipment_rental','other')),
  contact_name text,
  contact_phone text,
  governorate text,
  city text,
  area text,
  address text,
  description text,
  portfolio_url text,
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','paused','suspended')),
  is_verified boolean NOT NULL DEFAULT false,
  verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $ammar_schema$
DECLARE
  project_id_type text;
BEGIN
  SELECT format_type(a.atttypid, a.atttypmod)
    INTO project_id_type
  FROM pg_attribute a
  WHERE a.attrelid = 'public.projects'::regclass
    AND a.attname = 'id'
    AND NOT a.attisdropped;

  IF project_id_type IS NULL THEN
    RAISE EXCEPTION 'AMMAR migration stopped: public.projects.id was not found';
  END IF;

  EXECUTE format($ddl$
    CREATE TABLE IF NOT EXISTS public.ammar_market_requests (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      buyer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
      supplier_id uuid NOT NULL REFERENCES public.ammar_market_suppliers(id) ON DELETE RESTRICT,
      project_id %s REFERENCES public.projects(id) ON DELETE SET NULL,
      status text NOT NULL DEFAULT 'submitted'
        CHECK (status IN ('draft','submitted','quoted','accepted','fulfilling','delivered','completed','cancelled','disputed')),
      delivery_governorate text,
      delivery_city text,
      delivery_area text,
      delivery_address text,
      buyer_note text,
      agreed_total numeric(14,2) CHECK (agreed_total IS NULL OR agreed_total >= 0),
      currency text NOT NULL DEFAULT 'SDG',
      submitted_at timestamptz NOT NULL DEFAULT now(),
      completed_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    )
  $ddl$, project_id_type);

  EXECUTE format($ddl$
    CREATE TABLE IF NOT EXISTS public.ammar_service_requests (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      requester_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
      project_id %s REFERENCES public.projects(id) ON DELETE SET NULL,
      service_type text NOT NULL
        CHECK (service_type IN ('contractor','renovation','maintenance','engineering','inspection','transport','equipment_rental','other')),
      title text NOT NULL CHECK (char_length(title) BETWEEN 5 AND 180),
      description text NOT NULL CHECK (char_length(description) BETWEEN 10 AND 6000),
      governorate text,
      city text,
      area text,
      budget_min numeric(14,2) CHECK (budget_min IS NULL OR budget_min >= 0),
      budget_max numeric(14,2) CHECK (budget_max IS NULL OR budget_max >= 0),
      currency text NOT NULL DEFAULT 'SDG',
      target_start_date date,
      status text NOT NULL DEFAULT 'open'
        CHECK (status IN ('draft','open','reviewing','awarded','closed','cancelled')),
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      CHECK (budget_min IS NULL OR budget_max IS NULL OR budget_max >= budget_min)
    )
  $ddl$, project_id_type);

  EXECUTE format($ddl$
    CREATE TABLE IF NOT EXISTS public.ammar_agreements (
      id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
      project_id %s REFERENCES public.projects(id) ON DELETE SET NULL,
      source_type text NOT NULL DEFAULT 'project'
        CHECK (source_type IN ('project','market_request','service_offer')),
      source_id text,
      client_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
      provider_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
      title text NOT NULL CHECK (char_length(title) BETWEEN 3 AND 180),
      scope text NOT NULL CHECK (char_length(scope) BETWEEN 10 AND 8000),
      amount numeric(14,2) NOT NULL CHECK (amount >= 0),
      currency text NOT NULL DEFAULT 'SDG',
      schedule_text text,
      terms text,
      status text NOT NULL DEFAULT 'sent'
        CHECK (status IN ('draft','sent','partially_accepted','accepted','rejected','cancelled')),
      created_by uuid NOT NULL REFERENCES auth.users(id),
      client_accepted_at timestamptz,
      provider_accepted_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      CHECK (client_id <> provider_id)
    )
  $ddl$, project_id_type);
END
$ammar_schema$;

ALTER TABLE public.ammar_market_requests
  ADD COLUMN IF NOT EXISTS project_expense_id uuid
  REFERENCES public.project_expenses(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS public.ammar_market_request_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.ammar_market_requests(id) ON DELETE CASCADE,
  product_id uuid REFERENCES public.ammar_market_products(id) ON DELETE SET NULL,
  product_title text NOT NULL,
  unit text NOT NULL,
  quantity numeric(14,3) NOT NULL CHECK (quantity > 0),
  requested_unit_price numeric(14,2) CHECK (requested_unit_price IS NULL OR requested_unit_price >= 0),
  buyer_note text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ammar_market_quotes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.ammar_market_requests(id) ON DELETE CASCADE,
  supplier_id uuid NOT NULL REFERENCES public.ammar_market_suppliers(id) ON DELETE RESTRICT,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  total_amount numeric(14,2) NOT NULL CHECK (total_amount >= 0),
  currency text NOT NULL DEFAULT 'SDG',
  delivery_days integer CHECK (delivery_days IS NULL OR delivery_days BETWEEN 0 AND 3650),
  valid_until date,
  notes text,
  status text NOT NULL DEFAULT 'proposed'
    CHECK (status IN ('proposed','accepted','rejected','withdrawn')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ammar_service_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.ammar_service_requests(id) ON DELETE CASCADE,
  provider_id uuid NOT NULL REFERENCES public.ammar_service_providers(id) ON DELETE RESTRICT,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  amount numeric(14,2) NOT NULL CHECK (amount >= 0),
  currency text NOT NULL DEFAULT 'SDG',
  duration_days integer CHECK (duration_days IS NULL OR duration_days BETWEEN 1 AND 3650),
  inclusions text,
  exclusions text,
  warranty_months integer CHECK (warranty_months IS NULL OR warranty_months BETWEEN 0 AND 600),
  status text NOT NULL DEFAULT 'proposed'
    CHECK (status IN ('proposed','accepted','rejected','withdrawn')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ammar_conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  context_type text NOT NULL
    CHECK (context_type IN ('project','market_product','supplier','market_request','service_offer')),
  context_id text NOT NULL,
  subject text,
  created_by uuid NOT NULL REFERENCES auth.users(id),
  last_message_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ammar_conversation_participants (
  conversation_id uuid NOT NULL REFERENCES public.ammar_conversations(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  participant_role text NOT NULL DEFAULT 'participant'
    CHECK (participant_role IN ('participant','customer','provider')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  last_read_at timestamptz,
  PRIMARY KEY (conversation_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.ammar_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.ammar_conversations(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  message_type text NOT NULL DEFAULT 'text'
    CHECK (message_type IN ('text','image','file','system')),
  body text,
  file_path text,
  file_name text,
  mime_type text,
  reply_to_id uuid REFERENCES public.ammar_messages(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (
    (message_type IN ('text','system') AND body IS NOT NULL AND char_length(body) BETWEEN 1 AND 5000)
    OR
    (message_type IN ('image','file') AND file_path IS NOT NULL)
  )
);

CREATE TABLE IF NOT EXISTS public.ammar_user_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  notification_type text NOT NULL,
  title text NOT NULL,
  body text,
  conversation_id uuid REFERENCES public.ammar_conversations(id) ON DELETE CASCADE,
  message_id uuid REFERENCES public.ammar_messages(id) ON DELETE CASCADE,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ammar_agreement_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agreement_id uuid NOT NULL REFERENCES public.ammar_agreements(id) ON DELETE CASCADE,
  actor_id uuid NOT NULL REFERENCES auth.users(id),
  event_type text NOT NULL CHECK (event_type IN ('created','sent','accepted','rejected','cancelled','amended')),
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ammar_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.ammar_market_requests(id) ON DELETE RESTRICT,
  reviewer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  reviewed_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  rating integer NOT NULL CHECK (rating BETWEEN 1 AND 5),
  review_text text CHECK (review_text IS NULL OR char_length(review_text) <= 2000),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (request_id, reviewer_id),
  CHECK (reviewer_id <> reviewed_user_id)
);

CREATE TABLE IF NOT EXISTS public.ammar_disputes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.ammar_market_requests(id) ON DELETE RESTRICT,
  raised_by uuid NOT NULL REFERENCES auth.users(id),
  reason text NOT NULL CHECK (char_length(reason) BETWEEN 10 AND 5000),
  evidence_note text,
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open','under_review','resolved','rejected')),
  resolution_note text,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ammar_commission_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  activity_type text NOT NULL UNIQUE
    CHECK (activity_type IN ('market_materials','contracting','maintenance','engineering','other')),
  rate_percent numeric(5,2) NOT NULL DEFAULT 5.00
    CHECK (rate_percent >= 0 AND rate_percent <= 100),
  payer_side text NOT NULL DEFAULT 'provider'
    CHECK (payer_side IN ('provider','customer')),
  is_active boolean NOT NULL DEFAULT true,
  effective_from timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ammar_commission_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid UNIQUE REFERENCES public.ammar_market_requests(id) ON DELETE RESTRICT,
  activity_type text NOT NULL DEFAULT 'market_materials'
    CHECK (activity_type IN ('market_materials','contracting','maintenance','engineering','other')),
  source_type text NOT NULL DEFAULT 'market_request'
    CHECK (source_type IN ('market_request','service_offer')),
  source_id text NOT NULL,
  gross_amount numeric(14,2) NOT NULL CHECK (gross_amount >= 0),
  currency text NOT NULL,
  rate_percent numeric(5,2) NOT NULL CHECK (rate_percent >= 0 AND rate_percent <= 100),
  commission_amount numeric(14,2) NOT NULL CHECK (commission_amount >= 0),
  payer_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'recorded'
    CHECK (status IN ('recorded','due','paid','void','refunded')),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  settled_at timestamptz,
  UNIQUE(source_type, source_id)
);

CREATE TABLE IF NOT EXISTS public.ammar_transaction_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.ammar_market_requests(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  event_type text NOT NULL,
  summary text NOT NULL CHECK (char_length(summary) BETWEEN 1 AND 1000),
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.ammar_commission_rules(activity_type, rate_percent, payer_side)
VALUES
  ('market_materials', 5.00, 'provider'),
  ('contracting', 5.00, 'provider'),
  ('maintenance', 5.00, 'provider'),
  ('engineering', 5.00, 'provider'),
  ('other', 5.00, 'provider')
ON CONFLICT (activity_type) DO NOTHING;

CREATE INDEX IF NOT EXISTS ammar_market_products_catalog_idx
  ON public.ammar_market_products(category, is_active, created_at DESC);
CREATE INDEX IF NOT EXISTS ammar_market_products_supplier_idx
  ON public.ammar_market_products(supplier_id, is_active, updated_at DESC);
CREATE INDEX IF NOT EXISTS ammar_market_suppliers_location_idx
  ON public.ammar_market_suppliers(governorate, city, area, market_name);
CREATE INDEX IF NOT EXISTS ammar_market_requests_buyer_idx
  ON public.ammar_market_requests(buyer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ammar_market_requests_supplier_idx
  ON public.ammar_market_requests(supplier_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS ammar_service_requests_status_idx
  ON public.ammar_service_requests(status, service_type, created_at DESC);
CREATE INDEX IF NOT EXISTS ammar_service_offers_request_idx
  ON public.ammar_service_offers(request_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ammar_conversation_participants_user_idx
  ON public.ammar_conversation_participants(user_id, last_read_at);
CREATE INDEX IF NOT EXISTS ammar_messages_conversation_idx
  ON public.ammar_messages(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ammar_notifications_user_idx
  ON public.ammar_user_notifications(user_id, read_at, created_at DESC);
CREATE INDEX IF NOT EXISTS ammar_agreements_parties_idx
  ON public.ammar_agreements(client_id, provider_id, status);
CREATE INDEX IF NOT EXISTS ammar_disputes_request_idx
  ON public.ammar_disputes(request_id, status, created_at DESC);

CREATE OR REPLACE FUNCTION public.ammar_market_product_price_stamp()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.price IS DISTINCT FROM OLD.price THEN
    NEW.price_updated_at := now();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammar_market_product_price_stamp_trigger ON public.ammar_market_products;
CREATE TRIGGER ammar_market_product_price_stamp_trigger
BEFORE UPDATE ON public.ammar_market_products
FOR EACH ROW EXECUTE FUNCTION public.ammar_market_product_price_stamp();

CREATE OR REPLACE FUNCTION public.ammar_ecosystem_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DO $ammar_touch$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'ammar_market_suppliers','ammar_market_products','ammar_service_providers',
    'ammar_market_requests','ammar_market_quotes','ammar_service_requests',
    'ammar_service_offers','ammar_agreements','ammar_disputes'
  ]
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t || '_touch_updated_at', t);
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.ammar_ecosystem_touch_updated_at()',
      t || '_touch_updated_at', t
    );
  END LOOP;
END
$ammar_touch$;

CREATE OR REPLACE FUNCTION public.ammar_is_conversation_member(
  p_conversation_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.ammar_conversation_participants cp
    WHERE cp.conversation_id = p_conversation_id
      AND cp.user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.ammar_start_conversation(
  p_other_user uuid,
  p_context_type text,
  p_context_id text,
  p_subject text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_conversation uuid;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_other_user IS NULL OR p_other_user = v_user THEN
    RAISE EXCEPTION 'A different participant is required';
  END IF;
  IF p_context_type IS NULL OR p_context_type NOT IN ('project','market_product','supplier','market_request','service_offer')
     OR coalesce(trim(p_context_id),'') = '' THEN
    RAISE EXCEPTION 'A valid conversation context is required';
  END IF;

  IF p_context_type = 'project' THEN
    IF public.ammar_project_role(p_context_id) IS NULL THEN
      RAISE EXCEPTION 'You are not a member of this project';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.projects p
      WHERE p.id::text = p_context_id
        AND (
          p.client_id = p_other_user
          OR EXISTS (
            SELECT 1 FROM public.project_members pm
            WHERE pm.project_id::text = p_context_id AND pm.user_id = p_other_user
          )
        )
    ) THEN
      RAISE EXCEPTION 'The other participant is not a member of this project';
    END IF;
  ELSIF p_context_type = 'market_product' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.ammar_market_products mp
      JOIN public.ammar_market_suppliers s ON s.id = mp.supplier_id
      WHERE mp.id::text = p_context_id
        AND s.owner_id = p_other_user
        AND mp.is_active = true
        AND s.status = 'active'
    ) THEN
      RAISE EXCEPTION 'The product does not belong to this supplier';
    END IF;
  ELSIF p_context_type = 'supplier' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.ammar_market_suppliers s
      WHERE s.id::text = p_context_id AND s.owner_id = p_other_user AND s.status = 'active'
    ) THEN
      RAISE EXCEPTION 'Supplier profile not found';
    END IF;
  ELSIF p_context_type = 'market_request' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.ammar_market_requests r
      JOIN public.ammar_market_suppliers s ON s.id = r.supplier_id
      WHERE r.id::text = p_context_id
        AND (
          (r.buyer_id = v_user AND s.owner_id = p_other_user)
          OR
          (r.buyer_id = p_other_user AND s.owner_id = v_user)
        )
    ) THEN
      RAISE EXCEPTION 'You are not a party to this market request';
    END IF;
  ELSIF p_context_type = 'service_offer' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.ammar_service_offers o
      JOIN public.ammar_service_requests r ON r.id = o.request_id
      JOIN public.ammar_service_providers sp ON sp.id = o.provider_id
      WHERE o.id::text = p_context_id
        AND (
          (r.requester_id = v_user AND sp.owner_id = p_other_user)
          OR
          (r.requester_id = p_other_user AND sp.owner_id = v_user)
        )
    ) THEN
      RAISE EXCEPTION 'You are not a party to this service offer';
    END IF;
  END IF;

  SELECT c.id INTO v_conversation
  FROM public.ammar_conversations c
  WHERE c.context_type = p_context_type
    AND c.context_id = p_context_id
    AND EXISTS (
      SELECT 1 FROM public.ammar_conversation_participants cp
      WHERE cp.conversation_id = c.id AND cp.user_id = v_user
    )
    AND EXISTS (
      SELECT 1 FROM public.ammar_conversation_participants cp
      WHERE cp.conversation_id = c.id AND cp.user_id = p_other_user
    )
  ORDER BY c.created_at DESC
  LIMIT 1;

  IF v_conversation IS NULL THEN
    INSERT INTO public.ammar_conversations(context_type, context_id, subject, created_by)
    VALUES (p_context_type, p_context_id, nullif(trim(p_subject),''), v_user)
    RETURNING id INTO v_conversation;

    INSERT INTO public.ammar_conversation_participants(conversation_id, user_id, participant_role)
    VALUES
      (v_conversation, v_user, 'customer'),
      (v_conversation, p_other_user, 'provider')
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN v_conversation;
END;
$$;

CREATE OR REPLACE FUNCTION public.ammar_mark_conversation_read(p_conversation_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.ammar_is_conversation_member(p_conversation_id) THEN
    RAISE EXCEPTION 'Conversation access denied';
  END IF;
  UPDATE public.ammar_conversation_participants
  SET last_read_at = now()
  WHERE conversation_id = p_conversation_id AND user_id = auth.uid();
END;
$$;

CREATE OR REPLACE FUNCTION public.ammar_accept_agreement(p_agreement_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  a public.ammar_agreements%ROWTYPE;
BEGIN
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
$$;

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
SET search_path = public, pg_temp
AS $$
DECLARE
  v_project_id_type text;
  v_request_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero';
  END IF;

  SELECT format_type(a.atttypid, a.atttypmod)
    INTO v_project_id_type
  FROM pg_attribute a
  WHERE a.attrelid = 'public.projects'::regclass
    AND a.attname = 'id' AND NOT a.attisdropped;
  IF v_project_id_type IS NULL THEN
    RAISE EXCEPTION 'Project identifier type could not be determined';
  END IF;

  IF nullif(trim(coalesce(p_project_id,'')),'') IS NOT NULL
     AND public.ammar_project_role(p_project_id) IS NULL THEN
    RAISE EXCEPTION 'You are not a member of the selected project';
  END IF;

  EXECUTE format($query$
    INSERT INTO public.ammar_market_requests(
      buyer_id, supplier_id, project_id, currency, buyer_note
    )
    SELECT $1, $2,
           CASE WHEN nullif($3,'') IS NULL THEN NULL::%1$s ELSE $3::%1$s END,
           p.currency, $4
    FROM public.ammar_market_products p
    JOIN public.ammar_market_suppliers s ON s.id = p.supplier_id
    WHERE p.id = $5
      AND p.supplier_id = $2
      AND p.is_active = true
      AND p.availability IN ('available','limited')
      AND (p.quantity_available IS NULL OR p.quantity_available >= $6)
      AND s.status = 'active'
      AND s.owner_id <> $1
    RETURNING id
  $query$, v_project_id_type)
  INTO v_request_id
  USING auth.uid(), p_supplier_id, p_project_id, p_buyer_note, p_product_id, p_quantity;

  IF v_request_id IS NULL THEN
    RAISE EXCEPTION 'The selected product is unavailable or the supplier is inactive';
  END IF;

  INSERT INTO public.ammar_market_request_items(
    request_id, product_id, product_title, unit, quantity, requested_unit_price
  )
  SELECT v_request_id, p.id, p.title, p.unit, p_quantity, p.price
  FROM public.ammar_market_products p
  WHERE p.id = p_product_id;

  INSERT INTO public.ammar_transaction_events(
    request_id, actor_id, event_type, summary, payload
  )
  VALUES (
    v_request_id, auth.uid(), 'request_created', 'تم إنشاء طلب شراء من سوق عَمِّر.',
    jsonb_build_object('product_id', p_product_id, 'quantity', p_quantity)
  );

  RETURN v_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.ammar_accept_market_quote(p_quote_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  q public.ammar_market_quotes%ROWTYPE;
  r public.ammar_market_requests%ROWTYPE;
BEGIN
  SELECT * INTO q FROM public.ammar_market_quotes WHERE id = p_quote_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Quote not found'; END IF;
  SELECT * INTO r FROM public.ammar_market_requests WHERE id = q.request_id FOR UPDATE;
  IF NOT FOUND OR r.buyer_id <> auth.uid() THEN
    RAISE EXCEPTION 'Only the buyer can accept this quote';
  END IF;
  IF r.status NOT IN ('submitted','quoted') OR q.status <> 'proposed' THEN
    RAISE EXCEPTION 'This quote can no longer be accepted';
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
$$;

CREATE OR REPLACE FUNCTION public.ammar_advance_market_request(
  p_request_id uuid,
  p_next_status text,
  p_note text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  r public.ammar_market_requests%ROWTYPE;
  v_supplier_owner uuid;
  v_is_buyer boolean;
  v_is_supplier boolean;
  v_rate numeric(5,2);
  v_payer_side text;
  v_payer uuid;
  v_amount numeric(14,2);
  v_currency text;
  v_project_expense_id uuid;
BEGIN
  SELECT * INTO r FROM public.ammar_market_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Request not found'; END IF;

  SELECT owner_id INTO v_supplier_owner
  FROM public.ammar_market_suppliers WHERE id = r.supplier_id;
  v_is_buyer := r.buyer_id = auth.uid();
  v_is_supplier := v_supplier_owner = auth.uid();
  IF NOT (v_is_buyer OR v_is_supplier) THEN
    RAISE EXCEPTION 'Request access denied';
  END IF;

  IF p_next_status = 'cancelled' THEN
    IF r.status IN ('completed','cancelled') THEN
      RAISE EXCEPTION 'This request cannot be cancelled';
    END IF;
  ELSIF p_next_status = 'disputed' THEN
    IF r.status IN ('completed','cancelled','disputed')
       OR char_length(coalesce(trim(p_note),'')) < 10 THEN
      RAISE EXCEPTION 'A dispute requires an active request and a reason of at least 10 characters';
    END IF;
    INSERT INTO public.ammar_disputes(request_id, raised_by, reason)
    VALUES (r.id, auth.uid(), trim(p_note));
  ELSIF p_next_status = 'fulfilling' THEN
    IF NOT v_is_supplier OR r.status <> 'accepted' THEN
      RAISE EXCEPTION 'Only the supplier can start fulfilment after acceptance';
    END IF;
  ELSIF p_next_status = 'delivered' THEN
    IF NOT v_is_supplier OR r.status <> 'fulfilling' THEN
      RAISE EXCEPTION 'Only the supplier can mark an accepted order as delivered';
    END IF;
  ELSIF p_next_status = 'completed' THEN
    IF NOT v_is_buyer OR r.status <> 'delivered' OR r.agreed_total IS NULL THEN
      RAISE EXCEPTION 'Only the buyer can complete a delivered order with an agreed total';
    END IF;
  ELSE
    RAISE EXCEPTION 'Unsupported status transition';
  END IF;

  UPDATE public.ammar_market_requests
  SET status = p_next_status,
      completed_at = CASE WHEN p_next_status = 'completed' THEN now() ELSE completed_at END
  WHERE id = r.id;

  INSERT INTO public.ammar_transaction_events(request_id, actor_id, event_type, summary, payload)
  VALUES (r.id, auth.uid(), 'status_' || p_next_status,
          coalesce(nullif(trim(p_note),''), 'تم تحديث حالة الطلب إلى ' || p_next_status || '.'),
          jsonb_build_object('from', r.status, 'to', p_next_status));

  IF p_next_status = 'completed' AND r.project_id IS NOT NULL AND r.project_expense_id IS NULL THEN
    INSERT INTO public.project_expenses(
      project_id, description, amount, currency, spent_on, notes
    )
    VALUES (
      r.project_id,
      left('شراء مواد بناء من عَمِّر - طلب ' || left(r.id::text, 8), 240),
      r.agreed_total,
      r.currency,
      CURRENT_DATE,
      'AMMAR market request: ' || r.id::text || '. Automatically recorded after buyer confirmed receipt.'
    )
    RETURNING id INTO v_project_expense_id;

    UPDATE public.ammar_market_requests
    SET project_expense_id = v_project_expense_id
    WHERE id = r.id;
  END IF;

  IF p_next_status = 'completed' THEN
    SELECT rate_percent, payer_side INTO v_rate, v_payer_side
    FROM public.ammar_commission_rules
    WHERE activity_type = 'market_materials' AND is_active = true
    LIMIT 1;
    IF v_rate IS NOT NULL THEN
      v_amount := r.agreed_total;
      v_currency := r.currency;
      v_payer := CASE WHEN v_payer_side = 'customer'
                      THEN r.buyer_id ELSE v_supplier_owner END;
      INSERT INTO public.ammar_commission_ledger(
        request_id, activity_type, source_type, source_id,
        gross_amount, currency, rate_percent, commission_amount, payer_id, status
      )
      VALUES (
        r.id, 'market_materials', 'market_request', r.id::text,
        v_amount, v_currency, v_rate,
        round(v_amount * v_rate / 100, 2), v_payer, 'due'
      )
      ON CONFLICT (source_type, source_id) DO NOTHING;
    END IF;
  END IF;

  RETURN p_next_status;
END;
$$;

CREATE OR REPLACE FUNCTION public.ammar_accept_service_offer(p_offer_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  o public.ammar_service_offers%ROWTYPE;
  r public.ammar_service_requests%ROWTYPE;
BEGIN
  SELECT * INTO o FROM public.ammar_service_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Offer not found'; END IF;
  SELECT * INTO r FROM public.ammar_service_requests WHERE id = o.request_id FOR UPDATE;
  IF NOT FOUND OR r.requester_id <> auth.uid() OR r.status <> 'open' OR o.status <> 'proposed' THEN
    RAISE EXCEPTION 'Only the requester can accept an offer for an open request';
  END IF;

  UPDATE public.ammar_service_offers
  SET status = CASE WHEN id = o.id THEN 'accepted' ELSE 'rejected' END
  WHERE request_id = r.id AND status = 'proposed';
  UPDATE public.ammar_service_requests SET status = 'awarded' WHERE id = r.id;

  RETURN r.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.ammar_complete_service_request(p_request_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $ammar_service_complete$
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
$ammar_service_complete$;

CREATE OR REPLACE FUNCTION public.ammar_validate_agreement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.created_by <> auth.uid() OR auth.uid() NOT IN (NEW.client_id, NEW.provider_id) THEN
    RAISE EXCEPTION 'Only a contract party can create this agreement';
  END IF;

  IF NEW.source_type = 'project' THEN
    IF NEW.project_id IS NULL OR public.ammar_project_role(NEW.project_id::text) IS NULL THEN
      RAISE EXCEPTION 'Agreement must reference a project accessible to its creator';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.projects p
      WHERE p.id = NEW.project_id
        AND p.client_id = NEW.client_id
        AND EXISTS (
          SELECT 1 FROM public.project_members pm
          WHERE pm.project_id = p.id AND pm.user_id = NEW.provider_id
        )
    ) THEN
      RAISE EXCEPTION 'The client and provider must match the referenced project and membership';
    END IF;
  ELSIF NEW.source_type = 'market_request' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.ammar_market_requests r
      JOIN public.ammar_market_suppliers s ON s.id = r.supplier_id
      WHERE r.id::text = NEW.source_id
        AND r.buyer_id = NEW.client_id
        AND s.owner_id = NEW.provider_id
        AND r.status = 'accepted'
    ) THEN
      RAISE EXCEPTION 'Agreement parties must match an accepted market request';
    END IF;
  ELSIF NEW.source_type = 'service_offer' THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.ammar_service_offers o
      JOIN public.ammar_service_requests r ON r.id = o.request_id
      JOIN public.ammar_service_providers sp ON sp.id = o.provider_id
      WHERE o.id::text = NEW.source_id
        AND r.requester_id = NEW.client_id
        AND sp.owner_id = NEW.provider_id
        AND o.status = 'accepted'
    ) THEN
      RAISE EXCEPTION 'Agreement parties must match an accepted service offer';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammar_validate_agreement_trigger ON public.ammar_agreements;
CREATE TRIGGER ammar_validate_agreement_trigger
BEFORE INSERT ON public.ammar_agreements
FOR EACH ROW EXECUTE FUNCTION public.ammar_validate_agreement();

CREATE OR REPLACE FUNCTION public.ammar_record_agreement_creation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.ammar_agreement_events(agreement_id, actor_id, event_type, note)
  VALUES (NEW.id, NEW.created_by, 'created', 'تم إنشاء مسودة الاتفاق وإرسالها للطرف الآخر.');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammar_agreement_created_trigger ON public.ammar_agreements;
CREATE TRIGGER ammar_agreement_created_trigger
AFTER INSERT ON public.ammar_agreements
FOR EACH ROW EXECUTE FUNCTION public.ammar_record_agreement_creation();

CREATE OR REPLACE FUNCTION public.ammar_market_quote_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.ammar_market_requests
  SET status = 'quoted'
  WHERE id = NEW.request_id AND status = 'submitted';

  INSERT INTO public.ammar_transaction_events(request_id, actor_id, event_type, summary, payload)
  VALUES (
    NEW.request_id, NEW.created_by, 'quote_submitted',
    'تم استلام عرض سعر من المورد.',
    jsonb_build_object('quote_id', NEW.id, 'amount', NEW.total_amount, 'currency', NEW.currency)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammar_market_quote_created_trigger ON public.ammar_market_quotes;
CREATE TRIGGER ammar_market_quote_created_trigger
AFTER INSERT ON public.ammar_market_quotes
FOR EACH ROW EXECUTE FUNCTION public.ammar_market_quote_created();

CREATE OR REPLACE FUNCTION public.ammar_notify_new_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_subject text;
BEGIN
  UPDATE public.ammar_conversations
  SET last_message_at = NEW.created_at
  WHERE id = NEW.conversation_id;

  SELECT subject INTO v_subject
  FROM public.ammar_conversations WHERE id = NEW.conversation_id;

  INSERT INTO public.ammar_user_notifications(
    user_id, actor_id, notification_type, title, body, conversation_id, message_id
  )
  SELECT cp.user_id, NEW.sender_id, 'new_message',
         coalesce(v_subject, 'رسالة جديدة في عَمِّر'),
         left(coalesce(NEW.body, NEW.file_name, 'مرفق جديد'), 240),
         NEW.conversation_id, NEW.id
  FROM public.ammar_conversation_participants cp
  WHERE cp.conversation_id = NEW.conversation_id
    AND cp.user_id <> NEW.sender_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ammar_notify_new_message_trigger ON public.ammar_messages;
CREATE TRIGGER ammar_notify_new_message_trigger
AFTER INSERT ON public.ammar_messages
FOR EACH ROW EXECUTE FUNCTION public.ammar_notify_new_message();

ALTER TABLE public.ammar_market_suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_market_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_service_providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_market_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_market_request_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_market_quotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_service_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_service_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_user_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_agreements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_agreement_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_commission_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_commission_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ammar_transaction_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY ammar_suppliers_select ON public.ammar_market_suppliers
FOR SELECT TO authenticated USING (status = 'active' OR owner_id = auth.uid());
CREATE POLICY ammar_suppliers_insert ON public.ammar_market_suppliers
FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid());
CREATE POLICY ammar_suppliers_update ON public.ammar_market_suppliers
FOR UPDATE TO authenticated USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());

CREATE POLICY ammar_products_select ON public.ammar_market_products
FOR SELECT TO authenticated USING (
  (is_active = true AND EXISTS (
    SELECT 1 FROM public.ammar_market_suppliers s
    WHERE s.id = supplier_id AND s.status = 'active'
  ))
  OR EXISTS (
    SELECT 1 FROM public.ammar_market_suppliers s
    WHERE s.id = supplier_id AND s.owner_id = auth.uid()
  )
);
CREATE POLICY ammar_products_insert ON public.ammar_market_products
FOR INSERT TO authenticated WITH CHECK (
  EXISTS (SELECT 1 FROM public.ammar_market_suppliers s
          WHERE s.id = supplier_id AND s.owner_id = auth.uid())
);
CREATE POLICY ammar_products_update ON public.ammar_market_products
FOR UPDATE TO authenticated USING (
  EXISTS (SELECT 1 FROM public.ammar_market_suppliers s
          WHERE s.id = supplier_id AND s.owner_id = auth.uid())
) WITH CHECK (
  EXISTS (SELECT 1 FROM public.ammar_market_suppliers s
          WHERE s.id = supplier_id AND s.owner_id = auth.uid())
);
CREATE POLICY ammar_products_delete ON public.ammar_market_products
FOR DELETE TO authenticated USING (
  EXISTS (SELECT 1 FROM public.ammar_market_suppliers s
          WHERE s.id = supplier_id AND s.owner_id = auth.uid())
);

CREATE POLICY ammar_service_providers_select ON public.ammar_service_providers
FOR SELECT TO authenticated USING (status = 'active' OR owner_id = auth.uid());
CREATE POLICY ammar_service_providers_insert ON public.ammar_service_providers
FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid());
CREATE POLICY ammar_service_providers_update ON public.ammar_service_providers
FOR UPDATE TO authenticated USING (owner_id = auth.uid()) WITH CHECK (owner_id = auth.uid());

CREATE POLICY ammar_market_requests_select ON public.ammar_market_requests
FOR SELECT TO authenticated USING (
  buyer_id = auth.uid()
  OR EXISTS (SELECT 1 FROM public.ammar_market_suppliers s
             WHERE s.id = supplier_id AND s.owner_id = auth.uid())
);
CREATE POLICY ammar_market_requests_insert ON public.ammar_market_requests
FOR INSERT TO authenticated WITH CHECK (
  buyer_id = auth.uid()
  AND EXISTS (SELECT 1 FROM public.ammar_market_suppliers s
              WHERE s.id = supplier_id AND s.status = 'active')
  AND (project_id IS NULL OR public.ammar_project_role(project_id::text) IS NOT NULL)
);
CREATE POLICY ammar_market_items_select ON public.ammar_market_request_items
FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM public.ammar_market_requests r
    LEFT JOIN public.ammar_market_suppliers s ON s.id = r.supplier_id
    WHERE r.id = request_id AND (r.buyer_id = auth.uid() OR s.owner_id = auth.uid())
  )
);
CREATE POLICY ammar_market_items_insert ON public.ammar_market_request_items
FOR INSERT TO authenticated WITH CHECK (
  EXISTS (SELECT 1 FROM public.ammar_market_requests r
          WHERE r.id = request_id AND r.buyer_id = auth.uid())
  AND (product_id IS NULL OR EXISTS (
    SELECT 1 FROM public.ammar_market_products p
    JOIN public.ammar_market_requests r ON r.id = request_id
    WHERE p.id = product_id AND p.supplier_id = r.supplier_id
  ))
);

CREATE POLICY ammar_market_quotes_select ON public.ammar_market_quotes
FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM public.ammar_market_requests r
    JOIN public.ammar_market_suppliers s ON s.id = r.supplier_id
    WHERE r.id = request_id
      AND (r.buyer_id = auth.uid() OR s.owner_id = auth.uid())
  )
);
CREATE POLICY ammar_market_quotes_insert ON public.ammar_market_quotes
FOR INSERT TO authenticated WITH CHECK (
  created_by = auth.uid()
  AND status = 'proposed'
  AND EXISTS (
    SELECT 1 FROM public.ammar_market_requests r
    JOIN public.ammar_market_suppliers s ON s.id = r.supplier_id
    WHERE r.id = request_id
      AND r.supplier_id = ammar_market_quotes.supplier_id
      AND s.owner_id = auth.uid()
      AND r.status IN ('submitted','quoted')
  )
);
CREATE POLICY ammar_service_requests_select ON public.ammar_service_requests
FOR SELECT TO authenticated USING (
  requester_id = auth.uid()
  OR (
    status = 'open'
    AND EXISTS (SELECT 1 FROM public.ammar_service_providers sp
                WHERE sp.owner_id = auth.uid() AND sp.status = 'active')
  )
);
CREATE POLICY ammar_service_requests_insert ON public.ammar_service_requests
FOR INSERT TO authenticated WITH CHECK (
  requester_id = auth.uid()
  AND (project_id IS NULL OR public.ammar_project_role(project_id::text) IS NOT NULL)
);
CREATE POLICY ammar_service_offers_select ON public.ammar_service_offers
FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.ammar_service_requests r
          WHERE r.id = request_id AND r.requester_id = auth.uid())
  OR EXISTS (SELECT 1 FROM public.ammar_service_providers sp
             WHERE sp.id = provider_id AND sp.owner_id = auth.uid())
);
CREATE POLICY ammar_service_offers_insert ON public.ammar_service_offers
FOR INSERT TO authenticated WITH CHECK (
  created_by = auth.uid()
  AND EXISTS (SELECT 1 FROM public.ammar_service_providers sp
              WHERE sp.id = provider_id AND sp.owner_id = auth.uid() AND sp.status = 'active')
  AND EXISTS (SELECT 1 FROM public.ammar_service_requests r
              WHERE r.id = request_id AND r.status = 'open')
);
CREATE POLICY ammar_conversations_select ON public.ammar_conversations
FOR SELECT TO authenticated USING (public.ammar_is_conversation_member(id));
CREATE POLICY ammar_participants_select ON public.ammar_conversation_participants
FOR SELECT TO authenticated USING (public.ammar_is_conversation_member(conversation_id));
CREATE POLICY ammar_participants_update_self ON public.ammar_conversation_participants
FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY ammar_messages_select ON public.ammar_messages
FOR SELECT TO authenticated USING (public.ammar_is_conversation_member(conversation_id));
CREATE POLICY ammar_messages_insert ON public.ammar_messages
FOR INSERT TO authenticated WITH CHECK (
  sender_id = auth.uid()
  AND message_type IN ('text','image','file')
  AND public.ammar_is_conversation_member(conversation_id)
  AND (file_path IS NULL OR file_path LIKE conversation_id::text || '/' || auth.uid()::text || '/%')
);

CREATE POLICY ammar_notifications_select ON public.ammar_user_notifications
FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY ammar_notifications_update_self ON public.ammar_user_notifications
FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY ammar_agreements_select ON public.ammar_agreements
FOR SELECT TO authenticated USING (auth.uid() IN (client_id, provider_id));
CREATE POLICY ammar_agreements_insert ON public.ammar_agreements
FOR INSERT TO authenticated WITH CHECK (
  created_by = auth.uid()
  AND auth.uid() IN (client_id, provider_id)
  AND (project_id IS NULL OR public.ammar_project_role(project_id::text) IS NOT NULL)
);
CREATE POLICY ammar_agreement_events_select ON public.ammar_agreement_events
FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.ammar_agreements a
          WHERE a.id = agreement_id AND auth.uid() IN (a.client_id, a.provider_id))
);

CREATE POLICY ammar_reviews_select ON public.ammar_reviews
FOR SELECT TO authenticated USING (true);
CREATE POLICY ammar_reviews_insert ON public.ammar_reviews
FOR INSERT TO authenticated WITH CHECK (
  reviewer_id = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.ammar_market_requests r
    JOIN public.ammar_market_suppliers s ON s.id = r.supplier_id
    WHERE r.id = request_id AND r.status = 'completed'
      AND (
        (r.buyer_id = auth.uid() AND s.owner_id = reviewed_user_id)
        OR
        (s.owner_id = auth.uid() AND r.buyer_id = reviewed_user_id)
      )
  )
);

CREATE POLICY ammar_disputes_select ON public.ammar_disputes
FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM public.ammar_market_requests r
    JOIN public.ammar_market_suppliers s ON s.id = r.supplier_id
    WHERE r.id = request_id AND (r.buyer_id = auth.uid() OR s.owner_id = auth.uid())
  )
);
CREATE POLICY ammar_disputes_insert ON public.ammar_disputes
FOR INSERT TO authenticated WITH CHECK (
  raised_by = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.ammar_market_requests r
    JOIN public.ammar_market_suppliers s ON s.id = r.supplier_id
    WHERE r.id = request_id AND r.status NOT IN ('cancelled')
      AND (r.buyer_id = auth.uid() OR s.owner_id = auth.uid())
  )
);

CREATE POLICY ammar_commission_rules_select ON public.ammar_commission_rules
FOR SELECT TO authenticated USING (is_active = true);
CREATE POLICY ammar_commission_ledger_select ON public.ammar_commission_ledger
FOR SELECT TO authenticated USING (payer_id = auth.uid());
CREATE POLICY ammar_transaction_events_select ON public.ammar_transaction_events
FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.ammar_market_requests r
          JOIN public.ammar_market_suppliers s ON s.id = r.supplier_id
          WHERE r.id = request_id AND (r.buyer_id = auth.uid() OR s.owner_id = auth.uid()))
);
CREATE POLICY ammar_transaction_events_insert ON public.ammar_transaction_events
FOR INSERT TO authenticated WITH CHECK (
  actor_id = auth.uid()
  AND EXISTS (SELECT 1 FROM public.ammar_market_requests r
              JOIN public.ammar_market_suppliers s ON s.id = r.supplier_id
              WHERE r.id = request_id AND (r.buyer_id = auth.uid() OR s.owner_id = auth.uid()))
);

GRANT SELECT ON
  public.ammar_market_suppliers,
  public.ammar_market_products,
  public.ammar_service_providers,
  public.ammar_market_requests,
  public.ammar_market_request_items,
  public.ammar_market_quotes,
  public.ammar_service_requests,
  public.ammar_service_offers,
  public.ammar_agreements,
  public.ammar_reviews,
  public.ammar_disputes,
  public.ammar_transaction_events
TO authenticated;

-- Column-level writes keep provider verification and workflow state server-controlled.
GRANT INSERT (owner_id,business_name,contact_name,contact_phone,whatsapp_phone,
  governorate,city,area,market_name,address,description,logo_path)
ON public.ammar_market_suppliers TO authenticated;
GRANT UPDATE (business_name,contact_name,contact_phone,whatsapp_phone,
  governorate,city,area,market_name,address,description,logo_path)
ON public.ammar_market_suppliers TO authenticated;

GRANT INSERT (supplier_id,title,category,brand,description,unit,price,currency,
  quantity_available,availability,image_path,is_active)
ON public.ammar_market_products TO authenticated;
GRANT UPDATE (title,category,brand,description,unit,price,currency,
  quantity_available,availability,image_path,is_active)
ON public.ammar_market_products TO authenticated;

GRANT INSERT (owner_id,business_name,provider_type,contact_name,contact_phone,
  governorate,city,area,address,description,portfolio_url)
ON public.ammar_service_providers TO authenticated;
GRANT UPDATE (business_name,provider_type,contact_name,contact_phone,
  governorate,city,area,address,description,portfolio_url)
ON public.ammar_service_providers TO authenticated;

GRANT INSERT (request_id,supplier_id,created_by,total_amount,currency,
  delivery_days,valid_until,notes)
ON public.ammar_market_quotes TO authenticated;

GRANT INSERT (requester_id,project_id,service_type,title,description,
  governorate,city,area,budget_min,budget_max,currency,target_start_date)
ON public.ammar_service_requests TO authenticated;
GRANT INSERT (request_id,provider_id,created_by,amount,currency,
  duration_days,inclusions,exclusions,warranty_months)
ON public.ammar_service_offers TO authenticated;

GRANT INSERT (project_id,source_type,source_id,client_id,provider_id,
  title,scope,amount,currency,schedule_text,terms,created_by)
ON public.ammar_agreements TO authenticated;
GRANT INSERT (request_id,reviewer_id,reviewed_user_id,rating,review_text)
ON public.ammar_reviews TO authenticated;
GRANT INSERT (request_id,raised_by,reason,evidence_note)
ON public.ammar_disputes TO authenticated;
GRANT SELECT ON public.ammar_conversations, public.ammar_conversation_participants,
  public.ammar_messages, public.ammar_user_notifications,
  public.ammar_agreement_events, public.ammar_commission_rules,
  public.ammar_commission_ledger TO authenticated;
GRANT INSERT ON public.ammar_messages TO authenticated;
GRANT UPDATE (last_read_at) ON public.ammar_conversation_participants TO authenticated;
GRANT UPDATE (read_at) ON public.ammar_user_notifications TO authenticated;

REVOKE ALL ON public.ammar_commission_ledger, public.ammar_commission_rules FROM anon, authenticated;
GRANT SELECT ON public.ammar_commission_rules TO authenticated;
GRANT SELECT ON public.ammar_commission_ledger TO authenticated;

REVOKE ALL ON FUNCTION public.ammar_market_product_price_stamp() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_market_quote_created() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_create_market_request(uuid,uuid,numeric,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_is_conversation_member(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_start_conversation(uuid,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_mark_conversation_read(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_accept_agreement(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_accept_market_quote(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_advance_market_request(uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_accept_service_offer(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_complete_service_request(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_validate_agreement() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_record_agreement_creation() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_ecosystem_touch_updated_at() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_notify_new_message() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.ammar_create_market_request(uuid,uuid,numeric,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_is_conversation_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_start_conversation(uuid,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_mark_conversation_read(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_accept_agreement(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_accept_market_quote(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_advance_market_request(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_accept_service_offer(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ammar_complete_service_request(uuid) TO authenticated;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'ammar-chat-files',
  'ammar-chat-files',
  false,
  26214400,
  ARRAY[
    'image/jpeg','image/png','image/webp','application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ]
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS ammar_chat_files_member_select ON storage.objects;
CREATE POLICY ammar_chat_files_member_select ON storage.objects
FOR SELECT TO authenticated USING (
  bucket_id = 'ammar-chat-files'
  AND public.ammar_is_conversation_member((storage.foldername(name))[1]::uuid)
);
DROP POLICY IF EXISTS ammar_chat_files_member_insert ON storage.objects;
CREATE POLICY ammar_chat_files_member_insert ON storage.objects
FOR INSERT TO authenticated WITH CHECK (
  bucket_id = 'ammar-chat-files'
  AND (storage.foldername(name))[2] = auth.uid()::text
  AND public.ammar_is_conversation_member((storage.foldername(name))[1]::uuid)
);
DROP POLICY IF EXISTS ammar_chat_files_member_delete ON storage.objects;
CREATE POLICY ammar_chat_files_member_delete ON storage.objects
FOR DELETE TO authenticated USING (
  bucket_id = 'ammar-chat-files'
  AND (storage.foldername(name))[2] = auth.uid()::text
  AND public.ammar_is_conversation_member((storage.foldername(name))[1]::uuid)
);

-- Public read-only product imagery; upload and replacement remain supplier-owned.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'ammar-market-files', 'ammar-market-files', true, 5242880,
  ARRAY['image/jpeg','image/png','image/webp']
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS ammar_market_images_public_read ON storage.objects;
CREATE POLICY ammar_market_images_public_read ON storage.objects
FOR SELECT TO public USING (bucket_id = 'ammar-market-files');

DROP POLICY IF EXISTS ammar_market_images_supplier_insert ON storage.objects;
CREATE POLICY ammar_market_images_supplier_insert ON storage.objects
FOR INSERT TO authenticated WITH CHECK (
  bucket_id = 'ammar-market-files'
  AND (storage.foldername(name))[2] = auth.uid()::text
  AND EXISTS (
    SELECT 1 FROM public.ammar_market_suppliers s
    WHERE s.id::text = (storage.foldername(name))[1]
      AND s.owner_id = auth.uid()
  )
);

DROP POLICY IF EXISTS ammar_market_images_supplier_update ON storage.objects;
CREATE POLICY ammar_market_images_supplier_update ON storage.objects
FOR UPDATE TO authenticated USING (
  bucket_id = 'ammar-market-files'
  AND (storage.foldername(name))[2] = auth.uid()::text
  AND EXISTS (
    SELECT 1 FROM public.ammar_market_suppliers s
    WHERE s.id::text = (storage.foldername(name))[1]
      AND s.owner_id = auth.uid()
  )
) WITH CHECK (
  bucket_id = 'ammar-market-files'
  AND (storage.foldername(name))[2] = auth.uid()::text
  AND EXISTS (
    SELECT 1 FROM public.ammar_market_suppliers s
    WHERE s.id::text = (storage.foldername(name))[1]
      AND s.owner_id = auth.uid()
  )
);

DROP POLICY IF EXISTS ammar_market_images_supplier_delete ON storage.objects;
CREATE POLICY ammar_market_images_supplier_delete ON storage.objects
FOR DELETE TO authenticated USING (
  bucket_id = 'ammar-market-files'
  AND (storage.foldername(name))[2] = auth.uid()::text
  AND EXISTS (
    SELECT 1 FROM public.ammar_market_suppliers s
    WHERE s.id::text = (storage.foldername(name))[1]
      AND s.owner_id = auth.uid()
  )
);

-- Add only if Supabase Realtime publication exists and these tables are not present.
DO $ammar_realtime$
DECLARE t text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    FOREACH t IN ARRAY ARRAY[
      'ammar_conversations','ammar_messages','ammar_user_notifications'
    ]
    LOOP
      IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = t
      ) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
      END IF;
    END LOOP;
  END IF;
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'Realtime publication update skipped; enable these tables manually if required.';
  WHEN undefined_object THEN
    RAISE NOTICE 'Supabase Realtime publication is not available in this project.';
END
$ammar_realtime$;

COMMIT;
