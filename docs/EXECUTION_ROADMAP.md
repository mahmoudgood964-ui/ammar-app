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
- [x] Delivery evidence and reconciliation implementation: supplier dispatch, private evidence upload, manager review through short-lived signed URLs, per-line received/damaged/missing quantities, atomic receiver confirmation, and optional consent-based GPS metadata. Supplier dispatch fields and evidence Storage lifecycle are restricted by database policies/triggers.
- [ ] Separate buyer + supplier + unrelated-account end-to-end acceptance remains open; no production test accounts or persistent test data were created.
- [x] Incremental receipt batches: project managers can record multiple partial receipts against the same dispatched delivery; each batch has a unique idempotency key and immutable receipt/line history. Replaying the same key and payload returns the original receipt without adding quantities twice.
- [x] Authorization regression: the disposable PostgreSQL CI fixture confirms an authenticated but unrelated user is rejected by the receipt RPC with `Project manager permission required`.
- [x] Rejection accounting: record rejected quantities with a mandatory reason, separately from good, damaged and missing quantities. Only accepted-good quantities enter the commission basis.
- [x] Cancellation guard: a delivery with any receipt history or recorded quantities cannot be cancelled. Direct client edits/deletes of reconciled delivery quantities are blocked; only the private receipt RPC can append quantities.
- [x] Commission immutability: replace aggregate delivery commission triggers with one ledger source per receipt batch. Later partial receipts create new due entries and cannot rewrite previously paid commission rows. This does not process refunds or credits.
- [x] CI validation: the incremental receipt migration and SQL regression suite pass on feature branch run `45580391348`, including partial batches, same-key replay, changed-payload idempotency rejection, over-receipt rejection, mandatory rejection reasons, paid-ledger immutability, rejected-quantity exclusion, cancellation guard, direct-write guard, and unrelated-user authorization.
- [x] Accepted physical returns: a project manager can record a return only against an accepted quality/wrong-item claim and its exact receipt line. Cumulative returns are capped by both accepted claim quantity and accepted-good receipt quantity; return events are idempotent and append-only.
- [x] Proportional commission adjustment proposals: derive the adjustment from the original receipt-batch ledger entry and returned line value, using the commission amount already recorded for that batch (never a new or hardcoded rate). Multiple partial returns use cumulative target rounding and create only the incremental delta. Original commission rows, including paid rows, remain unchanged.
- [x] Adjustment proposals are immutable records with `pending_review` status; no refund, credit, cash movement, commission-ledger mutation, or settlement status change is performed. Finance approval and licensed payment-provider settlement remain separate future work.
- [ ] Validate the return workflow with authenticated buyer/supplier accounts and a real finance approver before enabling production settlement.
- [x] GitHub Actions PostgreSQL integration run `45584188082` passed: migration application, delivery/claims/returns SQL regression suite, private RPC permission checks, and browser/migration wiring validation. The validated code commit is `ace2344c39098db704bf690018f44e13d43c6bed`.
- [x] Supplier self-service performance view: read-only metrics from the supplier's own latest 500 manager-confirmed `received` deliveries with a recorded receipt timestamp. Visible only to an active, verified supplier account; shows completed delivery count and on-time rate only where a scheduled date exists. Partial, exception, cancelled and quote-only activity is excluded. No composite score or ranking is invented. Uses the existing supplier-only delivery SELECT policy; no admin-wide RLS expansion is required.
- [ ] Validate supplier metrics against real completed transactions during the pilot; current production has zero delivery, award and commission-ledger rows, so no real supplier performance score can be displayed yet.

## P1 — Trust, operations and revenue

- [ ] Operational admin queue for supplier/provider verification, disputes, reports, overdue RFQs and delayed deliveries.
- [x] Admin commission ledger statement: read-only view of recorded ledger rows and persisted statuses (`recorded`, `due`, `paid`, `void`, `refunded`), with bounded latest-100 query and status counts. No payment collection or settlement mutation is exposed. Overdue reporting remains deferred because the current ledger schema has no due-date field; do not infer overdue from age.
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
- Incremental delivery receipt migration adds append-only receipt batches, idempotent replay, per-line rejection quantities/reasons, manager-only reconciliation, cancellation protection after any receipt, and immutable commission entries per batch. Rejected/damaged/missing quantities are excluded from commission; paid entries are never recalculated by later batches. SQL regression coverage is wired into GitHub Actions and passed in runs `45515784254` and latest `45515975946` (including migration application, incremental receipt/commission tests, private-RPC permission checks, and browser-code validation). A Vercel preview exists for an earlier branch commit, but the latest commits still need a fresh preview/browser acceptance; production acceptance with real buyer/supplier accounts remains open.
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


## AMMIR delivery claims and dispute workflow — 2026-11-25

- [x] Add project-delivery claims linked to the delivery and, optionally, a specific immutable receipt line.
- [x] Support structured claim categories: damaged goods, missing goods, rejected goods, quality, wrong item, documentation, and other.
- [x] Restrict claim creation to the assigned supplier or project management roles; restrict messages to the claimant, assigned supplier, and project team.
- [x] Record opening, messages, evidence references, status transitions, and resolutions in an append-only claim event trail.
- [x] Require a written resolution note before a project manager can accept or reject a claim.
- [x] Prevent direct client inserts/updates/deletes of claims and events; expose authenticated operations through guarded RPCs.
- [x] Keep claim outcomes operational only: no automatic receipt edits, commission reversals, refunds, credits, or settlement mutations.
- [x] Full GitHub Actions run `45581908979` passed on code commit `37f09a9`, applying the claims migration and running receipt/claim SQL regressions plus browser-code/migration wiring checks, including supplier-side claim UI and authorization coverage.
- [ ] Authenticated buyer/supplier acceptance and evidence upload review remain pending.
- [x] Return recording and proportional commission adjustment proposals are implemented in a feature migration; adjustment proposals remain pending human finance review and do not move money.
- [ ] Finance approval authority, credit-note issuance, refunds, and payment-provider settlement remain unimplemented pending signed policy and legal/finance review.
