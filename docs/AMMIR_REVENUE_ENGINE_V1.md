# AMMIR Revenue Engine v1 — Admin Ledger Dashboard

**Status:** implementation on feature branch; not yet merged or deployed to production.  
**Scope:** read-only administrative reporting on the existing commission ledger.

## What changed
- Added an admin-only **الإيرادات** tab to the existing marketplace workspace.
- Uses the existing `is_admin()` RPC for UI visibility and a second client-side admin guard before loading/exporting.
- Reads the existing `ammar_commission_ledger` and `ammar_commission_rules` tables; no parallel ledger, no duplicate commission source, no new financial write path.
- Shows loaded-record counts, GMV basis separately from commission revenue, amounts grouped by currency and ledger status, current commission rules, and the latest 100 ledger records.
- Adds CSV export for the loaded ledger records with UTF-8 BOM and standard CSV escaping.

## Important accounting boundaries
- GMV / `gross_amount` is the underlying transaction basis, not AMMIR revenue.
- `commission_amount` is the commission amount recorded in the current ledger, not automatically cash received.
- Only rows with status `paid` are labelled "paid/settled according to ledger status". This is not independent bank or payment-provider reconciliation.
- Values are not combined across currencies.
- Dashboard reads at most 2,000 newest ledger rows. It displays the loaded count and database count to avoid implying full history when the result is capped.
- Current active 5% provider-side rules remain unchanged. No new rates or service categories are introduced.
- The dashboard does not modify rules, ledger entries, settlement status, payment milestones, or customer funds.

## Existing production data protection
No schema changes or SQL migrations are included in this slice. Existing commission tables, triggers, RLS policies, project payment milestones, payment events, and historic financial rows remain untouched.

## Acceptance checklist
1. Sign in as a verified AMMIR admin. Confirm the new tab appears.
2. Sign in as a non-admin. Confirm the new tab remains hidden and direct tab selection fails the `isAdmin` guard.
3. Confirm the dashboard shows separate totals for each currency.
4. Confirm GMV and commission revenue are displayed as different measures.
5. Confirm each of the five existing ledger statuses is counted separately.
6. Confirm existing activity rules are displayed without changing any rate.
7. Export CSV; verify Arabic text opens correctly, every row has 12 columns, commas/quotes are escaped, and no formula values are injected.
8. Verify the dashboard does not display another user's private ledger rows to a non-admin. Existing RLS remains the data access boundary.
9. Test empty ledger, 2,000+ records, null settled_at, and mixed currencies.
10. Run the full existing marketplace and project procurement regression suite before merge.

## Next slice — full financial foundation
Before adding new revenue streams, design and review (without deploying blindly):
- versioned fee-policy records by market, activity, payer, fee type, basis, effective period, limits and tax treatment;
- immutable revenue events and compensating reversals;
- partial refunds and adjustments;
- supplier/provider statements and period close;
- settlement reconciliation against actual payment-provider reports;
- idempotency and unique source references;
- secure admin-only policy management and server-authoritative fee calculation.

Do not apply new fees to logistics, advertising, subscriptions, financing referrals or enterprise contracts until the service has an approved contract, cost model, refund policy, tax treatment and legal review.
