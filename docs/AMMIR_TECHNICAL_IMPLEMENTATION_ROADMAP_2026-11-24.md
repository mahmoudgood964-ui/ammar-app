# عَمِّر | AMMIR — Technical Implementation Roadmap
**Version:** 1.0  
**Date:** 2026-11-24  
**Status:** Audit-based plan; documentation only. No application code or production data changed.

## 1. Executive decision

AMMIR must evolve from its existing construction-project and supplier marketplace into a multi-revenue construction-commerce operating platform. This is an additive evolution of the current product, not a rewrite.

**Non-negotiable engineering rule:** preserve the current production application, existing users, projects, messages, supplier records, commission history, storage objects, and payment-milestone records. Reuse existing tables and workflows wherever possible. No parallel marketplace, duplicate ledger, replacement auth system, or new payment custody layer.

## 2. Audited production baseline

### Application and deployment
- GitHub repository: `mahmoudgood964-ui/ammar-app`.
- Production branch: `main`.
- Current app is a mobile-responsive Arabic-first PWA built around `index.html`, `ammar-marketplace.js`, `ammir-identity.css`, `ammir-analytics.js`, `manifest.webmanifest`, and `sw.js`. Supabase JS v2 is loaded by the current page.
- Vercel project: `ammar-app`; production domains include `app.ammirbuild.com` and `ammar-app.vercel.app`. Latest deployment inspected on 2026-11-24 reported READY.
- The project is not a Next.js/React application. Do not migrate frameworks merely to implement the roadmap.

### Supabase
- Active, healthy production project: `uutwijowzewmvvrzsaww` (region `eu-west-2`, PostgreSQL 17).
- A separate Supabase project `qeqnbcbulptcoszcqdjq` is INACTIVE. Do not use it as the production target.
- Production inspection returned 62 public tables and 46 recorded migrations.
- Existing domains include profiles, projects and project members, tasks, expenses, payments, marketplace suppliers/products/requests/quotes, service providers/requests/offers, agreements, conversations/messages, reviews/disputes, notifications, commission rules/ledger/events, BOQ versions/items, RFQs/invitations/quotes, awards, purchase orders, deliveries/evidence, and visitor analytics.
- Existing workflows already include versioned BOQs and CSV import/export, multi-provider RFQs, quote comparison, split awards, purchase orders, supplier acceptance, delivery dispatch, private evidence, and atomic receipt reconciliation.
- Existing commission tables: `ammar_commission_rules`, `ammar_commission_ledger`, and `ammar_transaction_events`.
- Production commission rules inspected on 2026-11-24: 5% provider-side rules are active for `market_materials`, `contracting`, `engineering`, `maintenance`, and `other`. This is the current configured policy, not a recommendation to charge every new service 5%.
- The existing `project_payment_milestones` and `project_payment_events` tables are explicitly out of scope for changes in this roadmap. Keep their current behaviour and data intact.

### Existing release and acceptance gaps
- Previous handover records show the core workflow has extensive database regression coverage, but real buyer + verified supplier + unrelated-account acceptance remains incomplete.
- Android physical-device and weak-network acceptance remains incomplete.
- Supabase Security Advisor currently reports leaked-password protection disabled (WARN) and an RLS-enabled/no-policy informational finding. Investigate the latter table and confirm whether deny-by-default is intentional; do not add a permissive policy just to silence the notice.
- No new financial, credit, insurance, escrow, or stored-value capability is authorised by this document.

## 3. Product architecture: reuse first

