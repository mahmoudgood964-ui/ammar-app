import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const html = fs.readFileSync('index.html', 'utf8');
const moduleSource = fs.readFileSync('ammar-marketplace.js', 'utf8');
const serviceWorker = fs.readFileSync('sw.js', 'utf8');
const migration = fs.readFileSync('supabase/migrations/202611120006_ammar_marketplace_messaging.sql', 'utf8');
const messagingPlus = fs.readFileSync('supabase/migrations/202611120007_ammar_messaging_plus.sql', 'utf8');
const trustMigration = fs.readFileSync('supabase/migrations/20261112200000_ammir_trust_and_admin_access.sql', 'utf8');
const verificationMigration = fs.readFileSync('supabase/migrations/20261112203000_ammir_provider_verification_audit.sql', 'utf8');
const trustTests = fs.readFileSync('tests/ammar-trust-admin.sql', 'utf8');
const providerGateMigration = fs.readFileSync('supabase/migrations/20261112210000_ammir_verified_provider_transaction_gate.sql', 'utf8');
const marketplaceIntegration = fs.readFileSync('tests/ammar-marketplace-integration.sql', 'utf8');
const messagingTests = fs.readFileSync('tests/ammar-messaging-plus.sql', 'utf8');
const competitiveAudit = fs.readFileSync('docs/AMMAR_COMPETITIVE_POSITIONING_AND_NAME_REVIEW.md', 'utf8');
const releaseAudit = fs.readFileSync('docs/AMMAR_MESSAGING_AND_RELEASE_GAP_AUDIT.md', 'utf8');
const tests = fs.readFileSync('tests/ammar-marketplace-integration.sql', 'utf8');
const workflowSchema = fs.readFileSync('supabase/migrations/20261113090000_ammir_boq_rfq_awards_delivery.sql', 'utf8');
const workflowRls = fs.readFileSync('supabase/migrations/20261113091000_ammir_workflow_rls_and_indexes.sql', 'utf8');
const workflowProviderGates = fs.readFileSync('supabase/migrations/20261113092000_ammir_verified_provider_gates_and_quote_totals.sql', 'utf8');
const workflowState = fs.readFileSync('supabase/migrations/20261113093000_ammir_workflow_state_guards.sql', 'utf8');
const workflowIndexes = fs.readFileSync('supabase/migrations/20261113094000_ammir_workflow_fk_indexes.sql', 'utf8');
const workflowGuards = fs.readFileSync('supabase/migrations/20261113100000_ammir_execution_state_guards.sql', 'utf8');
const workflowTests = fs.readFileSync('tests/ammir-project-workflows.sql', 'utf8');


