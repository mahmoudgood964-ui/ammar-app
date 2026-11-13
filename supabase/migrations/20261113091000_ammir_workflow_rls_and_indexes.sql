-- Tighten AMMIR workflow row policies and index every new workflow foreign key.
BEGIN;

-- Replace permissive FOR ALL policies with action-specific policies. This keeps
-- read-only project roles separate from write-capable project roles.

DROP POLICY IF EXISTS ammir_boq_versions_write ON public.ammir_project_boq_versions;
CREATE POLICY ammir_boq_versions_insert ON public.ammir_project_boq_versions
FOR INSERT TO authenticated WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_boq_versions_update ON public.ammir_project_boq_versions
FOR UPDATE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_boq_versions_delete ON public.ammir_project_boq_versions
FOR DELETE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));

DROP POLICY IF EXISTS ammir_boq_items_write ON public.ammir_project_boq_items;
CREATE POLICY ammir_boq_items_insert ON public.ammir_project_boq_items
FOR INSERT TO authenticated WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_boq_items_update ON public.ammir_project_boq_items
FOR UPDATE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_boq_items_delete ON public.ammir_project_boq_items
FOR DELETE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));

DROP POLICY IF EXISTS ammir_rfqs_write ON public.ammir_project_rfqs;
CREATE POLICY ammir_rfqs_insert ON public.ammir_project_rfqs
FOR INSERT TO authenticated WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_rfqs_update ON public.ammir_project_rfqs
FOR UPDATE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_rfqs_delete ON public.ammir_project_rfqs
FOR DELETE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));

DROP POLICY IF EXISTS ammir_rfq_items_write ON public.ammir_project_rfq_items;
CREATE POLICY ammir_rfq_items_insert ON public.ammir_project_rfq_items
FOR INSERT TO authenticated WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_rfq_items_update ON public.ammir_project_rfq_items
FOR UPDATE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_rfq_items_delete ON public.ammir_project_rfq_items
FOR DELETE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));

DROP POLICY IF EXISTS ammir_rfq_invites_write ON public.ammir_project_rfq_invites;
DROP POLICY IF EXISTS ammir_rfq_invites_provider_response ON public.ammir_project_rfq_invites;
CREATE POLICY ammir_rfq_invites_insert ON public.ammir_project_rfq_invites
FOR INSERT TO authenticated WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_rfq_invites_update ON public.ammir_project_rfq_invites
FOR UPDATE TO authenticated
USING (
  public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
  OR (provider_user_id = (SELECT auth.uid()) AND status = 'invited')
)
WITH CHECK (
  public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
  OR (provider_user_id = (SELECT auth.uid()) AND status IN ('accepted','declined'))
);
CREATE POLICY ammir_rfq_invites_delete ON public.ammir_project_rfq_invites
FOR DELETE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
REVOKE UPDATE ON public.ammir_project_rfq_invites FROM authenticated;
GRANT UPDATE(status, responded_at) ON public.ammir_project_rfq_invites TO authenticated;

DROP POLICY IF EXISTS ammir_awards_write ON public.ammir_project_awards;
DROP POLICY IF EXISTS ammir_awards_provider_response ON public.ammir_project_awards;
CREATE POLICY ammir_awards_insert ON public.ammir_project_awards
FOR INSERT TO authenticated WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_awards_update ON public.ammir_project_awards
FOR UPDATE TO authenticated
USING (
  public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
  OR (supplier_user_id = (SELECT auth.uid()) AND status = 'issued')
)
WITH CHECK (
  public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer')
  OR (supplier_user_id = (SELECT auth.uid()) AND status IN ('accepted','rejected'))
);
CREATE POLICY ammir_awards_delete ON public.ammir_project_awards
FOR DELETE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
REVOKE UPDATE ON public.ammir_project_awards FROM authenticated;
GRANT UPDATE(status, accepted_at) ON public.ammir_project_awards TO authenticated;

DROP POLICY IF EXISTS ammir_award_items_write ON public.ammir_project_award_items;
CREATE POLICY ammir_award_items_insert ON public.ammir_project_award_items
FOR INSERT TO authenticated WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_award_items_update ON public.ammir_project_award_items
FOR UPDATE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_award_items_delete ON public.ammir_project_award_items
FOR DELETE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));

DROP POLICY IF EXISTS ammir_deliveries_write ON public.ammir_project_deliveries;
CREATE POLICY ammir_deliveries_insert ON public.ammir_project_deliveries
FOR INSERT TO authenticated WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_deliveries_update ON public.ammir_project_deliveries
FOR UPDATE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_deliveries_delete ON public.ammir_project_deliveries
FOR DELETE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));

DROP POLICY IF EXISTS ammir_delivery_items_write ON public.ammir_project_delivery_items;
CREATE POLICY ammir_delivery_items_insert ON public.ammir_project_delivery_items
FOR INSERT TO authenticated WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_delivery_items_update ON public.ammir_project_delivery_items
FOR UPDATE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_delivery_items_delete ON public.ammir_project_delivery_items
FOR DELETE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));