| Capability | Existing foundation | Roadmap action |
|---|---|---|
| Supplier and product marketplace | `ammar_market_suppliers`, `ammar_market_products`, requests and quotes | Extend catalog attributes, supplier tiers and stock freshness without duplicating catalog tables |
| Service marketplace | `ammar_service_providers`, service requests/offers | Add equipment rental, inspection and logistics categories through existing provider model where semantics fit |
| Projects and teams | `projects`, `project_members`, tasks, expenses and related project tables | Extend project workspace; do not create a second project system |
| BOQ and RFQ | `ammir_project_boq_*`, `ammir_project_rfq_*` | Reuse as the procurement source of truth |
| Awards, POs and delivery | `ammir_project_awards`, purchase orders, deliveries and evidence | Add fulfilment service integrations and delivery cost detail additively |
| Agreements and disputes | `ammar_agreements`, `ammar_disputes`, events | Attach terms, service fees and dispute evidence to the existing transaction lifecycle |
| Revenue accounting | `ammar_commission_rules`, `ammar_commission_ledger`, transaction events | Evolve into a unified, auditable revenue subledger; do not create a second ledger |
| Messaging and notifications | Existing conversation and notification tables | Use for RFQ, logistics, verification, payment-partner and service status alerts |
| Analytics | `ammir_visitor_events` and existing analytics | Add transaction and funnel analytics with minimised personal data |

The current application is a large single-page HTML/JavaScript PWA. New modules should initially follow its existing modular JavaScript pattern and shared design system. A later componentisation decision must be based on maintainability evidence, not fashion.

## 4. Target modules and release sequence

### Release 0 — Production acceptance and trust (P0)
**Goal:** prove the current transaction path with real consenting participants before adding more commercial surface area.

1. Buyer account: signup, project, team, BOQ, RFQ, quote comparison, award, PO, delivery, receipt and closeout.
2. Verified supplier account: onboarding, document review, RFQ invitation, quote, award acceptance, PO acceptance, dispatch and evidence.
3. Unrelated account: prove it cannot read or mutate either party's project, quote, message, file, delivery or private evidence.
4. Admin: verify actual admin access, provider approval/rejection, audit history, report moderation and dispute queue.
5. Physical Android and weak-network testing: auth, uploads/downloads, signed URL expiry, Realtime reconnect, retry and offline drafts.
6. Resolve the leaked-password protection setting through Supabase Auth settings after review; do not weaken email confirmation or alter SMTP settings as part of this work.
7. Approve terms, privacy notice, provider agreement, commission disclosure, refund/return, support and dispute procedures with qualified local counsel.

**Exit criteria:** signed acceptance checklist, passing regression suite, no critical access-control defect, and no unresolved production data-loss risk.

### Release 1 — Revenue Foundation (P1)
**Goal:** account for every charge, credit, reversal and settlement before introducing many fee types.

Build a unified revenue model around the existing commission tables:
- Revenue event: immutable source reference, service category, payer, beneficiary, currency, gross basis, fee basis, rate or fixed fee, tax treatment, status, idempotency key and timestamps.
- Ledger entry: accrued, due, paid/settled, overdue, waived, disputed, reversed or refunded.
- Fee policy version: effective dates, market/country, customer segment, service type, payer side, minimum/maximum fee and approval history.
- Statement: period-based supplier/provider commission activity statement with source transaction links and downloadable CSV. Tax invoices remain a separate, jurisdiction-specific capability requiring legal/accounting review.
- Reconciliation: compare AMMIR ledger with partner settlement reports; never mark a fee paid merely because an order is complete. This remains blocked until an actual bank/payment-partner report format and evidence source are selected.

Do not overwrite historical commission rows when policy changes. New policy versions apply only to eligible transactions after their effective date. Use database constraints and transactional RPCs for idempotency and reversals. Do not let the browser calculate or authoritatively set payable fees.

**Current rule:** retain the active 5% provider-side policy for the existing activity types until the owner approves a market-tested replacement. Do not apply it indiscriminately to logistics, advertising, SaaS, finance referrals or enterprise contracts.

### Release 2 — Multi-revenue commerce (P2)
Implement and monetise these streams in order of operational readiness:

