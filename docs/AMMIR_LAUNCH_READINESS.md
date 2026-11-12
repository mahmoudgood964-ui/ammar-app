# AMMIR — Launch Readiness Review

**Review date:** 12 November 2026  
**Environment:** Production + isolated staging  
**Release branch under review:** `launch/ammir-trust-hardening`

## Executive verdict

**AMMIR is deployed, but it is not ready for a full public launch**

The deployed product is a real working application shell with project management, marketplace, supplier/service profiles, quotes, agreements, and messaging modules. However, a successful deployment and the presence of database tables do not prove that real users can safely complete every workflow

The most important issue found during this review was that suppliers and service providers could set their own `is_verified` and `verified_at` fields under the existing owner RLS policy. This review created a separate hardening branch, added database triggers, added admin-only moderation controls, added an audited verification workflow, and applied the SQL changes to the isolated staging project

Those changes are **not yet in production**. They must pass the new CI integration tests and code review before deployment

## Verified production evidence

| Check | Observed result |
|---|---|
| Production alias | `https://ammar-app.vercel.app` |
| Home page response | HTTP 200 |
| Document title | `عَمِّر | AMMIR` |
| Production deployment | Vercel `READY` |
| Production source branch | `main` |
| Public tables in production | 46 |
| Public tables with RLS enabled | 46 |
| Configured storage buckets | 4 |
| PWA manifest, service worker, marketplace JS, icon | HTTP 200 |
| Supabase status | `ACTIVE_HEALTHY` |
| Registered app profiles inspected | 2, both currently have role `client` |
| Admin account | Not present in the profiles inspected |

This proves hosting and schema availability. It does not prove end-to-end sign-up, role isolation, purchase completion, file access, real-time delivery, or Android behavior

## Application coverage by stakeholder

| Stakeholder | Existing workflows | Launch status |
|---|---|---|
| Property/project owner | Projects, costs, tasks, team, requests, quotes, agreements, reports and handover checklist | Partial acceptance testing required |
| Project manager | Team workflow, task updates, comments, decisions, reports and change orders | Role-specific permission tests required |
| Contractor/service provider | Profile, service requests, offers, agreements and completion actions | Verification and live transaction tests required |
| Materials supplier | Supplier profile, product catalogue, requests and quotations | Verification guard and workflow tests required |
| Procurement/accounting | Budgets, expenses, purchase/quote records and commission ledger | Reconciliation and permission tests required |
| Site supervisor/technician | Site reports, photos, issues, tasks and handover checks | Android and attachment tests required |
| AMMIR operations administrator | Verification, reports and dispute review | New admin console exists on hardening branch; an owner-approved admin account is still needed |

## New security work on `launch/ammir-trust-hardening`

### 1. Provider self-verification prevention
A database trigger now:
- Forces new authenticated supplier/provider records to remain unverified
- Blocks owners from changing verification flags or timestamps
- Prevents owners from setting their own account status to `suspended`
- Allows administrator decisions through a guarded database routine
- Preserves backend/service operations with no end-user identity

### 2. Admin-only moderation access
The branch adds administrator-only read/update policies for supplier/provider review, message reports, disputes, transaction events and the commission ledger. The new report-review RPC returns only the message linked to a report, not every message in every conversation

### 3. Audited verification decisions
A new append-only table records:
- Entity type and entity ID
- Owner ID and business name snapshot
- Decision and reason
- Optional evidence reference
- Administrator identity and timestamp

The database RPC requires an administrator, validates the decision, requires a reason, locks the target profile, applies the decision and records the audit event within one transaction

### 4. Initial administration interface
The new branch adds an administrator-only tab for supplier/provider review, message-report review, dispute status and verification history. The production users inspected do not yet include an administrator, and the tab remains hidden for non-admin accounts

### 5. Staging status
The two hardening migrations have been applied to isolated staging:
- `ammir_trust_and_admin_access`
- `ammir_provider_verification_audit`

Read-only verification found two trust triggers, eleven admin policies from the first migration, and the report review RPC. The second migration adds the provider verification audit table and guarded review routine

**Do not deploy to production until the new workflow succeeds and the SQL tests are reviewed**

## P0 — Required before a controlled pilot

1. **CI regression suite:** prove that ordinary supplier/provider owners cannot self-verify, self-suspend or call administrator routines; prove that an administrator can verify with a reason and audit entry; prove that only reported message content is available in the moderation review RPC
2. **Deploy hardening to production:** only after CI, peer review and a fresh staging check
3. **Choose the administrator account:** identify the account by its registered email in a separate owner-confirmed step; never promote an account based on guesswork
4. **Three-account security test:** use a buyer, a supplier and an unrelated outsider to test project, request, quote, agreement, file, message and dispute access
5. **Real Auth tests:** registration, email confirmation, sign-in, sign-out, reset, expired session, duplicate signup and invite acceptance
6. **Storage tests:** upload, signed read, expiration, denied cross-user download, unsupported MIME type, oversize file and deletion rules
7. **Realtime tests:** new message, notification, read receipt, reconnect after network loss and app background/resume
8. **Android acceptance:** test at least one low-memory phone, small screen, browser install, camera/file picker, interrupted uploads, and poor network
9. **Legal and operational readiness:** terms, privacy notice, provider verification criteria, complaint and dispute procedure, support contact, data retention and incident escalation