DROP POLICY IF EXISTS ammir_delivery_evidence_write ON public.ammir_project_delivery_evidence;
CREATE POLICY ammir_delivery_evidence_insert ON public.ammir_project_delivery_evidence
FOR INSERT TO authenticated WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_delivery_evidence_update ON public.ammir_project_delivery_evidence
FOR UPDATE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'))
WITH CHECK (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));
CREATE POLICY ammir_delivery_evidence_delete ON public.ammir_project_delivery_evidence
FOR DELETE TO authenticated USING (public.ammar_project_role(project_id::text) IN ('owner','manager','supervisor','engineer'));

-- Cover the new foreign-key lookup paths as well as the common project views.
CREATE INDEX IF NOT EXISTS ammir_boq_versions_created_by_idx ON public.ammir_project_boq_versions(created_by);
CREATE INDEX IF NOT EXISTS ammir_boq_items_version_project_fk_idx ON public.ammir_project_boq_items(boq_version_id, project_id);
CREATE INDEX IF NOT EXISTS ammir_boq_items_parent_idx ON public.ammir_project_boq_items(parent_item_id);
CREATE INDEX IF NOT EXISTS ammir_boq_items_created_by_idx ON public.ammir_project_boq_items(created_by);
CREATE INDEX IF NOT EXISTS ammir_rfqs_boq_version_project_fk_idx ON public.ammir_project_rfqs(boq_version_id, project_id);
CREATE INDEX IF NOT EXISTS ammir_rfqs_created_by_idx ON public.ammir_project_rfqs(created_by);
CREATE INDEX IF NOT EXISTS ammir_rfq_items_project_fk_idx ON public.ammir_project_rfq_items(rfq_id, project_id);
CREATE INDEX IF NOT EXISTS ammir_rfq_items_boq_item_project_fk_idx ON public.ammir_project_rfq_items(boq_item_id, project_id);
CREATE INDEX IF NOT EXISTS ammir_rfq_invites_project_fk_idx ON public.ammir_project_rfq_invites(rfq_id, project_id);
CREATE INDEX IF NOT EXISTS ammir_rfq_invites_invited_by_idx ON public.ammir_project_rfq_invites(invited_by);
CREATE INDEX IF NOT EXISTS ammir_rfq_quotes_project_idx ON public.ammir_project_rfq_quotes(project_id);
CREATE INDEX IF NOT EXISTS ammir_rfq_quotes_project_fk_idx ON public.ammir_project_rfq_quotes(rfq_id, project_id);
CREATE INDEX IF NOT EXISTS ammir_rfq_quotes_provider_fk_idx ON public.ammir_project_rfq_quotes(provider_user_id);
CREATE INDEX IF NOT EXISTS ammir_rfq_quote_items_rfq_item_idx ON public.ammir_project_rfq_quote_items(rfq_item_id);
CREATE INDEX IF NOT EXISTS ammir_rfq_quote_items_project_idx ON public.ammir_project_rfq_quote_items(project_id);
CREATE INDEX IF NOT EXISTS ammir_awards_project_fk_idx ON public.ammir_project_awards(rfq_id, project_id);
CREATE INDEX IF NOT EXISTS ammir_awards_created_by_idx ON public.ammir_project_awards(created_by);
CREATE INDEX IF NOT EXISTS ammir_awards_supplier_fk_idx ON public.ammir_project_awards(supplier_user_id);
CREATE INDEX IF NOT EXISTS ammir_award_items_award_project_fk_idx ON public.ammir_project_award_items(award_id, project_id);
CREATE INDEX IF NOT EXISTS ammir_award_items_project_fk_idx ON public.ammir_project_award_items(project_id);
CREATE INDEX IF NOT EXISTS ammir_award_items_quote_item_idx ON public.ammir_project_award_items(quote_item_id);
CREATE INDEX IF NOT EXISTS ammir_deliveries_award_project_fk_idx ON public.ammir_project_deliveries(award_id, project_id);
CREATE INDEX IF NOT EXISTS ammir_deliveries_supplier_idx ON public.ammir_project_deliveries(supplier_user_id);
CREATE INDEX IF NOT EXISTS ammir_deliveries_created_by_idx ON public.ammir_project_deliveries(created_by);
CREATE INDEX IF NOT EXISTS ammir_delivery_items_delivery_project_fk_idx ON public.ammir_project_delivery_items(delivery_id, project_id);
CREATE INDEX IF NOT EXISTS ammir_delivery_items_project_fk_idx ON public.ammir_project_delivery_items(project_id);
CREATE INDEX IF NOT EXISTS ammir_delivery_evidence_delivery_project_fk_idx ON public.ammir_project_delivery_evidence(delivery_id, project_id);
CREATE INDEX IF NOT EXISTS ammir_delivery_evidence_project_fk_idx ON public.ammir_project_delivery_evidence(project_id);
CREATE INDEX IF NOT EXISTS ammir_delivery_evidence_uploaded_by_idx ON public.ammir_project_delivery_evidence(uploaded_by);

COMMIT;