1. **Materials transaction fees:** existing marketplace and project procurement. Disclose who pays, what the fee is calculated on, and when it becomes due.
2. **Managed sourcing / bulk procurement:** fixed sourcing fee or negotiated margin only when AMMIR is contractually acting as a sourcing or resale principal. Keep agency and principal accounting separate.
3. **Logistics coordination:** quote comparison, carrier matching, delivery scheduling, proof of delivery, failed delivery, waiting time and return trip. Revenue is a disclosed booking/coordination fee or contracted carrier margin; never hide a markup in the carrier's price.
4. **Supplier business tools:** optional paid plans for catalog imports, multiple staff, analytics, CRM, inventory sync, API, custom storefront and advanced quote workflows. Basic discovery and responding to invited RFQs should remain accessible during network formation.
5. **Promoted placements:** sponsored products and supplier campaigns with clear ad labels, targeting controls, budget caps and campaign reporting. Organic relevance/ranking must remain distinguishable from paid placement.
6. **Inspection and verification:** charge only for a requested, completed inspection or document-verification service; disclose the independent inspector and scope.
7. **Equipment and specialist services:** booking/lead/transaction fees for rental, subcontractors, engineering, maintenance and other verified services.
8. **Enterprise procurement:** annual platform licence, implementation/integration fee, private procurement portal, approval workflows, supplier onboarding and support SLA.
9. **Market intelligence:** paid historical price indices, regional availability and procurement reports based on aggregated, permissioned data. Never sell identifiable buyer/supplier confidential data.

Each stream requires a product owner, fee definition, cost-to-serve calculation, refund rules, tax treatment, legal review and a measurable pilot before general release.

### Release 3 — Differentiating product capabilities (P3)
1. **True Cost:** compare landed cost, not only unit price: item value, freight, loading, unloading, taxes, fees, delivery window, warranty, validity and supplier reliability. Show assumptions and missing fields.
2. **AI BOQ assistant:** extract line items from user-uploaded PDF/Excel/images, preserve source references, flag uncertainty and require user confirmation before publishing an RFQ.
3. **Procurement agent:** convert a natural-language request into structured requirements, ask for missing quantities/specifications/location/date, find eligible providers and draft RFQs. Human confirmation is required before sending or accepting any commercial offer.
4. **Group buying:** aggregate compatible demand while preserving each buyer's separate order, invoice, ownership, delivery, cancellation and refund. Do not pool customer funds.
5. **Material passport:** manufacturer, grade, batch/lot, certificates, test records, origin and chain-of-custody evidence. Never imply verification if the evidence is absent.
6. **Surplus exchange:** resale of unused materials with condition, age, quantity, storage, provenance and buyer acknowledgement.
7. **Supplier reliability:** calculate only from completed, verified, non-disputed transactions; publish methodology and protect against review manipulation.

### Release 4 — Regulated and capital-intensive services (P4)
- Financing, invoice factoring, BNPL, credit and insurance are partner-led only after jurisdiction-specific legal review and a licensed provider agreement.
- Payment initiation, acquiring, wallet, escrow, custody, settlement and stored value require the appropriate licensed payment partner and regulatory approvals.
- AMMIR must not lend its own money, hold client funds, promise credit approval or represent itself as a bank/insurer.
- Cross-border sourcing, customs and trade finance require licensed counterparties, sanctions screening, tax and import/export compliance, and country-specific contracts.

### Release 5 — Multi-country platform (P5)
Make the platform market-aware, not merely translated:
- country and city configuration; currency and FX disclosure; tax rules; units and product standards; local business verification; local terms; permitted payment rails; logistics coverage; language; support hours; dispute and consumer rules.
- Separate tenant/country commercial configuration from shared identity and platform code.
- Launch one city and one focused material/service category at a time, with a local operating partner and a verified supplier base.
- Do not open Saudi Arabia, UAE, Egypt, Kenya or Nigeria until local supplier density, successful orders, repeat purchase, fulfilment reliability and contribution margin meet pre-agreed gates.

## 5. Revenue policy and unit economics

AMMIR should not maximise the number of fees per transaction. It should maximise **transparent contribution margin per successfully completed customer journey**.

For every service, calculate:
- Gross merchandise value (GMV) — value of goods/services transacted; not AMMIR revenue.
- Gross revenue — commission, subscription, logistics, inspection, advertising, enterprise and partner-referral revenue actually earned.
- Direct cost — payment partner charges, carrier/inspection costs borne by AMMIR, refunds, support and fulfilment operations.
- Contribution margin — gross revenue less direct variable costs.
- Operating profit — after payroll, technology, marketing, legal, admin and other overhead.

