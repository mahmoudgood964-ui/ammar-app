# AMMIR Release Acceptance Pack — 2026-11-24

**Purpose:** one operational checklist for closing Release 0 (production trust) and validating Revenue Foundation v1 without risking production.
**Status:** prepared on the feature branch. This document is not evidence that human acceptance, legal approval, or mobile-device testing has occurred.

## 1. Verified technical baseline

- Repository: `mahmoudgood964-ui/ammar-app`; production branch: `main`.
- Revenue implementation PR: #14, branch `feature/ammir-revenue-engine-v1`.
- Latest code-and-test head verified for this pack: `208cce64edbc3cbd1d555cba0d486e92e6c2e262`.
- Vercel preview for that code head: `https://ammar-g4qgekozx-mahmoudgood964-ui.vercel.app` (READY; preview only). A documentation-only refresh may advance the branch head without changing the tested application code.
- Supabase production project: `uutwijowzewmvvrzsaww`, ACTIVE_HEALTHY, PostgreSQL 17.
- Production migration history does not contain `20261124211500` or `20261124230000`.
- No Supabase development branches exist; to avoid recurring compute charges, revenue migration tests now run in an ephemeral PostgreSQL 17 service container inside GitHub Actions instead of a paid Supabase branch.
- Production schema/data were not changed during this work.

## 2. CI failure and correction

The workflow run associated with the previous PR head (`797705962acdb70db79826b6407ffc10c593a29f`) completed with failure. All preceding database, trust/admin, marketplace, messaging, storage, RLS, and private-RPC steps shown in that run completed successfully. The final static application check failed because it hard-coded the old Service Worker cache name `ammir-shell-v9-identity-first-load`, while both `main` and the feature branch already use `ammir-shell-v10-persistent-auth`.

The test was corrected on this feature branch to assert a versioned AMMIR shell cache-name pattern rather than one obsolete literal. This is a test-maintenance correction, not a change to the Service Worker or its cache behaviour. A fresh green workflow run confirmed the correction: [GitHub Actions run #45489721782](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45489721782), commit `d3a216036a129279cb7c9eb3377641280b182e5a` (SUCCESS). The expanded fee-decrease, invalid-input and same-key concurrency tests were then run on `34d3dbb9b1179d1bdbad03aa260fcb14d0168e2e`; both [push run #45492304272](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45492304272) and [pull-request run #45492316397](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45492316397) completed SUCCESS. Additional tests for blank/NULL inputs, original-ledger immutability and legacy payment-table fixture isolation were added. The latest code head `8c02a9e0cd83eb4788e0a5b5dca926857812d0fd` then passed both [push run #45493387107](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45493387107) and [pull-request run #45493400405](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45493400405), with all workflow steps green. The revenue CSV export was then hardened against spreadsheet-formula injection in untrusted text fields, including formulas preceded by whitespace; numeric amount columns remain numeric text. The current code head `208cce64edbc3cbd1d555cba0d486e92e6c2e262` passed [push run #45493781094](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45493781094) and [pull-request run #45493795458](https://github.com/mahmoudgood964-ui/ammar-app/actions/runs/45493795458), with all workflow steps green.

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
- [x] Payer can read their own adjustment rows; unrelated payer cannot (CI fixture). Admin-read path is covered by policy/schema assertions; full UI/admin account acceptance remains open.
- [x] Concurrent reductions with distinct keys cannot reduce net commission below zero (two-session CI test).
- [x] Concurrent replay with the same key produces one logical adjustment (two-session CI test; both calls succeed and exactly one row is recorded).
- [x] Original ledger fixture gross amount, currency, rate, commission amount, payer and status remain unchanged after adjustments; legacy payment milestone/event fixtures remain empty (CI assertion).

### Paid-ledger trigger protection

- [x] Delivery commission row is created on the tested fully received delivery path (CI fixture). Partial-receipt commission behavior remains separately unverified.
- [ ] Editing a non-paid delivery updates the corresponding non-paid ledger row as expected.
- [x] Editing a paid delivery does not change paid gross amount, commission amount, rate, payer, or paid status (CI fixture; currency remains part of the unchanged ledger row but was not separately mutated).
- [ ] Removing a delivery item does not rewrite a paid row's financial values.
- [x] Delivery status leaving received states does not void a paid row (CI cancellation-path fixture).
- [x] Service-award commission is created on the tested existing award-completion path (CI fixture).
- [x] Repeated delivery/service-award trigger paths preserve the same paid ledger row (CI fixture).
- [ ] Existing award-with-delivery duplicate prevention remains intact.
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
| PR #14 | Open / draft; mergeable at latest check; tested code head `208cce6` | CI green #45493781094 (push) and #45493795458 (PR); no review submissions or inline review threads were present at latest check; explicit release decision still required |
| Vercel preview | READY for code head `208cce6` | Manual UI acceptance; preview is not production |
| New SQL migrations | Both migrations applied and tested only in ephemeral GitHub Actions PostgreSQL 17; not applied to production | Review rollback and complete remaining trigger edge cases (non-paid delivery update, delivery-item removal, award-with-delivery duplicate guard); then explicit release decision |
| P0 buyer/supplier/unrelated user | Not evidenced complete | Real consenting test accounts and evidence |
| P0 admin/disputes | Not evidenced complete | Real admin test evidence |
| P0 Android/weak network | Not evidenced complete | Physical device test record |
| Auth leaked-password protection | Previously reported disabled | Setting review and post-change auth regression |
| Local legal approval | Not evidenced complete | Qualified local counsel approval |
| P2–P5 | Not implemented as full releases | Pilot/partner/compliance gates above |

**Production safety rule:** do not merge/deploy financial code or apply either migration until CI is green, the safe-database matrix passes, rollback is reviewed, and the owner explicitly approves the release. Preserve existing payment milestone logic and all historical financial data.
