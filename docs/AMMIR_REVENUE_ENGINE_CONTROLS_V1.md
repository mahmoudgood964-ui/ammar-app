# AMMIR Revenue Engine — Commission Controls v1

**Status:** drafted in feature branch; database migration has not been applied to production.  
**Migration:** `20261124211500_add_ammir_commission_adjustments.sql`

## Audit findings from the live schema
- The commission ledger currently stores the original commission amount and a status; it has no adjustment/reversal relationship.
- Delivery commission is synchronized from delivery and delivery-item changes. Its upsert can update the financial amount of a row whose status is already `paid`, while retaining the paid status. This is an accounting integrity defect.
- Delivery status transitions outside the received states can set unpaid rows to `void`, but paid rows remain marked paid; there is no linked compensating adjustment.
- Award completion can create a commission row when no delivery exists. If a delivery is present, that award path intentionally skips the commission to avoid duplication.
- Ledger uniqueness currently exists on request_id and (source_type, source_id). The current design is source-level, not a complete journal of corrections.
- Current ledger RLS lets a payer see their own row and administrators see all. Existing transaction events are request-scoped and are not a financial adjustment journal.
- No live commission ledger rows were returned during this audit, so there is no historical commission balance to reconcile at this point in time.

## What this migration adds
- An append-only `ammar_commission_adjustments` table linked to the existing commission ledger.
- Four explicit adjustment kinds: partial refund, full reversal, fee increase, fee decrease.
- Signed adjustment amounts; reduction types are negative, increase is positive.
- Required reason and globally unique idempotency key.
- Currency matching and a row lock on the original commission record to prevent concurrent over-adjustment.
- A full reversal must equal the remaining commission balance; a reduction cannot exceed that balance.
- Retry-safe behavior: replaying the same idempotency key and payload returns the original adjustment ID; reusing the key with a different payload is rejected.
- Immutable records: UPDATE and DELETE are rejected. Corrections must be new compensating adjustments.
- Payer/admin read access through RLS; only the administrator RPC can insert adjustments.

## Explicit limits
- This does not mark a commission as cash-refunded or settle a bank/payment-provider transaction.
- It does not alter the original commission ledger row or its status.
- It does not modify the 5% active rules.
- It does not create wallet, escrow, lending, payout, payment-custody, or bank milestone behavior.
- It does not yet automatically create adjustments when a delivery is edited after commission settlement. That trigger change needs its own reviewed patch and acceptance tests so that delivery workflows are not broken.
- Supplier statements and actual payment-provider reconciliation are subsequent slices.

## Required test cases before applying
1. Non-admin cannot call the adjustment RPC.
2. Admin can record a valid partial refund; signed delta is negative.
3. Admin can record a valid fee increase; signed delta is positive.
4. A full reversal must equal the remaining balance.
5. Cumulative reductions cannot exceed the original commission less prior adjustments.
6. Currency mismatch is rejected.
7. Replaying the same idempotency key and payload returns the same ID without inserting another row.
8. Reusing an idempotency key with different payload is rejected.
9. UPDATE and DELETE are rejected.
10. Payer can read adjustments for their own commission row; unrelated payer cannot; admin can read all.
11. Concurrent reductions cannot drive net commission below zero.
12. Original commission row, status, project payment milestones, and payment events remain unchanged.

## Follow-up critical fix
The live delivery commission trigger currently permits financial fields to be overwritten on a row already marked paid. Before the first real paid commission is recorded, change that trigger so it never rewrites a paid ledger row. Subsequent differences must be captured through append-only adjustment entries and reconciled against payment-provider records. Do not silently preserve a paid status while changing its amount.
