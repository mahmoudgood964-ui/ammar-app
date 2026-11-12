-- AMMIR trust and moderation hardening
-- Prevent self-verification of supplier and service-provider profiles
-- Add narrowly scoped admin review access for trust and safety workflows
-- This migration deliberately does not touch payment milestone/event tables

BEGIN;

CREATE OR REPLACE FUNCTION public.ammir_guard_provider_trust_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_is_admin boolean := false;
BEGIN
  -- Backend/service operations without an end-user JWT remain able to perform
  -- controlled imports and verification after their own authorization checks
  IF v_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_is_admin := public.is_admin();

  IF v_is_admin THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.owner_id := v_user_id;
    NEW.is_verified := false;
    NEW.verified_at := NULL;

    -- A registrant may start active or paused, but cannot self-suspend
    IF NEW.status = 'suspended' THEN
      NEW.status := 'active';
    END IF;

    RETURN NEW;
  END IF;

  -- The owner may edit business information, but trust decisions belong
  -- exclusively to an administrator or a controlled backend operation
  NEW.is_verified := OLD.is_verified;
  NEW.verified_at := OLD.verified_at;

  -- Owners may pause/resume their own listing, not suspend it
  IF NEW.status = 'suspended' OR OLD.status = 'suspended' THEN
    NEW.status := OLD.status;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.ammir_guard_provider_trust_fields() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammir_guard_provider_trust_fields() FROM anon;
REVOKE ALL ON FUNCTION public.ammir_guard_provider_trust_fields() FROM authenticated;

DROP TRIGGER IF EXISTS ammir_guard_supplier_trust_fields ON public.ammar_market_suppliers;
CREATE TRIGGER ammir_guard_supplier_trust_fields
BEFORE INSERT OR UPDATE ON public.ammar_market_suppliers
FOR EACH ROW EXECUTE FUNCTION public.ammir_guard_provider_trust_fields();

DROP TRIGGER IF EXISTS ammir_guard_service_provider_trust_fields ON public.ammar_service_providers;
CREATE TRIGGER ammir_guard_service_provider_trust_fields
BEFORE INSERT OR UPDATE ON public.ammar_service_providers
FOR EACH ROW EXECUTE FUNCTION public.ammir_guard_provider_trust_fields();

-- Give administrators access to review and verify suppliers/providers
DROP POLICY IF EXISTS ammir_admin_suppliers_select ON public.ammar_market_suppliers;
CREATE POLICY ammir_admin_suppliers_select
ON public.ammar_market_suppliers
FOR SELECT TO authenticated
USING (public.is_admin());

DROP POLICY IF EXISTS ammir_admin_suppliers_update ON public.ammar_market_suppliers;
CREATE POLICY ammir_admin_suppliers_update
ON public.ammar_market_suppliers
FOR UPDATE TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS ammir_admin_service_providers_select ON public.ammar_service_providers;
CREATE POLICY ammir_admin_service_providers_select
ON public.ammar_service_providers
FOR SELECT TO authenticated
USING (public.is_admin());

DROP POLICY IF EXISTS ammir_admin_service_providers_update ON public.ammar_service_providers;
CREATE POLICY ammir_admin_service_providers_update
ON public.ammar_service_providers
FOR UPDATE TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Reports can be viewed and processed by administrators, while reporters
-- retain their existing ability to see the reports they submitted
DROP POLICY IF EXISTS ammir_admin_message_reports_select ON public.ammar_message_reports;
CREATE POLICY ammir_admin_message_reports_select
ON public.ammar_message_reports
FOR SELECT TO authenticated
USING (public.is_admin());

DROP POLICY IF EXISTS ammir_admin_message_reports_update ON public.ammar_message_reports;
CREATE POLICY ammir_admin_message_reports_update
ON public.ammar_message_reports
FOR UPDATE TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Disputes stay visible to transaction parties; administrators can investigate
-- and record a resolution without receiving or moving customer funds
DROP POLICY IF EXISTS ammir_admin_disputes_select ON public.ammar_disputes;
CREATE POLICY ammir_admin_disputes_select
ON public.ammar_disputes
FOR SELECT TO authenticated
USING (public.is_admin());

DROP POLICY IF EXISTS ammir_admin_disputes_update ON public.ammar_disputes;
CREATE POLICY ammir_admin_disputes_update
ON public.ammar_disputes
FOR UPDATE TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Operational visibility is restricted to administrators
DROP POLICY IF EXISTS ammir_admin_transaction_events_select ON public.ammar_transaction_events;
CREATE POLICY ammir_admin_transaction_events_select
ON public.ammar_transaction_events
FOR SELECT TO authenticated
USING (public.is_admin());

DROP POLICY IF EXISTS ammir_admin_commission_ledger_select ON public.ammar_commission_ledger;
CREATE POLICY ammir_admin_commission_ledger_select
ON public.ammar_commission_ledger
FOR SELECT TO authenticated
USING (public.is_admin());

DROP POLICY IF EXISTS ammir_admin_commission_rules_update ON public.ammar_commission_rules;
CREATE POLICY ammir_admin_commission_rules_update
ON public.ammar_commission_rules
FOR UPDATE TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());

-- Message content is not made globally readable to administrators. This RPC
-- exposes only the message attached to a report, and only after an admin check.
CREATE OR REPLACE FUNCTION public.ammar_admin_list_message_reports(p_limit integer DEFAULT 50)
RETURNS TABLE (
  report_id uuid,
  conversation_id uuid,
  message_id uuid,
  reporter_id uuid,
  reason text,
  report_status text,
  report_created_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid,
  message_type text,
  message_body text,
  file_name text,
  sender_id uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'administrator access required'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.conversation_id,
    r.message_id,
    r.reporter_id,
    r.reason,
    r.status,
    r.created_at,
    r.reviewed_at,
    r.reviewed_by,
    m.message_type,
    m.body,
    m.file_name,
    m.sender_id
  FROM public.ammar_message_reports AS r
  JOIN public.ammar_messages AS m
    ON m.id = r.message_id
   AND m.conversation_id = r.conversation_id
  ORDER BY
    CASE WHEN r.status = 'pending' THEN 0
         WHEN r.status = 'investigating' THEN 1
         ELSE 2 END,
    r.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
END;
$function$;

REVOKE ALL ON FUNCTION public.ammar_admin_list_message_reports(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ammar_admin_list_message_reports(integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.ammar_admin_list_message_reports(integer) TO authenticated;

COMMENT ON FUNCTION public.ammar_admin_list_message_reports(integer)
IS 'Returns only reported message context to verified AMMIR administrators; it does not grant general conversation access';

COMMIT;
