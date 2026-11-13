# AMMIR — Project Execution Workflow Handover
Date: 2026-11-13

## Product scope delivered in the current development branch

AMMIR is being developed as a construction and renovation project operating system. The project workspace now includes the following end-to-end commercial and execution capabilities:

1. Versioned BOQ — draft and published versions, structured item codes, descriptions, specifications, units, quantities, optional rates, and revision history. Published BOQs are immutable. CSV template download, CSV import, and CSV export are available in the project workspace.
2. Multi-provider RFQ — publish a request from a published BOQ snapshot, include delivery location, currency, deadline and scope, and invite active, verified suppliers or service providers.
3. Supplier privacy — providers see only their invitations, the RFQ lines sent to them, their own quote, and awards directed to their account. They cannot query competing providers' submitted prices through the workflow's RLS policies.
4. Structured quotations — provider line pricing, available/partial/unconfirmed/unavailable quantities, delivery lead time, validity date, warranty terms, exclusions, transport, loading, taxes and other charges. A database trigger derives the submitted total from line items and charges.
5. Quote comparison — compare submitted quotes by line, availability, delivery time, warranty, exclusions and landed-cost components. Currencies remain separate; prices in different currencies are not combined into a false total.
6. Partial awards — award line quantities to one or multiple providers. Database triggers enforce the quoted rate/currency and prevent cumulative awarded quantities from exceeding the RFQ quantity.
7. Delivery and receiving — record deliveries against issued/accepted awards, reconcile received/damaged/missing quantities, and preserve the state and audit trail of completed or evidenced deliveries.
8. Private delivery evidence — upload photos/PDFs to the private `ammir-delivery-evidence` bucket and create signed URLs for authorized project users.
9. Provider inbox — providers can accept/decline invitations, submit their own quotation, and accept/reject directed awards.

## Database changes

The six additive workflow migrations were applied to both the separate staging project and the production project:

- `20261113090000_ammir_boq_rfq_awards_delivery.sql`
- `20261113091000_ammir_workflow_rls_and_indexes.sql`
- `20261113092000_ammir_verified_provider_gates_and_quote_totals.sql`
- `20261113093000_ammir_workflow_state_guards.sql`
- `20261113094000_ammir_workflow_fk_indexes.sql`
- `20261113100000_ammir_execution_state_guards.sql`

The workflow adds 12 tables. Production verification confirmed RLS on all 12, authenticated SELECT grants on all 12, no duplicate permissive policies for the new workflow actions, a private delivery-evidence bucket, and storage policies for that bucket.

The existing bank-milestone tables `project_payment_milestones` and `project_payment_events` were not modified. The workflow does not receive, hold, transfer, or escrow money.

## Validation

- GitHub Actions run `43401026288` passed on branch head `8deba66c1b194177c5d6d4b4c7fc706cc37a2f14`, including migration application and the BOQ/RFQ/award/delivery regression suite.
- The regression suite checks published BOQ/RFQ immutability, quote totals, provider invitation response, split-award quantity and price controls, delivery supplier matching, receipt-state guards, over-delivery, and evidence metadata.
- Static checks also execute the BOQ CSV parser against a file with a BOM, quoted commas, numeric quantities and blank optional rates.
- Supabase Advisors were checked after the production migration. The new workflow foreign-key index warnings were addressed. Remaining Advisor warnings relate to pre-existing project features and are documented in the session handover.

## Release status and explicit acceptance boundary

- GitHub PR #3 remains open and in Draft; production frontend has not been replaced by this branch.
- Latest READY Vercel preview available at handover: `https://ammar-t2jve2hjk-mahmoudgood964-ui.vercel.app`, built from commit `a9a6e4078b50ba2730bc414b440cab86cf8e855b`.
- The current source branch head is newer than that preview and includes the CSV import/export and test refinements. A fresh Vercel deployment could not be created because the Vercel deployment quota was exhausted.
- Real production account acceptance using separate owner/provider accounts, file upload/download through a real authenticated browser session, Realtime verification, and physical Android/weak-network testing have not been performed in this session.
- Supabase Auth leaked-password protection remains an existing configuration item requiring an authenticated Auth settings change; it is not changed by these SQL migrations.

Do not declare the frontend production release complete until a preview of the exact head is available and real-account/mobile acceptance has passed.
