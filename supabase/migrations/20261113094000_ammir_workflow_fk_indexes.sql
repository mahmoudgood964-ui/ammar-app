-- Cover every new workflow FK discovered by Supabase Advisor.
BEGIN;
CREATE INDEX IF NOT EXISTS ammar_provider_verification_events_owner_idx
  ON public.ammar_provider_verification_events(owner_id);
CREATE INDEX IF NOT EXISTS ammir_boq_versions_published_by_idx
  ON public.ammir_project_boq_versions(published_by);
CREATE INDEX IF NOT EXISTS ammir_deliveries_received_by_idx
  ON public.ammir_project_deliveries(received_by);
CREATE INDEX IF NOT EXISTS ammir_rfq_invites_project_id_idx
  ON public.ammir_project_rfq_invites(project_id);
CREATE INDEX IF NOT EXISTS ammir_rfq_items_project_id_idx
  ON public.ammir_project_rfq_items(project_id);
CREATE INDEX IF NOT EXISTS ammir_rfq_quote_items_quote_project_idx
  ON public.ammir_project_rfq_quote_items(quote_id,project_id);
COMMIT;
