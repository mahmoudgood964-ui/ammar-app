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

- [x] BOQ CSV import validation: required columns, row width, CSV quoting, UTF-8 replacement-character detection, description/unit limits, positive quantities, non-negative rates, currency format/required currency when a rate is supplied, duplicate item codes within the file and against the target draft version, and aggregated row-level errors before any insert. Parser regression checks passed for valid input, duplicate codes, invalid quantity and malformed quoting; live import with a real project remains pending.
- [x] RFQ invitations: invite multiple verified suppliers/providers in one action; production DB already has a unique index on `(rfq_id, provider_user_id)` and the client now uses conflict-safe upsert to prevent race-condition duplicates. Multi-recipient UI is deployed; end-to-end acceptance with real separate accounts and invite status/reminders remain open.
- [x] Quote comparison UI: group submitted offers by the same RFQ and currency (not currency alone); show each requested line, quoted unit rate/quantity/availability/lead time, total landed cost, transport, loading, taxes, other costs, validity, warranty and exclusions. Different RFQs/currencies are never mixed in the comparison. JavaScript syntax validation passed; real quote dataset/acceptance testing remains pending.
- [x] Partial award quantity guard: production trigger `ammir_validate_award_item()` serializes concurrent awards with an advisory transaction lock and rejects cumulative awarded quantity above the RFQ line quantity. The application creates line-level awards; a dedicated transactional regression test and live multi-supplier acceptance remain pending.
- [x] Purchase orders: added a separate order header and immutable line snapshots for each accepted award, preserving supplier, RFQ item description/specification/unit, awarded quantities, unit rates, currency and accepted award terms. A single SECURITY DEFINER RPC (fixed empty search_path, authenticated execute only) creates the order and lines atomically; direct authenticated INSERT is revoked. RLS allows project members and the named supplier to read; only the supplier can accept/reject an issued order.
- [x] Delivery creation now requires an accepted purchase order; it no longer starts directly from an unaccepted award.
- [ ] Delivery evidence and reconciliation: supplier can now mark an assigned planned shipment as dispatched and upload JPG/PNG/WEBP/PDF proof (max 10 MB); database policies restrict dispatch and evidence to the assigned supplier; a trigger limits supplier dispatch updates to status/timestamp only. Existing project-side receipt reconciliation records received/damaged/missing quantities and manager evidence. GPS/location capture, receiver confirmation and two-account end-to-end acceptance remain open.
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

- BOQ versions/items, CSV import/export, RFQs, invitation, quote submission, quote comparison, award and delivery UI/schema already exist in partial form. Do not rebuild them from scratch. BOQ CSV validation was strengthened and parser regression-tested; no production data was inserted during these checks.
- Purchase-order tables, line snapshots, RPC, RLS and supplier acceptance/rejection are now deployed. New purchase orders and items are currently empty; authenticated users cannot insert directly, and unauthenticated RPC issuance was rejected in a no-write guard test.
- Quote comparison now groups by RFQ + currency and includes line-level coverage and landed-cost components; partial-award over-allocation is guarded by an advisory-lock trigger; a 6+5 over-allocation against quantity 10 was rejected in a rollback-only production regression test.
- Purchase orders are now issued only from accepted awards and delivery records can be created only from supplier-accepted purchase orders. Suppliers can dispatch their assigned delivery and upload evidence; DB status and storage policies enforce the supplier/project relationship. Full two-account acceptance and delivery/commission end-to-end tests remain open.
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


## Delivery reconciliation and evidence review — 2026-11-18

- [x] Added optional location columns to delivery evidence with latitude/longitude/accuracy checks. The browser asks for geolocation only after the user checks an explicit consent option.
- [x] Project manager view now displays delivery lines and evidence metadata and opens private files through signed URLs valid for five minutes.
- [x] Receipt UI now provides per-line fields for accepted-good, damaged, missing, and condition notes.
- [x] Added atomic ammir_reconcile_project_delivery RPC. It verifies caller authentication, project role, dispatched status, exact line coverage, duplicate item IDs, non-negative quantities, and per-line quantity bounds before updating all lines and delivery state in one transaction.
- [x] On receipt RPC failure, the client removes any evidence metadata/object it just uploaded.
- [x] Moved ammir_issue_purchase_order privileged implementation into app_private; the public RPC is now SECURITY INVOKER and delegates to the private function. anon has no execute permission.
- [x] Consolidated delivery/evidence RLS policies and corrected explicit project_id qualification in evidence supplier policies.
- [x] Added indexes covering the four purchase-order foreign-key paths.
- [x] JavaScript syntax compilation passed for all inline scripts in index.html and ammar-marketplace.js; latest Vercel production deployment is READY.
- [x] Unauthenticated call to the new receipt RPC was rejected with Authentication required before any write.
- [ ] Real account acceptance across buyer, supplier, and unrelated account remains pending; no production delivery/evidence records were inserted.
- [ ] Supabase Auth leaked-password protection remains disabled and must be enabled in Auth settings.


- [x] Final storage lifecycle hardening: consolidated supplier/manager Storage SELECT and INSERT rules; evidence deletion is now manager-only so a supplier cannot delete its uploaded object while leaving an orphaned evidence metadata record. Verified the private bucket, allowed MIME types and 15 MB storage ceiling (the UI enforces 10 MB).
- [x] Re-ran Supabase advisors after the storage change: no exposed SECURITY DEFINER warning and no multiple-permissive-policy warning remain. Only the existing Auth leaked-password protection warning and informational unused-index notices remain.


## Regression and browser smoke checks — 2026-11-18

- [x] Production rollback-only split-award regression: first 6 units accepted against requested quantity 10; a second 5-unit award was rejected with the expected over-allocation error. Follow-up count confirmed zero rollback-test RFQs/awards remained.
- [x] BOQ CSV parser tests: valid UTF-8 BOM + CRLF + Arabic quoted comma + escaped quote accepted; unterminated quote, malformed quote, duplicate item code, negative quantity, missing currency for a supplied rate, and replacement-character encoding errors rejected.
- [x] Live production browser smoke test in Chromium: official app returned HTTP 200, correct Arabic/English title, no JavaScript page errors, no same-origin failed requests, and no horizontal overflow at desktop 1365px or mobile 390px.
- [x] Production homepage content confirms the delivery evidence review, atomic reconciliation RPC integration, and optional location UI are included in the served build.
- [ ] Authenticated buyer/supplier project-workflow UI and Android native-device acceptance remain untested because no separate real test accounts/participants were available; no accounts or test records were created in production.

- [x] Security regression for the new receipt RPC: a synthetic unrelated authenticated identity was tested against a temporary dispatched-delivery row inside a rollback transaction; the RPC rejected it with Project manager permission required. The row was confirmed absent after rollback.

- [x] Full rollback-only database workflow regression: draft RFQ → submitted quote → issued/accepted award → purchase-order RPC → supplier PO acceptance → delivery → dispatch → exception receipt. With 10 units expected, 6 good + 2 damaged + 2 missing produced gross commission basis 600 SDG and exactly 30 SDG at 5%; damaged/missing quantities were excluded.
- [x] Replayed the delivery-item commission trigger and confirmed the ledger remained one row; a second receipt RPC call was rejected because the delivery was no longer dispatched.
- [x] Confirmed the synthetic RFQ, award and delivery counts returned to zero after transaction rollback. This is database workflow regression coverage using one existing project-owner identity, not a two-account acceptance test.