## P1 — Build a defensible procurement product

These features are more important than adding decorative modules

### Bill of Quantities (BOQ)
A project should hold structured items with specification, category, unit, quantity, location/phase, approved version, revision history and attachments. Imported spreadsheets need column validation, duplicate detection and a preview before acceptance

### Multi-supplier Request for Quotation (RFQ)
A buyer should be able to prepare one specification and invite multiple verified suppliers. Each supplier sees only its own recipient record and quote submission, not competitors' quotes or private buyer notes

### Comparable bid evaluation
Compare like-for-like line items, unit rates, quantities, availability, validity, transport, loading, taxes, delivery time, warranty and exclusions. Do not rank solely by lowest headline price

### Split awards
Permit the buyer to award different lines to different suppliers with explicit approval, totals, reasons and separate order references

### Delivery and receipt reconciliation
Capture shipment quantity, received quantity, damaged/short quantities, photo evidence, recipient/time, delivery note, location when voluntarily provided, and a signed reconciliation record

### Supplier quality and performance
Calculate performance from completed, verifiable transactions: on-time delivery, fill rate, quality disputes, response time and buyer reviews. Do not use unverified self-reported scores as proof

## P1 — Communications and service reliability

- Complete English translation of every view and system message
- User-configurable push and email notifications with delivery logs and retry policy
- Group conversations tied to projects and procurement requests, with clear participant permissions
- Full conversation search, data export and moderation escalation
- Service-level reminders for RFQs, quotes, delivery and unresolved issues
- Better file preview, compression and resumable uploads for low-bandwidth connections

## P2 — Scale and market expansion

- Supplier price/availability history and region-level analytics based only on real transactions
- Product substitutions and specification equivalence with buyer approval
- Multiple currencies and explicit exchange-rate snapshots where appropriate
- Procurement reporting by project, category, city, vendor and budget variance
- Offline drafts and safe sync queues; no silent overwrites
- Integration APIs for established construction, accounting and logistics providers

## Security, infrastructure and cost decisions

- The browser currently uses a Supabase publishable client key. No service-role or secret key marker was found in the inspected public application files
- Vercel environment-variable listing currently returns no project variables; the current static client config is embedded in the frontend. This is acceptable only for the public URL and publishable key, never for secrets
- The frontend imports Supabase JS from an unpinned major-version CDN URL. Pin an explicit reviewed version and test upgrades
- Current Supabase Security Advisor reports an authenticated SECURITY DEFINER warning family. Review each business RPC individually: keep only functions that require privilege elevation, verify authorization checks, lock search paths, revoke unnecessary grants and test as buyer/provider/outsider
- Leaked-password protection is currently flagged as disabled. Supabase documents this feature as Pro plan and above; enable it in Auth settings if the project plan permits it
- Current project hosting is on Vercel Hobby. Confirm expected usage, deployment protection, bandwidth and limits before the public campaign
- Backups, recovery drills, database monitoring, error alerts and incident contacts must be documented before handling high-value business activity

## Money, commission and regulated activities

AMMIR does not receive, hold, transfer or safeguard customer money. Current payment-related tables record project payment information, business events and commission ledger entries. They are not a payment rail or escrow service

The 5% rule previously present is a technical default only, not an approved tariff. Do not publish it as the final fee. Any payment processing, escrow, bank transfer, credit or financing product requires a licensed provider, written commercial agreement and regulatory review

The deferred bank milestone feature is outside this release. The tables `project_payment_milestones` and `project_payment_events` must remain untouched unless explicitly reopened by the owner

## Launch sequence that can generate real attention

### Stage 1 — Proof before publicity
- Recruit a small founding cohort of actual property owners, contractors and building-material suppliers
- Obtain explicit consent and verify the first participants
- Process a small number of real but low-risk requests end-to-end
- Track response time, quote completeness, delivery variance, disputes and user feedback

### Stage 2 — Demonstrate the transaction
Publish a short product walkthrough showing a real permitted workflow: project → specification → RFQ → competing offers → documented decision → delivery/receipt → project cost record

Do not use fabricated prices, stock, supplier logos, customer quotes, project outcomes or market statistics

### Stage 3 — Public launch
- Publish separate landing paths for property owners, project managers, contractors and suppliers
- Launch a concise demonstration video and a clear product explanation
- Use verified pilot case studies and attributable customer quotes
- Provide a visible support route and fast issue response
- Invite vendors through direct business channels and industry associations, not mass spam

### Launch success metrics
Track:
- Verified active suppliers and contractors by city/category
- Percentage of RFQs receiving at least two comparable offers
- Median time to first valid quote
- Quote-to-order conversion
- On-time/full delivery rate
- Dispute rate and resolution time
- Repeat request rate
- Percentage of transactions with documented receipt

The launch story should be built around measured improvement, not a list of screens

## Final release decision

**Current state: deployed production prototype / controlled-pilot candidate after P0 closure, not a broad-market launch**

The next gate is CI and review of `launch/ammir-trust-hardening`, followed by real account-based acceptance tests and an approved admin account. After that, build BOQ, multi-supplier RFQ, comparable bids and delivery reconciliation before promising a complete construction procurement network
