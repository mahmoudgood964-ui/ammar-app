-- Keep the paused bank-payment tables inaccessible through the client API.
-- This migration does not implement or reactivate the payment workflow.

BEGIN;

ALTER TABLE public.project_payment_milestones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "No client access while payment milestones are paused"
  ON public.project_payment_milestones;
CREATE POLICY "No client access while payment milestones are paused"
  ON public.project_payment_milestones
  FOR ALL TO anon, authenticated
  USING (false)
  WITH CHECK (false);
REVOKE ALL ON TABLE public.project_payment_milestones FROM anon, authenticated;

ALTER TABLE public.project_payment_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "No client access while payment events are paused"
  ON public.project_payment_events;
CREATE POLICY "No client access while payment events are paused"
  ON public.project_payment_events
  FOR ALL TO anon, authenticated
  USING (false)
  WITH CHECK (false);
REVOKE ALL ON TABLE public.project_payment_events FROM anon, authenticated;

COMMIT;
