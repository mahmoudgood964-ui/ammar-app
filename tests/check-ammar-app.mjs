import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const html = fs.readFileSync('index.html', 'utf8');
const moduleSource = fs.readFileSync('ammar-marketplace.js', 'utf8');
const serviceWorker = fs.readFileSync('sw.js', 'utf8');
const migration = fs.readFileSync('supabase/migrations/202611120006_ammar_marketplace_messaging.sql', 'utf8');
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

for (const feature of [
  'data-eco-buy','data-eco-contact','data-eco-submit-quote','data-eco-accept-quote',
  'data-eco-service-offer','data-eco-accept-service','data-eco-service-chat',
  'data-eco-complete-service','data-eco-submit-review','ammar_user_notifications','ammar-chat-files','ammar-market-files'
]) assert.ok(moduleSource.includes(feature), 'Missing UI feature ' + feature);

console.log('AMMAR static application and migration checks passed.');