const inlineScripts = [...html.matchAll(/<script\b(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
assert.ok(inlineScripts.length > 0, 'The main app inline script must exist');
inlineScripts.forEach((match, index) => {
  new vm.Script(match[1], { filename: 'index.html:inline-script-' + (index + 1) });
});
new vm.Script(moduleSource, { filename: 'ammar-marketplace.js' });

assert.match(html, /window\.ammarSupabase\s*=\s*client/, 'Expose the existing authenticated Supabase client');
assert.match(html, /<script src="\/ammar-marketplace\.js"><\/script>/, 'Load the ecosystem browser module');
assert.match(serviceWorker, /ammar-marketplace\.js/, 'Cache the ecosystem module in the service worker');

const tables = [
  'ammar_market_suppliers','ammar_market_products','ammar_service_providers',
  'ammar_market_requests','ammar_market_request_items','ammar_market_quotes',
  'ammar_service_requests','ammar_service_offers','ammar_conversations',
  'ammar_conversation_participants','ammar_messages','ammar_user_notifications',
  'ammar_agreements','ammar_agreement_events','ammar_reviews','ammar_disputes',
  'ammar_commission_rules','ammar_commission_ledger','ammar_transaction_events'
];
for (const name of tables) {
  assert.ok(migration.includes('CREATE TABLE IF NOT EXISTS public.' + name), 'Missing table ' + name);
  assert.ok(migration.includes('ALTER TABLE public.' + name + ' ENABLE ROW LEVEL SECURITY'), 'RLS missing for ' + name);
}
for (const rpc of [
  'ammar_create_market_request','ammar_accept_market_quote','ammar_advance_market_request',
  'ammar_start_conversation','ammar_accept_service_offer','ammar_accept_agreement',
  'ammar_complete_service_request'
]) assert.ok(migration.includes('FUNCTION public.' + rpc), 'Missing RPC ' + rpc);

assert.ok(migration.includes('ammar-chat-files'), 'Private chat file bucket is missing');
assert.ok(migration.includes('ammar-market-files'), 'Product image bucket is missing');
assert.ok(migration.includes('project_expenses'), 'Completed purchases must be linked to project expenses');
assert.doesNotMatch(migration, /\bDROP\s+(?:TABLE|SCHEMA)\b/i, 'Migration must not drop existing tables or schemas');
const realtimeStart = moduleSource.indexOf('function switchRealtime');
const realtimeEnd = moduleSource.indexOf('async function click', realtimeStart);
const realtimeBlock = moduleSource.slice(realtimeStart, realtimeEnd);
for (const table of ['ammar_messages','ammar_user_notifications','ammar_message_receipts']) {
  assert.ok(realtimeBlock.includes("table:'" + table + "'"), 'Missing realtime subscription for ' + table);
}
assert.ok(moduleSource.includes("m.message_type==='text'&&m.body"), 'Forward control must be limited to text messages');

assert.ok(!/(^|\n)AS \$(\n|$)/.test(migration), 'Found malformed PL/pgSQL dollar opening delimiter');
assert.ok(!/(^|\n)\$(\n|$)/.test(migration), 'Found malformed PL/pgSQL dollar closing delimiter');

const tagMatches = [...migration.matchAll(/\$[A-Za-z_0-9]*\$/g)].map(x => x[0]);
const tagCounts = new Map();
for (const tag of tagMatches) tagCounts.set(tag, (tagCounts.get(tag) || 0) + 1);
for (const [tag, count] of tagCounts) assert.equal(count % 2, 0, 'Unbalanced SQL delimiter ' + tag);

assert.ok(!/^DO \$(?: BEGIN|$)/m.test(tests), 'Found malformed dollar delimiter in integration test');
assert.ok(tests.includes('ammar_accept_agreement'), 'Dual-party agreement tests are missing');
assert.ok(tests.includes('ammar_advance_market_request'), 'Purchase lifecycle tests are missing');
assert.ok(tests.includes('RLS failure'), 'Private conversation isolation test is missing');
for (const feature of ['ammar_message_receipts','ammar_user_blocks','ammar_message_reports','ammar_pinned_messages','ammar_conversation_preferences','ammar_user_presence']) {
  assert.ok(messagingPlus.includes('CREATE TABLE IF NOT EXISTS public.' + feature), 'Missing advanced messaging table ' + feature);
}
for (const rpc of ['ammar_mark_conversation_delivered','ammar_mark_conversation_read','ammar_set_presence','ammar_get_conversation_presence','ammar_forward_message','ammar_message_to_project_task','ammar_message_to_change_order']) {
  assert.ok(messagingPlus.includes('FUNCTION public.' + rpc), 'Missing advanced messaging RPC ' + rpc);
}
assert.ok(messagingPlus.includes("'video','location'"), 'Video and location messages are missing');
assert.ok(messagingPlus.includes("'market_quote','agreement'"), 'Quote and agreement chat contexts are missing');
assert.ok(messagingTests.includes('AMMAR ADVANCED MESSAGING TESTS PASSED'), 'Advanced messaging integration tests are missing');
assert.ok(messagingTests.includes('بعد إلغاء الحظر'), 'Unblock/resume messaging test is missing');
assert.ok(messagingTests.includes("'market_quote'"), 'Quote-linked conversation test is missing');
assert.ok(messagingTests.includes("'agreement'"), 'Agreement-linked conversation test is missing');
assert.ok(competitiveAudit.includes('عمار لمواد البناء'), 'Direct same-name building-materials competitor not documented');
assert.ok(competitiveAudit.includes('BOQ'), 'Defensible project procurement differentiation is not documented');
assert.ok(releaseAudit.includes('synthetic PostgreSQL'), 'Release audit must distinguish synthetic CI from production readiness');

for (const feature of [
  'data-eco-buy','data-eco-contact','data-eco-submit-quote','data-eco-accept-quote',
  'data-eco-service-offer','data-eco-accept-service','data-eco-service-chat',
  'data-eco-complete-service','data-eco-submit-review','data-eco-unblock','data-eco-to-task','data-eco-to-change','data-eco-quote-chat','data-eco-agreement-chat','contextCard','ammar_user_notifications','ammar-chat-files','ammar-market-files'
]) assert.ok(moduleSource.includes(feature), 'Missing UI feature ' + feature);

assert.ok(moduleSource.includes('data-eco-tab="partners"'), 'Exploratory partner directory tab is missing');
assert.ok(moduleSource.includes('function partnerDirectoryHtml'), 'Partner directory renderer is missing');
assert.ok(moduleSource.includes('جهة محتملة — غير معتمدة'), 'Partner prospects must be clearly marked unapproved');
assert.ok(moduleSource.includes('لم تُنشأ لها حسابات داخل التطبيق'), 'Partner directory must not imply consent or account creation');
assert.ok(moduleSource.includes('ecoPartnerSearch'), 'Partner directory search is missing');
assert.ok(moduleSource.includes('UN-Habitat Sudan'), 'Housing support organization lead is missing');
assert.ok(moduleSource.includes('ATC Group'), 'Construction company lead is missing');
assert.ok(moduleSource.includes('info@ctiunited.com'), 'CTI public contact is missing');
assert.ok(moduleSource.includes('const cbosBanks = ['), 'Official CBOS bank directory data is missing');
const cbosBankStart = moduleSource.indexOf('const cbosBanks = [');
const cbosBankEnd = moduleSource.indexOf('\\n  ];', cbosBankStart);
assert.ok(cbosBankStart >= 0 && cbosBankEnd > cbosBankStart, 'CBOS bank list could not be parsed');
const cbosBankEntries = moduleSource.slice(cbosBankStart, cbosBankEnd).split('\\n').filter(line => line.trim().startsWith("'"));
assert.equal(cbosBankEntries.length, 38, 'Expected 38 banks from the published CBOS licensed-institutions list');
assert.ok(moduleSource.includes('value="financial"'), 'Financial institution filter is missing');
assert.ok(moduleSource.includes('حالة التشغيل غير مؤكدة'), 'Financial directory must not imply that every listed bank is operating');
assert.ok(moduleSource.includes('لا توجد حالياً اتفاقات مصرفية أو عروض تمويل معتمدة'), 'Financial directory must not imply AMMIR bank partnerships or available finance');
assert.ok(html.includes('function authErrorMessage('), 'Friendly authentication error mapper is missing');
assert.ok(html.includes('البريد الإلكتروني أو كلمة المرور غير صحيحة.'), 'Invalid login guidance is missing');
assert.ok(!html.includes("تعذر تسجيل الدخول: '+(err.message"), 'Raw authentication errors must not be exposed to users');


assert.ok(trustMigration.includes('ammir_guard_provider_trust_fields'), 'Provider self-verification trigger is missing');
assert.ok(trustMigration.includes('ammar_admin_list_message_reports'), 'Admin report review RPC is missing');
assert.ok(trustMigration.includes('ammir_admin_message_reports_update'), 'Admin report moderation policy is missing');
assert.ok(verificationMigration.includes('ammar_provider_verification_events'), 'Provider verification audit log is missing');
assert.ok(verificationMigration.includes('ammar_admin_review_provider'), 'Audited admin verification RPC is missing');
assert.ok(verificationMigration.includes('SET search_path ='), 'Admin verification RPC must lock its search_path');
assert.ok(trustTests.includes('Supplier self-verification or self-suspension was not blocked'), 'Trust regression tests are missing');
assert.ok(trustTests.includes('Non-admin was able to approve a supplier'), 'Non-admin privilege-escalation test is missing');
assert.ok(trustTests.includes('AMMIR TRUST AND ADMIN ACCESS TESTS PASSED'), 'Trust/admin integration test completion marker is missing');


assert.ok(providerGateMigration.includes('s.is_verified = true'), 'Market purchase verification gate is missing');
assert.ok(providerGateMigration.includes('sp.is_verified = true'), 'Service provider verification gate is missing');
assert.ok(providerGateMigration.includes('ammar_accept_market_quote'), 'Quote acceptance verification gate is missing');
assert.ok(providerGateMigration.includes('ammar_accept_service_offer'), 'Service offer acceptance verification gate is missing');
assert.ok(marketplaceIntegration.includes('Unverified supplier unexpectedly accepted'), 'Unverified supplier purchase regression test is missing');
assert.ok(marketplaceIntegration.includes('Unverified provider unexpectedly submitted'), 'Unverified service provider offer regression test is missing');
assert.ok(marketplaceIntegration.includes('Buyer unexpectedly accepted a quote from an unverified supplier'), 'Quote acceptance verification regression test is missing');
assert.ok(marketplaceIntegration.includes('Buyer unexpectedly accepted an offer from an unverified provider'), 'Service offer acceptance verification regression test is missing');
assert.ok(moduleSource.includes('الشراء متاح بعد اعتماد المورد'), 'Unverified supplier purchase warning is missing from the UI');
assert.ok(moduleSource.includes('تقديم العروض الرسمية يتاح بعد اعتماد حسابك'), 'Unverified service-provider offer warning is missing from the UI');


const workflowTables = [
  'ammir_project_boq_versions','ammir_project_boq_items','ammir_project_rfqs',
  'ammir_project_rfq_items','ammir_project_rfq_invites','ammir_project_rfq_quotes',
  'ammir_project_rfq_quote_items','ammir_project_awards','ammir_project_award_items',
  'ammir_project_deliveries','ammir_project_delivery_items','ammir_project_delivery_evidence'
];
for (const table of workflowTables) {
  assert.ok(workflowSchema.includes('CREATE TABLE IF NOT EXISTS public.' + table), 'Missing execution workflow table ' + table);
  assert.ok(workflowSchema.includes("'" + table + "'"), 'Missing RLS enablement entry for ' + table);
}
for (const migration of [workflowSchema,workflowRls,workflowProviderGates,workflowState,workflowIndexes,workflowGuards]) {
  assert.doesNotMatch(migration,/project_payment_(?:milestones|events)/,'Execution workflow migrations must not alter deferred bank milestone tables');
  for (const line of migration.split(/\r?\n/)) {
    assert.notEqual(line.trim(),'AS $','Execution workflow migration contains malformed PL/pgSQL opening delimiter');
    assert.notEqual(line.trim(),'$;','Execution workflow migration contains malformed PL/pgSQL closing delimiter');
  }
}
for (const feature of [
  'ammir_rfq_quotes_select','ammir_rfq_quotes_insert','ammir_rfq_invites_insert',
  'ammir_awards_insert','ammir_delivery_evidence_storage_select'
]) assert.ok(workflowSchema.includes(feature)||workflowRls.includes(feature)||workflowProviderGates.includes(feature),'Missing workflow access policy ' + feature);
for (const guard of [
  'ammir_guard_rfq_state_trigger','ammir_guard_invite_state_trigger',
  'ammir_guard_award_header_state_trigger','ammir_guard_delivery_delete_trigger'
]) assert.ok(workflowGuards.includes(guard),'Missing commercial state guard ' + guard);
assert.ok(workflowSchema.includes("'ammir-delivery-evidence','ammir-delivery-evidence',false"),'Private delivery evidence bucket is missing');
assert.ok(workflowProviderGates.includes("NEW.total_cost :="),'Quote total must be derived from submitted line items and costs');
assert.ok(workflowGuards.includes('Published RFQ scope is immutable'),'Published RFQ scope immutability guard is missing');
assert.ok(workflowGuards.includes('Issued award terms and supplier are immutable'),'Issued award immutability guard is missing');
assert.ok(workflowTests.includes('AMMIR PROJECT BOQ/RFQ/AWARD/DELIVERY TESTS PASSED'),'Execution workflow regression test completion marker is missing');
assert.ok(workflowTests.includes('Split awards exceeding requested quantity'),'Split-award quantity regression test is missing');
assert.ok(workflowTests.includes('Delivery with a supplier different from the award'),'Delivery supplier mismatch regression test is missing');

for (const feature of [
  'function parseAmmirCsv','function downloadAmmirCsv','data-execution-form="boqImport"',
  'data-execution-status="boq-template"','data-execution-status="boq-export"',
  'async function loadRfqInbox','async function submitRfqProviderQuote',
  'data-execution-form="rfq"','data-execution-form="invite"',
  'data-execution-form="award"','data-execution-form="delivery"','data-execution-form="receipt"',
  'data-rfq-provider-form="quote"','ammir-delivery-evidence'
]) assert.ok(html.includes(feature),'Missing project execution UI feature ' + feature);

const csvStart=html.indexOf('function parseAmmirCsv');
const csvEnd=html.indexOf('function renderExecutionPanel',csvStart);
assert.ok(csvStart>=0&&csvEnd>csvStart,'BOQ CSV import/export helpers are missing');
const csvSandbox={};
vm.runInNewContext(
  html.slice(csvStart,csvEnd) + String.fromCharCode(10) + 'globalThis.parseAmmirCsv=parseAmmirCsv;',
  csvSandbox
);
const newline=String.fromCharCode(10),bom=String.fromCharCode(0xfeff);
const csvText=bom+[
  'item_code,description,specification,unit,quantity,unit_rate,currency',
  '01,"Concrete, C30","Grade C30",m3,10,125,SDG',
  '02,Steel bar,12mm,kg,50,,SDG'
].join(newline);
const importedRows=csvSandbox.parseAmmirCsv(csvText);
assert.equal(importedRows.length,2,'CSV parser should read both BOQ rows');
assert.equal(importedRows[0].description,'Concrete, C30','CSV parser should preserve quoted commas');
assert.equal(importedRows[0].quantity,10,'CSV parser should normalize numeric quantities');
assert.equal(importedRows[1].unit_rate,null,'CSV parser should accept a blank optional unit rate');


const identityCss = fs.readFileSync('ammir-identity.css', 'utf8');
const pwaManifest = JSON.parse(fs.readFileSync('manifest.webmanifest', 'utf8'));
assert.ok(html.includes('<link rel="stylesheet" href="/ammir-identity.css">'), 'Identity stylesheet must load on the first page visit without relying on service-worker HTML rewriting');
assert.ok(html.includes('<link rel="apple-touch-icon" sizes="192x192" href="/icon-192.png">'), 'Apple launcher icon declaration is missing');
assert.ok(html.includes('<meta name="mobile-web-app-capable" content="yes">'), 'Android standalone app metadata is missing');
assert.ok(html.includes('<meta name="theme-color" content="#102f29">'), 'Browser chrome theme must match the AMMIR identity');
assert.equal(pwaManifest.display, 'standalone', 'PWA must request standalone display');
assert.ok(pwaManifest.icons.some(icon => icon.src === '/icon-192.png' && icon.sizes === '192x192'), '192px install icon is missing from the manifest');
assert.ok(pwaManifest.icons.some(icon => icon.src === '/icon-512.png' && icon.sizes === '512x512' && icon.purpose.includes('maskable')), '512px maskable install icon is missing from the manifest');
assert.ok(identityCss.includes("url('/icon.svg')"), 'The app brand mark must use the canonical AMMIR seal');
assert.ok(identityCss.includes(':focus-visible'), 'Keyboard-visible focus treatment is missing');
assert.ok(serviceWorker.includes('/icon-512.png'), 'The 512px install icon must be cached in the app shell');
assert.ok(serviceWorker.includes('ammir-shell-v9-identity-first-load'), 'Service worker cache must be versioned for the new identity assets');
assert.ok(!serviceWorker.includes("html.replace('</head>'"), 'Service worker must not rewrite HTML to inject identity assets; first-load HTML must declare them directly');

console.log('AMMIR static application and migration checks passed.');
