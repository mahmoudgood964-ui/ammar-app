-- AMMIR: combine equivalent user/admin RLS policies without changing access.
-- PostgreSQL ORs permissive policies for the same role/action; these combined
-- predicates preserve that exact visibility/update rule while avoiding duplicate
-- policy evaluation on each row.

BEGIN;

-- Commission ledger: payer visibility OR administrator visibility.
DROP POLICY IF EXISTS ammir_admin_commission_ledger_select
  ON public.ammar_commission_ledger;
DROP POLICY IF EXISTS ammar_commission_ledger_select
  ON public.ammar_commission_ledger;
CREATE POLICY ammar_commission_ledger_select
  ON public.ammar_commission_ledger
  FOR SELECT TO authenticated
  USING (
    payer_id = (SELECT auth.uid())
    OR (SELECT public.is_admin())
  );

-- Disputes: transaction parties OR administrators.
DROP POLICY IF EXISTS ammir_admin_disputes_select
  ON public.ammar_disputes;
DROP POLICY IF EXISTS ammar_disputes_select
  ON public.ammar_disputes;
CREATE POLICY ammar_disputes_select
  ON public.ammar_disputes
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.ammar_market_requests AS r
      JOIN public.ammar_market_suppliers AS s
        ON s.id = r.supplier_id
      WHERE r.id = public.ammar_disputes.request_id
        AND (
          r.buyer_id = (SELECT auth.uid())
          OR s.owner_id = (SELECT auth.uid())
        )
    )
    OR (SELECT public.is_admin())
  );

-- Suppliers: active/public listing or own listing OR administrator.
DROP POLICY IF EXISTS ammir_admin_suppliers_select
  ON public.ammar_market_suppliers;
DROP POLICY IF EXISTS ammar_suppliers_select
  ON public.ammar_market_suppliers;
CREATE POLICY ammar_suppliers_select
  ON public.ammar_market_suppliers
  FOR SELECT TO authenticated
  USING (
    status = 'active'
    OR owner_id = (SELECT auth.uid())
    OR (SELECT public.is_admin())
  );

-- Supplier updates: owner OR administrator; both USING and WITH CHECK retained.
DROP POLICY IF EXISTS ammir_admin_suppliers_update
  ON public.ammar_market_suppliers;
DROP POLICY IF EXISTS ammar_suppliers_update
  ON public.ammar_market_suppliers;
CREATE POLICY ammar_suppliers_update
  ON public.ammar_market_suppliers
  FOR UPDATE TO authenticated
  USING (
    owner_id = (SELECT auth.uid())
    OR (SELECT public.is_admin())
  )
  WITH CHECK (
    owner_id = (SELECT auth.uid())
    OR (SELECT public.is_admin())
  );

-- Message reports: reporter OR administrator.
DROP POLICY IF EXISTS ammir_admin_message_reports_select
  ON public.ammar_message_reports;
DROP POLICY IF EXISTS ammar_message_reports_reporter_select
  ON public.ammar_message_reports;
CREATE POLICY ammar_message_reports_reporter_select
  ON public.ammar_message_reports
  FOR SELECT TO authenticated
  USING (
    reporter_id = (SELECT auth.uid())
    OR (SELECT public.is_admin())
  );

-- Service providers: active/public listing or own listing OR administrator.
DROP POLICY IF EXISTS ammir_admin_service_providers_select
  ON public.ammar_service_providers;
DROP POLICY IF EXISTS ammar_service_providers_select
  ON public.ammar_service_providers;
CREATE POLICY ammar_service_providers_select
  ON public.ammar_service_providers
  FOR SELECT TO authenticated
  USING (
    status = 'active'
    OR owner_id = (SELECT auth.uid())
    OR (SELECT public.is_admin())
  );

-- Service-provider updates: owner OR administrator.
DROP POLICY IF EXISTS ammir_admin_service_providers_update
  ON public.ammar_service_providers;
DROP POLICY IF EXISTS ammar_service_providers_update
  ON public.ammar_service_providers;
CREATE POLICY ammar_service_providers_update
  ON public.ammar_service_providers
  FOR UPDATE TO authenticated
  USING (
    owner_id = (SELECT auth.uid())
    OR (SELECT public.is_admin())
  )
  WITH CHECK (
    owner_id = (SELECT auth.uid())
    OR (SELECT public.is_admin())
  );

-- Transaction events: involved buyer/supplier OR administrator.
DROP POLICY IF EXISTS ammir_admin_transaction_events_select
  ON public.ammar_transaction_events;
DROP POLICY IF EXISTS ammar_transaction_events_select
  ON public.ammar_transaction_events;
CREATE POLICY ammar_transaction_events_select
  ON public.ammar_transaction_events
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.ammar_market_requests AS r
      JOIN public.ammar_market_suppliers AS s
        ON s.id = r.supplier_id
      WHERE r.id = public.ammar_transaction_events.request_id
        AND (
          r.buyer_id = (SELECT auth.uid())
          OR s.owner_id = (SELECT auth.uid())
        )
    )
    OR (SELECT public.is_admin())
  );

COMMIT;
