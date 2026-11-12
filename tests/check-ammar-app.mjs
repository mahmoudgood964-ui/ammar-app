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

console.log('AMMIR static application and migration checks passed.');
