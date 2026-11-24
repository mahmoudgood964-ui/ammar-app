# AMMIR Release Acceptance Pack — 2026-11-24

**Purpose:** one operational checklist for closing Release 0 (production trust) and validating Revenue Foundation v1 without risking production.
**Status:** prepared on the feature branch. This document is not evidence that human acceptance, legal approval, or mobile-device testing has occurred.

## 1. Verified technical baseline

- Repository: `mahmoudgood964-ui/ammar-app`; production branch: `main`.
- Revenue implementation PR: #14, branch `feature/ammir-revenue-engine-v1`.
- Latest application-and-test head verified for this pack: `e9ccd0ef7835829a2a7bdde1680d27b9ab34437c`.
- Vercel deployment lookup returned no deployment for exact head `e9ccd0ef`; the earlier READY preview remains only for an older application-code head. Preview status for the adjusted-revenue UI is unverified.
- Supabase production project: `uutwijowzewmvvrzsaww`, ACTIVE_HEALTHY, PostgreSQL 17.
- Production migration history does not contain `20261124211500` or `20261124230000`.
- No Supabase development branches exist; to avoid recurring compute charges, revenue migration tests now run in an ephemeral PostgreSQL 17 service container inside GitHub Actions instead of a paid Supabase branch.
- Production schema/data were not changed during this work.

## 2. CI failure and correction

The workflow run associated with the previous PR head (`797705962acdb70db79826b6407ffc10c593a29f`) completed with failure. All preceding database, trust/admin, marketplace, messaging, storage, RLS, and private-RPC steps shown in that run completed successfully. The final static application check failed because it hard-coded the old Service Worker cache name `ammir-shell-v9-identity-first-load`, while both `main` and the feature branch already use `ammir-shell-v10-persistent-auth`.

