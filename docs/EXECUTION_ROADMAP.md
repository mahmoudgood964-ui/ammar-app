# عَمِّر | AMMIR — Execution Roadmap

This file is the single source of truth for closing the gap between the deployed product and a real, repeatable construction-procurement workflow.

## Product rule

Do not add broad feature scope until the critical transaction journey is tested end-to-end. Never create fake suppliers, products, prices, projects, or reviews to make the marketplace look populated.

## P0 — Production acceptance (must pass before broad public launch)

- [ ] Run a real buyer account through signup, project creation, team invitation, procurement, agreement, delivery, and closeout.
- [ ] Run a separate verified supplier/contractor account through onboarding, document review, invitation, quote submission, award, delivery, and commission statement.
- [ ] Verify a third, unrelated account cannot read or mutate either party's private project, quotes, messages, files, or delivery records.
- [ ] Verify admin account permissions, audit trail, rejection reasons, reports, and dispute workflow.
- [ ] Test Android browser/PWA: auth, file upload/download, signed URL expiry, Realtime reconnect, low-memory device, weak/interrupted network.
- [ ] Resolve or explicitly accept the Supabase leaked-password protection warning before broad launch.
- [ ] Approve market-specific terms, privacy notice, commission agreement, support and dispute procedures with qualified human review.

## P1 — Procurement workflow completion

- [ ] BOQ CSV import: validate required columns, units, numeric values, duplicate codes, encoding, and provide row-level errors before insert.
- [x] RFQ invitations: invite multiple verified suppliers/providers in one action; production DB already has a unique index on `(rfq_id, provider_user_id)` and the client now uses conflict-safe upsert to prevent race-condition duplicates. Multi-recipient UI is deployed; end-to-end acceptance with real separate accounts and invite status/reminders remain open.
- [ ] Quote comparison: compare line-by-line quantities, unit rates, delivery, loading, taxes, other costs, lead time, currency and terms; never compare different currencies as if equivalent.
- [ ] Partial award: award selected line items to more than one supplier while enforcing awarded quantity <= RFQ quantity.
- [ ] Generate a separate purchase/work order for each award and preserve accepted terms/version.
- [ ] Delivery evidence: record delivered, accepted, damaged and missing quantities, photos, timestamp, location and receiver confirmation.
- [ ] Handle partial delivery, rejection, return, cancellation and changes without duplicating or erasing earned commission.
- [ ] Supplier performance metrics based only on completed, verified transactions.

## P1 — Trust, operations and revenue

- [ ] Operational admin queue for supplier/provider verification, disputes, reports, overdue RFQs and delayed deliveries.
- [ ] Commission statements: accrued, due, paid, overdue, reversed; 5% provider-side policy remains the agreed rule.
- [ ] Commission collection procedure and provider agreement; no in-app custody or escrow until a licensed payment partner and legal review are in place.
- [ ] Real supplier/provider onboarding with consent, documents, references, coverage, specialties, product/service catalog and current availability.
- [ ] Pilot: target 3 real projects, 8 suppliers, 3 contractors and 2 engineering offices; these are initial targets, not validated market-size assumptions.

## P2 — Scale after pilot evidence

- [ ] Reliable email and push notifications with delivery/failure logs and retry.
- [ ] Project group conversations and escalation/SLA.
- [ ] Full bilingual coverage and English QA.
- [ ] Offline-friendly drafts and reliable background sync.
- [ ] Full-text historical message search.
- [ ] Procurement analytics and regional price/availability insights.

## Current known implementation facts

- BOQ versions/items, CSV import/export, RFQs, invitation, quote submission, quote comparison, award and delivery UI/schema already exist in partial form. Do not rebuild them from scratch.
- Existing comparison groups submitted quotes by currency; it needs a rigorous line-item and landed-cost review.
- RFQ invitations: multi-recipient selection is implemented; production schema inspection confirmed the unique index `ammir_project_rfq_invites_rfq_id_provider_user_id_key` and zero duplicate groups in the current table. Client-side duplicate precheck is backed by `upsert(... ignoreDuplicates: true)` for concurrent requests. Functional end-to-end verification with real accounts is still pending.
- Project delivery commission logic and provider-side 5% rules have been deployed and transactionally smoke-tested.
- RLS is enabled on all 59 public tables checked in production.
- No real supplier/provider network or full real-user acceptance journey has been proven yet.

## Execution order

1. Audit and test the existing BOQ/RFQ/quote/award/delivery path before changing schema.
2. Fix the highest-risk functional gaps with migration + regression test + preview deployment.
3. Run separate-account production acceptance using real consenting participants; never use synthetic production data outside rolled-back transactions.
4. Start a limited pilot; only then expand features and marketing.

## Release rule

Every implementation must include: migration (if needed), regression test, security/RLS review, preview verification, production deployment only after validation, and a concise release note. Preserve existing payment milestone tables and data.
