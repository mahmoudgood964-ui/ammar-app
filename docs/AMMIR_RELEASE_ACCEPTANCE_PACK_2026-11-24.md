# AMMIR Release Acceptance Pack — 2026-11-24

**Purpose:** one operational checklist for closing Release 0 (production trust) and validating Revenue Foundation v1 without risking production.
**Status:** prepared on the feature branch. This document is not evidence that human acceptance, legal approval, or mobile-device testing has occurred.

## 1. Verified technical baseline

- Repository: `mahmoudgood964-ui/ammar-app`; production branch: `main`.
- Revenue implementation PR: #14, branch `feature/ammir-revenue-engine-v1`.
- Current feature head at preparation: `0ef45b561a104857f33f76ffda48372120e86b6c`.
- Vercel preview for that head: `https://ammar-eyhmm5upm-mahmoudgood964-ui.vercel.app` (READY; preview only).
- Supabase production project: `uutwijowzewmvvrzsaww`, ACTIVE_HEALTHY, PostgreSQL 17.
- Production migration history does not contain `20261124211500` or `20261124230000`.
- No Supabase development branches exist; to avoid recurring compute charges, revenue migration tests now run in an ephemeral PostgreSQL 17 service container inside GitHub Actions instead of a paid Supabase branch.
- Production schema/data were not changed during this work.

## 2. CI failure and correction

The workflow run associated with the previous PR head (`797705962acdb70db79826b6407ffc10c593a29f`) completed with failure. All preceding database, trust/admin, marketplace, messaging, storage, RLS, and private-RPC steps shown in that run completed successfully. The final static application check failed because it hard-coded the old Service Worker cache name `ammir-shell-v9-identity-first-load`, while both `main` and the feature branch already use `ammir-shell-v10-persistent-auth`.

The test was corrected on this feature branch to assert a versioned AMMIR shell cache-name pattern rather than one obsolete literal. This is a test-maintenance correction, not a change to the Service Worker or its cache behaviour. A fresh green workflow run is still required to confirm the correction.

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

- [ ] Anonymous caller cannot execute the RPC.
- [ ] Authenticated non-admin cannot execute the RPC.
- [ ] Admin can create a valid partial refund; delta is negative.
- [ ] Admin can create a valid fee decrease; delta is negative.
- [ ] Admin can create a valid fee increase; delta is positive.
- [ ] Full reversal must equal the remaining balance after prior adjustments.
- [ ] Reduction exceeding remaining balance is rejected.
- [ ] Currency mismatch is rejected.
- [ ] Missing/short reason, malformed key, zero/negative amount, and >2-decimal amount are rejected.
- [ ] Same idempotency key + same payload returns the same adjustment ID and creates one row.
- [ ] Same idempotency key + different payload is rejected.
- [ ] UPDATE and DELETE are rejected by the immutable trigger.
- [ ] Payer can read their own adjustment rows; unrelated payer cannot; admin can read all.
- [ ] Concurrent reductions with distinct keys cannot reduce net commission below zero.
- [ ] Concurrent replay with the same key produces one logical adjustment.
- [ ] Original ledger amount/status and payment milestone/event rows remain unchanged.

### Paid-ledger trigger protection

- [ ] Delivery commission row is created correctly for received/partially received delivery.
- [ ] Editing a non-paid delivery updates the corresponding non-paid ledger row as expected.
- [ ] Editing a paid delivery does not change paid gross amount, commission amount, rate, currency, payer, or paid status.
- [ ] Removing a delivery item does not rewrite a paid row's financial values.
- [ ] Delivery status leaving received states does not void a paid row.
- [ ] Service-award commission is created only on the existing supported award-completion path.
- [ ] Repeated trigger execution is idempotent and does not duplicate ledger rows.
- [ ] Existing award-with-delivery duplicate prevention remains intact.
- [ ] No payment milestone, payment event, commission rate, or historical ledger row is modified.

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
| PR #14 | Open / draft at pack creation | Fresh CI green, review, merge decision |
| Vercel preview | READY for feature head | Manual UI acceptance; preview is not production |
| New SQL migrations | Not applied to production | Safe-database SQL matrix and rollback review |
| P0 buyer/supplier/unrelated user | Not evidenced complete | Real consenting test accounts and evidence |
| P0 admin/disputes | Not evidenced complete | Real admin test evidence |
| P0 Android/weak network | Not evidenced complete | Physical device test record |
| Auth leaked-password protection | Previously reported disabled | Setting review and post-change auth regression |
| Local legal approval | Not evidenced complete | Qualified local counsel approval |
| P2–P5 | Not implemented as full releases | Pilot/partner/compliance gates above |

**Production safety rule:** do not merge/deploy financial code or apply either migration until CI is green, the safe-database matrix passes, rollback is reviewed, and the owner explicitly approves the release. Preserve existing payment milestone logic and all historical financial data.