Pricing experiments must compare conversion, repeat rate, gross revenue, contribution margin, refund/dispute rate and supplier retention. A fee that raises nominal revenue but destroys liquidity or conversion is not a win.

### Proposed fee configuration dimensions (not preset rates)
- Country/city.
- Category and material/service type.
- Transaction value band.
- Buyer/supplier/other payer.
- Agency vs principal role.
- Fulfilment method and logistics distance.
- Enterprise vs SME account.
- Fixed fee, percentage, tiered fee, subscription, campaign budget or contracted service fee.
- Effective date, tax, minimum/maximum, cap, refund/reversal handling.

All fees must be visible before a party accepts a quote, order, booking or service.

## 6. Database and security implementation rules

1. Start with a schema and dependency map for existing tables; never create a parallel set for suppliers, orders, RFQs, projects, conversations or commissions.
2. Every new exposed table must have RLS enabled and explicit least-privilege grants/policies.
3. Never use user-editable `user_metadata` for authorization. Use trusted server-side role records or app metadata with refresh-aware checks.
4. Avoid `SECURITY DEFINER` unless there is a documented reason; lock search_path, restrict EXECUTE, validate auth.uid() and run Supabase Advisors.
5. Use `SECURITY INVOKER` by default; privileged financial operations must be transactional and server-controlled.
6. Never accept authoritative fee, status, payer, currency conversion or settlement values from browser input.
7. Use idempotency keys and unique source references to prevent duplicate charges.
8. Record reversals as new compensating ledger events; do not delete or rewrite financial history.
9. Keep private documents and delivery evidence in private storage with short-lived signed URLs and ownership checks.
10. Preserve the existing payment milestone tables and defer any work on their bank-payment stage logic unless the owner explicitly reopens it.
11. Do not expose service-role credentials or financial secrets to the browser.
12. Run schema diff, regression tests, RLS tests, advisors and rollback review before applying any migration.

## 7. Frontend implementation rules

- Keep current PWA entry point and navigation working.
- Add modules behind feature flags or role/market visibility; do not expose unfinished financial products.
- Keep buyer, supplier, service provider, carrier, inspector and admin views task-focused.
- Maintain Arabic RTL and English LTR, responsive mobile layouts, accessible forms and clear empty/error/loading states.
- Avoid a single overloaded dashboard. Use a shared design system with separate workspaces and consistent transaction identifiers.
- AI features must cite source documents/fields and mark extracted or estimated values; no synthetic stock, price, delivery or supplier data.

## 8. KPIs and release gates

### Marketplace liquidity
- Verified active suppliers per city/category.
- RFQ response rate and median response time.
- Quotes per RFQ.
- RFQ-to-award conversion.
- Award-to-accepted-PO conversion.
- PO-to-completed-delivery rate.
- Repeat buyer rate and repeat supplier rate.

### Trust and operations
- Verification turnaround.
- On-time delivery.
- Complete/short/damaged delivery rate.
- Dispute rate and resolution time.
- Refund/reversal rate.
- Evidence completeness.

### Revenue quality
- GMV (reported separately).
- Revenue by stream and country.
- Revenue per completed transaction.
- Contribution margin per stream.
- Supplier subscription retention.
- Advertising renewal.
- Enterprise contract renewal.
- Aged receivables and settlement reconciliation variance.

### Launch gates
No new market launch based solely on registrations or app downloads. Require verified suppliers, active demand, real completed transactions, acceptable fulfilment/dispute levels, repeat usage and positive or explicitly budgeted contribution economics.

## 9. Immediate execution backlog

