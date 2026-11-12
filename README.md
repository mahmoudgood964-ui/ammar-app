# عَمِّر | AMMAR

AMMAR is a bilingual (Arabic/English) workspace for managing renovation and property-maintenance projects, from project setup through field execution and handover.

## Current capabilities

- Account registration, sign-in and password recovery through Supabase Auth.
- Project creation, updates, search and shared project access.
- Team invitations, role-based access and activity history.
- Tasks, progress updates, contractor quotations and structured quotation comparison.
- Expenses, budgets, payments and CSV project exports.
- Private project documents and signed downloads through Supabase Storage.
- Daily site reports, issue/defect tracking, scope-change approvals and handover checklists.
- Supplier profiles, self-managed construction-material listings, regional catalog, purchase requests and supplier quotations (after the ecosystem migration is applied).
- Private customer/supplier conversations with text and file/image attachments, read receipts, notifications and project-linked purchase requests.
- Service-provider profiles and service requests, agreement records with dual-party acceptance timestamps, dispute/review records and configurable commission rules.
- Bank-referenced milestone workflow with customer completion approval, dispute holds and payout audit records (AMMAR does not custody or transfer funds).
- Arabic/English interface switching.
- Installable PWA shell.
- Supplier marketplace for construction materials with supplier-managed prices, availability, product images and regional catalog.
- Project-linked purchase requests, supplier quotations, order status, delivery confirmation and purchase expense recording.
- Private in-app customer/supplier messaging with attachments, unread notifications and realtime updates.
- Contractor and service-provider profiles, service requests, offers, two-party agreements, completion confirmation and reviews.
- Configurable transaction commission ledger (5% initial default); commission entries are accounting records only and do not collect or transfer funds.

## Technology

- Static HTML, CSS and JavaScript in `index.html`.
- Supabase Auth, Postgres, Row Level Security and Storage.
- Vercel hosting.
- PWA manifest, service worker and SVG application icon.

## Database migrations

Apply the migrations in order in the Supabase SQL Editor, only once per environment:

1. `202611120001_project_management.sql`
2. `202611120002_part1_schema.sql`
3. `202611120002_part2_functions.sql`
4. `202611120002_part3_policies.sql`
5. `202611120003_team_member_privacy.sql`
6. `202611120004_field_operations.sql`
7. `202611120005_bank_payment_workflow.sql`
8. `202611120006_ammar_marketplace_messaging.sql`
8. `202611120006_ammar_marketplace_messaging.sql`

Do not rerun earlier migrations that have already been applied successfully. Keep a record of the environment and migration history.

For the AMMAR marketplace release, apply migration 8 first in a separate Supabase test project. Confirm the new tables, RLS policies, Storage buckets and realtime publication, then run the buyer/supplier/service-provider acceptance tests with separate accounts. Only after the test environment passes should the same migration be applied to production. The GitHub feature pull request must be reviewed and merged separately; merging code alone does not apply the database migration.

## Deployment notes

The site uses the Supabase publishable/anon key in the browser. This key is intended to be public; database security must therefore be enforced by RLS and least-privilege grants. Never put a Supabase service-role key or other server secret in `index.html`.

Configure the production Supabase Auth site URL and redirect URLs to match the deployed domain. Email delivery for password recovery and invitations requires a verified sender/provider configuration.

## Product and release boundaries

The service worker caches the application shell for quicker loading and an installable app experience. It does **not** currently provide full offline project-data editing or reliable background synchronization.

The ecosystem migration adds the first marketplace and messaging foundation. It does not itself create a payment processor, escrow, or funds custody. The current rollout should be treated as a controlled pilot until the new migration is applied, the new account-to-account workflows are tested, and the RLS review below is complete. The service-provider and agreement schemas provide a foundation; they still need broader acceptance workflows and operational review before public-scale use. Before broad public launch, complete a real-device/browser regression pass, database/RLS security review, backup and restore validation, monitoring/alerts, legal/privacy pages, billing and payment integrations where needed, and a supervised customer pilot in Sudan. Validate localization, currencies, date formats and operational workflows in each target market before expanding.

## Release verification

Syntax checks on the inline application JavaScript, service worker and manifest are useful preflight checks, but they do not replace browser, database-runtime, security or end-to-end acceptance tests.


## Payments and custody

The bank milestone workflow records deposit references, bank reconciliation, client acceptance, disputes, refunds and payout references. It does not move money or provide escrow. Do not receive customer funds into a personal or ordinary operating account. Any safeguarded balance, escrow arrangement, bank API, or automatic payout must be provided under a written agreement with a bank or licensed payment institution and reviewed for Sudanese regulatory requirements.


## AMMAR marketplace and messaging rollout

The marketplace and messaging implementation is isolated in `ammar-marketplace.js` and migration `202611120006_ammar_marketplace_messaging.sql`. Apply the migration once, after migration 005, in a non-production Supabase environment first. It is additive and does not rewrite existing project tables or records.

Current browser functionality includes supplier registration, product creation with optional image upload, location/catalog filtering, project-linked purchase requests, supplier quotes, quote acceptance, delivery status transitions, internal conversations, private file attachments, service-provider profiles, service RFQs, agreement creation/dual-party acceptance and a payer-facing commission ledger view.

Before merging this branch to production, test with at least two independent authenticated accounts (buyer and supplier). Verify that each account can only see its own orders and conversations, and that unverified suppliers cannot set their own verification state. Verify message attachment access from a non-participant account. Do not claim marketplace operations are live until the migration has been applied to the target Supabase project and the branch is deployed.

The default commission rate is 5% for the configured service categories, with the provider as the default payer. It is a configurable starting rule, not a market-validated final price. On completion of a market-material order, the database records a commission due entry; it does not collect or transfer funds.