The test was corrected on this feature branch to assert a versioned AMMIR shell cache-name pattern rather than one obsolete literal. This is a test-maintenance correction, not a change to the Service Worker or its cache behaviour. A fresh green workflow run confirmed the correction: [GitHub Actions run #45489721782](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45489721782), commit `d3a216036a129279cb7c9eb3377641280b182e5a` (SUCCESS). The expanded fee-decrease, invalid-input and same-key concurrency tests were then run on `34d3dbb9b1179d1bdbad03aa260fcb14d0168e2e`; both [push run #45492304272](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45492304272) and [pull-request run #45492316397](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45492316397) completed SUCCESS. Additional tests for blank/NULL inputs, original-ledger immutability and legacy payment-table fixture isolation were added. The latest code head `8c02a9e0cd83eb4788e0a5b5dca926857812d0fd` then passed both [push run #45493387107](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45493387107) and [pull-request run #45493400405](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45493400405), with all workflow steps green. The revenue CSV export was then hardened against spreadsheet-formula injection in untrusted text fields, including formulas preceded by whitespace; numeric amount columns remain numeric text. The application-code head `208cce64edbc3cbd1d555cba0d486e92e6c2e262` passed [push run #45493781094](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45493781094) and [pull-request run #45493795458](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45493795458), with all workflow steps green. Follow-up trigger regression coverage was added at `677fba2e2449a5bc56a40ebfdb1de2766b1cdfbb`; [push run #45495329660](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45495329660) completed SUCCESS with all workflow steps green. The revenue dashboard was then updated to load append-only adjustment rows for the displayed ledger records, calculate original commission + adjustment delta = adjusted net commission, show a separate adjustment history, and export ledger and adjustment events as distinct CSV record types. Currency mismatches are rejected in the client summary as a defensive check. CI tests cover multiple adjustments, fee increases/decreases, net arithmetic, original-ledger immutability, currency mismatch, and formula-safe negative numeric CSV values. Exact application head `3227e62cc1f38d223e64728c67c0d65216daf595` passed [pull-request run #45496210713](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45496210713) and [push run #45496212858](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45496212858) (both SUCCESS). The adjustment loader was then covered for paginated results and bounded 200-ID query chunks; an initial failure was traced to an incorrect test mock that returned page length as total count, not to application logic. The mock was corrected to match PostgREST exact-count semantics. Latest head `b2c198d30b3af267f19c7080dd4ab9a6404cd977` passed [push run #45497011770](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45497011770) and [pull-request run #45497027267](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45497027267) (both SUCCESS). A follow-up corrected CSV numeric typing so negative `adjustment_delta` and `net_commission_amount` values remain numeric in spreadsheet exports, and added explicit regression assertions. Latest exact head `e9ccd0ef7835829a2a7bdde1680d27b9ab34437c` passed [push run #45497243476](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45497243476) and [pull-request run #45497228884](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45497228884); both completed SUCCESS, with all 37 workflow steps green in the push run.

## 3. Release 0 — production acceptance checklist

### A. Buyer / supplier / unrelated account

Use three consenting, non-production test accounts: buyer A, verified supplier B, unrelated account C. Do not use real customer data.

- [ ] Buyer A creates a project and a procurement request / RFQ.
- [ ] Supplier B can see only eligible RFQs and can submit a quote.
- [ ] Buyer A can compare quotes and award/accept through the supported flow.
- [ ] Supplier B can accept the purchase order and dispatch a delivery.
- [ ] Buyer A can record receipt and attach evidence.
- [ ] Unrelated account C cannot read or mutate A/B projects, RFQs, quotes, orders, conversations, files, delivery evidence, or private signed URLs.
- [ ] Repeat negative-access checks after logout/login and with copied object IDs.
- [ ] Capture sanitized screenshots, account roles, timestamps, and pass/fail evidence. Never store passwords or access tokens in this pack.

### B. Admin trust, moderation, disputes

- [ ] Non-admin cannot invoke admin RPCs or reveal the admin workspace.
- [ ] Admin can review provider documents, approve/reject, and see audit history.
- [ ] Rejection reason is persisted and visible only to authorized parties.
- [ ] Admin can open a dispute, review evidence, record a decision, and verify the resulting audit trail.
- [ ] Unrelated users cannot access private dispute evidence.
- [ ] Capture sanitized test evidence and actor roles.

### C. Physical Android and weak network

Test at least one real Android device, not only desktop emulation.

- [ ] Fresh install / first page load / add-to-home-screen.
- [ ] Sign-in, session persistence, refresh, sign-out and recovery.
- [ ] Upload and download a permitted document; verify signed URL expiry and ownership checks.
- [ ] Toggle network off during navigation and upload; verify clear retry/error states and no duplicate submission.
- [ ] Restore network; verify Realtime reconnect and fresh data.
- [ ] Verify no stale cached private page is exposed after sign-out or account switch.
- [ ] Record device model, Android/browser version, network profile, and outcome.

### D. Auth and legal readiness

- [ ] Review Supabase Auth leaked-password protection setting and enable only after confirming compatibility; do not change email confirmation or SMTP in this work.
- [ ] Re-run signup, sign-in, password reset and password update tests after any Auth setting change.
- [ ] Qualified local counsel reviews terms, privacy notice, supplier/provider agreement, commission disclosure, refunds/returns, customer support, and disputes.
- [ ] Store counsel approval date and document version outside this technical checklist. No legal approval is implied by this file.

**Release 0 exit:** all relevant boxes above have evidence, no critical access-control defect remains, and the owner signs the acceptance record.

## 4. Revenue Foundation v1 — required safe-database test matrix

The two migrations below are committed to the feature branch only. They must not be applied to production until this matrix passes on a disposable, isolated PostgreSQL/Supabase-compatible test database built from the same migration baseline.

- `20261124211500_add_ammir_commission_adjustments.sql`
- `20261124230000_protect_paid_commission_ledger_rows.sql`

### Commission adjustments RPC and table

- [x] Anonymous role has no EXECUTE privilege on the RPC (CI privilege assertion; direct anonymous invocation is not separately simulated).
- [x] Authenticated non-admin cannot execute the RPC (CI fixture).
- [x] Admin can create a valid partial refund; delta is negative (CI fixture).
- [x] Admin can create a valid fee decrease; delta is negative (CI fixture).
- [x] Admin can create a valid fee increase; delta is positive (CI fixture).
- [x] Full reversal equals the remaining balance after prior adjustments (CI fixture).
- [x] Reduction exceeding remaining balance is rejected (CI fixture).
- [x] Currency mismatch is rejected (CI fixture).
- [x] Short/blank/NULL reason, short/NULL idempotency key, blank currency, NULL/zero/negative amount, and >2-decimal amount are rejected (CI fixtures). Malformed non-short key formats are not separately constrained or tested.
- [x] Same idempotency key + same payload returns the same adjustment ID and creates one row (CI fixture).
- [x] Same idempotency key + different payload is rejected (CI fixture).
- [x] UPDATE and DELETE are rejected by the immutable trigger (CI fixture).
- [x] Payer can read their own adjustment rows; unrelated payer cannot; administrator can read all rows under the authenticated RLS fixture (CI fixture). Full UI/admin account acceptance remains open.
- [x] Concurrent reductions with distinct keys cannot reduce net commission below zero (two-session CI test).
- [x] Concurrent replay with the same key produces one logical adjustment (two-session CI test; both calls succeed and exactly one row is recorded).
- [x] Original ledger fixture gross amount, currency, rate, commission amount, payer and status remain unchanged after adjustments; legacy payment milestone/event fixtures remain empty (CI assertion).

### Revenue dashboard adjustment visibility

- [x] Dashboard loads append-only adjustments associated with the displayed ledger rows (admin-only RLS path; UI acceptance remains open).
- [x] Net commission is calculated as original ledger commission plus all associated signed adjustments.
- [x] Original ledger commission remains visible separately and is not overwritten by the adjusted net amount.
- [x] Paid ledger amount is labelled as the original ledger settlement state; later adjustments are not represented as bank-settled cash.
- [x] Adjustment history displays type, signed amount, reason, external reference and linked ledger identifier.
- [x] CSV exports ledger rows and adjustment events as distinct record types, with adjusted net amount on ledger rows.
- [x] Client-side summary rejects adjustment/ledger currency mismatches defensively.
- [x] CI verifies partial refund, fee decrease, fee increase aggregation, net arithmetic, original-value preservation, currency mismatch rejection, and negative numeric CSV formatting.
- [x] CI verifies adjustment loading across paginated result sets and 200-ledger-ID chunks (mock reproduces exact total-count semantics; all pages/chunks asserted).
- [ ] Verify the adjusted dashboard on a Vercel preview for the exact tested application/test head and complete manual admin UI acceptance. The available READY preview serves the adjusted revenue UI code but was built from an earlier app commit; no preview exists for the latest branch head.

### Paid-ledger trigger protection

- [x] Delivery commission row is created on fully received and clean partial-receipt paths; the partial-receipt basis is limited to received quantity, and a changed received quantity synchronizes the unpaid row (CI fixture). Missing/damaged quantities remain exception cases.
- [x] Editing a non-paid delivery updates the corresponding non-paid ledger row as expected (CI fixture; gross and commission amounts asserted).
- [x] Editing a paid delivery does not change paid gross amount, commission amount, rate, payer, or paid status (CI fixture; currency remains part of the unchanged ledger row but was not separately mutated).
- [x] Removing a delivery item does not rewrite or void a paid row's financial values (CI fixture; amount, currency, rate, payer and paid status asserted).
- [x] Delivery status leaving received states does not void a paid row (CI cancellation-path fixture).
- [x] Service-award commission is created on the tested existing award-completion path (CI fixture).
- [x] Repeated delivery/service-award trigger paths preserve the same paid ledger row (CI fixture).
- [x] Existing award-with-delivery duplicate prevention remains intact (CI fixture completes an award with an existing delivery and asserts no second service-award ledger entry).
- [x] No production payment milestone, payment event, commission rate, or historical ledger row was modified during this work (production migration history and read-only checks; CI tests run only in disposable PostgreSQL).

### Required SQL evidence

For every case, record: fixture IDs, role/claims, SQL command or test name, expected result, actual result, and transaction rollback/cleanup result. Include a concurrent-session test for the row-lock guarantee. A static source scan is not a substitute for executing this matrix.

## 5. Release 1 items still outside this PR

- Supplier/provider period statements with transaction-level source links.
- Settlement reconciliation against actual payment-provider or bank reports.
- Overdue, waived, disputed and settlement lifecycle definitions.
- Fee-policy versioning and effective-date rules for future markets/services.
- Owner-approved fee taxonomy and local tax/legal treatment.
- No new rates are approved by this pack; existing configured rates remain unchanged.

## 6. Later releases and gates

- **P2:** logistics, supplier tools, sponsored placements, inspection/verification, equipment/services, enterprise procurement and market intelligence. Each needs a scoped pilot, cost-to-serve, refund/tax/legal review and measurable contribution margin.
- **P3:** True Cost, AI BOQ extraction, procurement agent, group buying, material passport, surplus exchange and supplier reliability. AI output must cite source data and require human confirmation for commercial actions.
- **P4:** financing, insurance and payment capabilities only through appropriately licensed partners after jurisdiction-specific legal review. AMMIR does not hold customer funds or lend.
- **P5:** UAE/Saudi/other markets only after local partner, verified supply density, real completed transactions, repeat usage, fulfilment reliability and contribution-margin gates.

## 7. Release decision record

| Gate | Current status | Evidence needed |
|---|---|---|
| PR #14 | Open / draft; latest head `143b5b2`; not merged | Latest CI for this head is running; earlier feature heads passed. No merge or production migration/deployment has been authorized. |
| Vercel preview | READY preview exists at `https://ammar-4na89ynyy-mahmoudgood964-ui.vercel.app`; its deployed JavaScript contains the adjusted revenue dashboard, adjustment history, CSV export, and admin guard. It is not built from the latest branch head. | Obtain preview for the exact latest head after deployment quota allows, then complete manual admin UI acceptance; preview is not production |
| New SQL migrations | Both migrations applied and tested only in ephemeral GitHub Actions PostgreSQL 17; not applied to production | Review rollback and remaining edge cases; then explicit release decision |
| P0 buyer/supplier/unrelated user | Not evidenced complete | Real consenting test accounts and evidence |
| P0 admin/disputes | Not evidenced complete | Real admin test evidence |
| P0 Android/weak network | Not evidenced complete | Physical device test record |
| Auth leaked-password protection | Previously reported disabled | Setting review and post-change auth regression |
| Local legal approval | Not evidenced complete | Qualified local counsel approval |
| P2–P5 | Not implemented as full releases | Pilot/partner/compliance gates above |

**Production safety rule:** do not merge/deploy financial code or apply either migration until CI is green, the safe-database matrix passes, rollback is reviewed, and the owner explicitly approves the release. Preserve existing payment milestone logic and all historical financial data.

## 5. Follow-up regression evidence — partial receipts and table grants

The delivery workflow regression suite now explicitly covers a clean partial receipt: a delivery has an outstanding quantity but no missing/damaged quantity, the commission basis is limited to the received quantity, and a subsequent received-quantity change synchronizes the still-unpaid ledger row. The test intentionally respects the delivery state guard; missing or damaged quantities remain exception cases rather than being mislabeled as a clean partial receipt.

The revenue-engine SQL assertions now also verify the adjustment table's least-privilege grants (authenticated read only, no anonymous read, no direct authenticated insert/update/delete) and require the SECURITY DEFINER adjustment RPC to pin its search path. These are test-only additions; no production grant, policy, or function was changed.

Exact head `d40825c9827826067c3d83f4a769f28f25514327` passed [push run #45503249823](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45503249823) and [pull-request run #45503260402](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45503260402), both SUCCESS. The partial-receipt correction head `3dfe6fbd7a990234a0c201bec9dc20bbd209d22b` also passed [push run #45502800544](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45502800544) and [pull-request run #45502811222](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45502811222), both SUCCESS.

A Vercel preview was requested for exact head `d40825c`, but the Vercel API again returned HTTP 402 `api-deployments-free-per-day` with a 24-hour retry window. No billing, plan, project, or production settings were changed. The feature remains unmerged and its migrations remain unapplied to production.

## 6. Administrator adjustment visibility regression

The revenue-engine SQL test now confirms all three sides of the adjustment read policy: the payer sees their own adjustments, an unrelated authenticated account sees none, and an administrator can read all adjustment rows. The assertion runs under the authenticated role with the admin fixture, so it exercises the policy rather than merely inspecting its definition.

Exact head `ea9b0c52d0836129325ee18bdc8465bc1f377186` passed [push run #45503670749](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45503670749) and [pull-request run #45503683103](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45503683103), both SUCCESS (39/39 workflow steps).

## 7. Production PWA static smoke check (read-only)

A read-only HTTP check against `https://app.ammirbuild.com` returned HTTP 200 for the Arabic RTL application shell, `manifest.webmanifest`, `sw.js`, and all three manifest icon assets (`icon-192.png`, `icon-512.png`, `icon.svg`). The manifest parses as JSON and declares standalone display, root start URL/scope, Arabic RTL metadata, and the expected 192/512/SVG icons. The service worker is served successfully and contains the current `ammir-shell-v10-persistent-auth` cache identifier, navigation fallback, `skipWaiting`, and `clients.claim` handling.

This is a static production smoke check only. It does not replace physical Android installation, real authentication/session transitions, private-file access checks, offline retry, or weak-network acceptance. No production data or settings were changed.

## 6. Admin-session navigation regression checks

The browser/static regression suite now also asserts that the revenue/admin navigation state is sourced from the server-side `is_admin` RPC, hidden for non-admin sessions, redirected to the market panel if a non-admin attempts to select an admin/revenue panel, and hidden when the session is cleared. These checks complement the existing server-side revenue dashboard guard; they do not replace acceptance with real administrator and non-administrator accounts.

## 8. Admin navigation guard CI result

The browser/static checks now assert that the admin state is populated by the existing server-side `db.rpc('is_admin')` call, the revenue tab is hidden for non-admin sessions, non-admin attempts to open admin/revenue panels are redirected to the market panel, and revenue navigation is hidden after session clear. An initial test-only assertion used the wrong source-code spelling and failed; the assertion was corrected to match the actual `db.rpc('is_admin').then(result=>` implementation. No application authorization logic was changed by that correction.

Exact code/test head `143b5b2f6c508b600c8d617ff6a01a845d9b8dbe` passed [push run #45513590620](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45513590620) and [pull-request run #45513597608](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45513597608), both SUCCESS (39/39 steps in the push run). The subsequent acceptance-pack documentation update is at `973892f1d7a351ce7b1e14b7b6d7f53490122597`; its CI runs are tracked separately.
