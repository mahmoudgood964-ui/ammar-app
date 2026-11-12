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
- Arabic/English interface switching.
- Installable PWA shell.

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

Do not rerun earlier migrations that have already been applied successfully. Keep a record of the environment and migration history.

## Deployment notes

The site uses the Supabase publishable/anon key in the browser. This key is intended to be public; database security must therefore be enforced by RLS and least-privilege grants. Never put a Supabase service-role key or other server secret in `index.html`.

Configure the production Supabase Auth site URL and redirect URLs to match the deployed domain. Email delivery for password recovery and invitations requires a verified sender/provider configuration.

## Product and release boundaries

The service worker caches the application shell for quicker loading and an installable app experience. It does **not** currently provide full offline project-data editing or reliable background synchronization.

The current release is a project operations workspace, not yet a full multi-tenant contractor marketplace. Before broad public launch, complete a real-device/browser regression pass, database/RLS security review, backup and restore validation, monitoring/alerts, legal/privacy pages, billing and payment integrations where needed, and a supervised customer pilot in Sudan. Validate localization, currencies, date formats and operational workflows in each target market before expanding.

## Release verification

Syntax checks on the inline application JavaScript, service worker and manifest are useful preflight checks, but they do not replace browser, database-runtime, security or end-to-end acceptance tests.