| Priority | Work item | Depends on | Done when |
|---|---|---|---|
| P0.1 | Reconfirm production branch/deployment and current PR/commit state | GitHub + Vercel | Baseline recorded |
| P0.2 | Buyer/supplier/unrelated-account acceptance | Real consenting test participants | All access and lifecycle tests pass |
| P0.3 | Admin queue and dispute workflow acceptance | Verified admin account | Approval, rejection, audit and dispute flows pass |
| P0.4 | Android/weak-network acceptance | Physical Android device | Upload, download, reconnect and offline draft checks pass |
| P0.5 | Auth leaked-password protection review | Supabase Auth settings | Setting enabled and tested without changing confirmation/SMTP |
| P1.1 | Map current commission trigger/RPC lifecycle and source references | Existing commission tables | No duplicate/incorrect accrual paths |
| P1.2 | Revenue ledger gap analysis and event taxonomy | P1.1 | Signed schema design; no production DDL yet |
| P1.3a | Read-only monthly payer commission statement and CSV export | Existing ledger + append-only adjustments | Implemented on PR #14; UTC month boundaries, payer RLS and per-currency totals; awaiting real-account acceptance |
| P1.3b | External settlement reconciliation | Bank/payment-partner settlement report format + legal/accounting review | Match by stable reference, currency and amount; unmatched/partial/duplicate cases reviewed; never auto-mark paid without evidence |
| P2.1 | Logistics partner and cost model pilot | Real carrier quotes | Delivered jobs and positive unit economics |
| P2.2 | Optional supplier business tools pilot | Supplier interviews | Paid conversion and retention measured |
| P2.3 | Sponsored placement experiment | Sufficient organic inventory | Ads clearly labelled; no ranking integrity harm |
| P3.1 | True Cost MVP | Structured quote/delivery data | Comparable landed-cost display with transparent assumptions |
| P3.2 | AI BOQ extraction prototype | Document handling and review UX | Human-confirmed extraction; regression tests |
| P4.1 | Licensed finance/payment partner discovery | Local legal review | Written partner scope and compliance approval |
| P5.1 | UAE/Saudi market entry research | Home-market pilot metrics | City-level partner and category case approved |

## 10. Change control and delivery protocol

Every implementation PR must contain:
1. Scope and user-visible behaviour.
2. Existing tables/files reused and any new schema justified.
3. Migration and rollback plan, if applicable.
4. RLS and privilege analysis.
5. Regression tests and negative-access tests.
6. Preview deployment tied to exact commit.
7. Real-user acceptance evidence where the feature needs it.
8. Concise release notes and operational monitoring.

**Do not merge or deploy unfinished financial features to production.** Documentation can be merged independently; code and schema changes must follow the release gates above.

## 11. First recommended engineering slice

The first feature slice after P0 is not AI or financing. It is **Revenue Foundation**:
- map exactly how current 5% provider-side commission accrues for the existing categories;
- verify idempotency, refunds, partial deliveries, disputes and reversals;
- generate supplier/provider statements from the existing ledger;
- add service-specific fee configuration only after cost and legal review;
- expose clear fee disclosures before acceptance.

This creates the accounting spine needed for logistics, inspections, subscriptions, ads, enterprise services and partner referrals without losing financial integrity.

---
**Owner decision required before any new production migration:** approve the detailed revenue event taxonomy, fee payer and settlement method for each new stream. Existing production rules remain unchanged until then.


## 10.1 Release 1 execution update — 2026-11-25

The feature branch now contains a payer-facing monthly commission activity statement and CSV export. It reports commission ledger rows and append-only adjustment events separately, includes per-currency period totals, source transaction references, adjustment reasons, and an explicit UTC reporting period. The UI is read-only and relies on the existing payer/admin RLS policy.

The latest application/test head passed GitHub Actions run #45516582618 (39/39 steps). This run uses disposable CI PostgreSQL; it does not apply migrations to production. PR #14 remains open and draft. No production deployment or production migration has occurred.

**Still not implemented:** external settlement reconciliation, tax invoices, bank matching, and cash-collection confirmation. These cannot be responsibly fabricated: they require a real settlement-report schema/sample, a stable external transaction reference, a designated reconciliation operator, and review of local accounting/tax requirements. Until those inputs exist, AMMIR must not infer cash settlement from an order or ledger status.
