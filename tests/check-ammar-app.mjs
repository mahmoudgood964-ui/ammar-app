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
const operationalAlertsMigration = fs.readFileSync('supabase/migrations/20261125103000_add_admin_operational_alerts.sql', 'utf8');
const operationalAlertsTests = fs.readFileSync('tests/ammir-admin-operational-alerts.sql', 'utf8');
const workflowTests = fs.readFileSync('tests/ammir-project-workflows.sql', 'utf8');


const inlineScripts = [...html.matchAll(/<script\b(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
assert.ok(inlineScripts.length > 0, 'The main app inline script must exist');
inlineScripts.forEach((match, index) => {
  new vm.Script(match[1], { filename: 'index.html:inline-script-' + (index + 1) });
});
new vm.Script(moduleSource, { filename: 'ammar-marketplace.js' });

const revenueExportStart = moduleSource.indexOf('async function loadRevenueAdjustments(');
const revenueExportEnd = moduleSource.indexOf('async function adminDashboardHtml()', revenueExportStart);
assert.ok(revenueExportStart >= 0 && revenueExportEnd > revenueExportStart, 'Revenue CSV export helpers are missing');
const revenueCsvSandbox = {};
vm.runInNewContext(
  moduleSource.slice(revenueExportStart, revenueExportEnd) + String.fromCharCode(10) + 'globalThis.revenueCsvCell=revenueCsvCell;globalThis.revenueAdjustmentSummary=revenueAdjustmentSummary;globalThis.loadRevenueAdjustments=loadRevenueAdjustments;',
  revenueCsvSandbox
);
assert.equal(
  revenueCsvSandbox.revenueCsvCell('=HYPERLINK("https://evil.example")', 'source_id'),
  '"\'=HYPERLINK(""https://evil.example"")"',
  'CSV export must neutralize spreadsheet formulas in text fields'
);
assert.equal(
  revenueCsvSandbox.revenueCsvCell('@SUM(A1:A2)', 'source_id'),
  '"\'@SUM(A1:A2)"',
  'CSV export must neutralize formula-like text beginning with @'
);
assert.equal(
  revenueCsvSandbox.revenueCsvCell('  =SUM(A1:A2)', 'source_id'),
  '"' + String.fromCharCode(39) + '  =SUM(A1:A2)"',
  'CSV export must neutralize formulas preceded by whitespace'
);
assert.equal(
  revenueCsvSandbox.revenueCsvCell('-5.00', 'commission_amount'),
  '"-5.00"',
  'CSV export must preserve numeric values as numeric text'
);
assert.equal(
  revenueCsvSandbox.revenueCsvCell('-12.50', 'adjustment_delta'),
  '"-12.50"',
  'CSV export must preserve negative adjustment amounts as numeric text'
);
assert.equal(
  revenueCsvSandbox.revenueCsvCell('-2.50', 'net_commission_amount'),
  '"-2.50"',
  'CSV export must preserve negative adjusted commission as numeric text'
);
assert.ok(
  moduleSource.includes("if(!isAdmin)throw new Error('ليست لديك صلاحية إدارة الإيرادات')"),
  'Revenue dashboard must enforce the admin guard before loading data'
);

assert.ok(
  moduleSource.includes("db.rpc('is_admin').then(result=>"),
  'Admin UI privilege state must come from the server-side is_admin RPC'
);
assert.ok(
  moduleSource.includes("const revenueTab=$('ecoRevenueTab');if(revenueTab)revenueTab.hidden=!isAdmin;"),
  'Revenue navigation must be hidden for non-admin sessions'
);
assert.ok(
  moduleSource.includes("if(!isAdmin&&['admin','revenue'].includes(tab))tab='market';"),
  'Non-admin sessions must be redirected away from admin and revenue panels'
);
assert.ok(
  moduleSource.includes("if($('ecoRevenueTab'))$('ecoRevenueTab').hidden=true;"),
  'Revenue navigation must be hidden when the session is cleared'
);
const summarizedRevenue = revenueCsvSandbox.revenueAdjustmentSummary(
  [
    {id:'ledger-a',currency:'SDG',commission_amount:50.00,status:'due'},
    {id:'ledger-b',currency:'USD',commission_amount:25.00,status:'paid'}
  ],
  [
    {ledger_id:'ledger-a',currency:'SDG',amount_delta:-10.00},
    {ledger_id:'ledger-a',currency:'SDG',amount_delta:-5.00},
    {ledger_id:'ledger-a',currency:'SDG',amount_delta:3.00},
    {ledger_id:'ledger-b',currency:'USD',amount_delta:-2.50},
    {ledger_id:'unloaded-ledger',currency:'SDG',amount_delta:-99.00}
  ]
);
assert.equal(summarizedRevenue[0].adjustment_delta,-12.00,'Revenue summary must net all append-only adjustments for the ledger');
assert.equal(summarizedRevenue[0].net_commission_amount,38.00,'Revenue summary must calculate original commission plus adjustments');
assert.equal(summarizedRevenue[0].commission_amount,50.00,'Revenue summary must preserve the immutable original commission amount');
assert.equal(summarizedRevenue[1].adjustment_delta,-2.50,'Revenue summary must keep currency-specific ledger adjustments separate');
assert.equal(summarizedRevenue[1].net_commission_amount,22.50,'Revenue summary must calculate adjusted commission for each ledger row');
assert.throws(
  () => revenueCsvSandbox.revenueAdjustmentSummary(
    [{id:'ledger-c',currency:'SDG',commission_amount:10}],
    [{ledger_id:'ledger-c',currency:'USD',amount_delta:-1}]
  ),
  /عملة التعديل لا تطابق عملة سجل العمولة/,
  'Revenue summary must reject an adjustment whose currency differs from its ledger row'
);
assert.ok(moduleSource.includes("db.from('ammar_commission_adjustments')"),'Revenue dashboard must load append-only adjustment rows');
assert.ok(moduleSource.includes("record_type:'adjustment'"),'Revenue CSV must include adjustment event rows separately from ledger rows');
assert.ok(moduleSource.includes('net_commission_amount'),'Revenue dashboard and export must expose adjusted net commission');

const statementStart=moduleSource.indexOf('function statementCsvCell(');
const statementEnd=moduleSource.indexOf('async function agreementsHtml()',statementStart);
assert.ok(statementStart>=0&&statementEnd>statementStart,'Period-based commission statement helpers are missing');
const monthlyStatementSandbox={};
vm.runInNewContext(
  moduleSource.slice(statementStart,statementEnd)+String.fromCharCode(10)+
  'globalThis.statementCsvCell=statementCsvCell;globalThis.buildCommissionStatementRows=buildCommissionStatementRows;globalThis.summarizeCommissionStatement=summarizeCommissionStatement;',
  monthlyStatementSandbox
);
assert.equal(
  monthlyStatementSandbox.statementCsvCell('=HYPERLINK("https://bad.example")','reason'),
  '"\'=HYPERLINK(""https://bad.example"")"',
  'Commission statement CSV must neutralize spreadsheet formula injection in text fields'
);
assert.equal(
  monthlyStatementSandbox.statementCsvCell('-12.50','adjustment_delta'),
  '"-12.50"',
  'Commission statement CSV must preserve signed numeric adjustment values'
);
const monthlyStatementRows=monthlyStatementSandbox.buildCommissionStatementRows(
  [{id:'ledger-1',recorded_at:'2026-11-03T10:00:00Z',activity_type:'market_materials',source_type:'market_request',source_id:'req-1',gross_amount:1000,currency:'SDG',rate_percent:5,commission_amount:50,status:'due'}],
  [{id:'adj-1',ledger_id:'ledger-1',created_at:'2026-11-12T10:00:00Z',adjustment_kind:'partial_refund',amount_delta:-10,currency:'SDG',reason:'Refund correction',source_reference:'bank-ref-1'}],
  [{id:'ledger-1',activity_type:'market_materials',source_type:'market_request',source_id:'req-1',status:'due'}]
);
assert.equal(monthlyStatementRows.length,2,'Statement must include commission and its adjustment as separate dated events');
assert.equal(monthlyStatementRows[1].source_id,'req-1','Adjustment statement row must retain its source transaction reference');
assert.equal(monthlyStatementRows[1].net_activity,-10,'Adjustment statement row must retain its signed net activity');
const monthlyStatementTotals=monthlyStatementSandbox.summarizeCommissionStatement(monthlyStatementRows);
assert.equal(monthlyStatementTotals[0].gross_amount,1000,'Statement summary must total gross transaction basis');
assert.equal(monthlyStatementTotals[0].commission_amount,50,'Statement summary must preserve original commission');
assert.equal(monthlyStatementTotals[0].adjustment_delta,-10,'Statement summary must total signed adjustments separately');
assert.equal(monthlyStatementTotals[0].net_activity,40,'Statement summary must calculate net period activity');
assert.ok(moduleSource.includes("gte('recorded_at',start).lt('recorded_at',end)"),'Statement ledger query must be restricted to the selected month');
assert.ok(moduleSource.includes("gte('created_at',start).lt('created_at',end)"),'Statement adjustment query must be restricted to the selected month');
assert.ok(moduleSource.includes(".eq('payer_id',user.id)"),'Statement ledger query must remain scoped to the signed-in payer');
assert.ok(moduleSource.includes('async function fetchStatementPages(makeQuery)'), 'Statement export must paginate rather than silently truncate at a fixed row limit');
assert.ok(moduleSource.includes("link.download='ammir-commission-statement-'+month+'.csv'"),'Statement export filename must identify its reporting month');
assert.ok(moduleSource.includes("data-statement-export>تنزيل كشف الشهر CSV"),'Statement export must be a month-selected action, not embedded CSV data in HTML');

const reconciliationStart=moduleSource.indexOf('function parseSettlementCsv(');
const reconciliationEnd=moduleSource.indexOf('async function adminDashboardHtml()',reconciliationStart);
assert.ok(reconciliationStart>=0&&reconciliationEnd>reconciliationStart,'Read-only settlement reconciliation helpers are missing');
const reconciliationSandbox={revenueAdjustmentSummary:revenueCsvSandbox.revenueAdjustmentSummary};
vm.runInNewContext(
  moduleSource.slice(reconciliationStart,reconciliationEnd)+String.fromCharCode(10)+
  'globalThis.parseSettlementCsv=parseSettlementCsv;globalThis.buildSettlementReconciliation=buildSettlementReconciliation;',
  reconciliationSandbox
);
const settlementCsv=String.fromCharCode(0xfeff)+'ledger_id,amount,currency,external_reference'+String.fromCharCode(13,10)+'11111111-1111-4111-8111-111111111111,40.00,SDG,"BANK, REF 1"'+String.fromCharCode(13,10)+'22222222-2222-4222-8222-222222222222,20.00,SDG,ref-2'+String.fromCharCode(13,10)+'22222222-2222-4222-8222-222222222222,20.00,SDG,ref-3'+String.fromCharCode(13,10)+'33333333-3333-4333-8333-333333333333,10.00,USD,ref-4'+String.fromCharCode(13,10);
const parsedSettlement=reconciliationSandbox.parseSettlementCsv(settlementCsv);
assert.equal(parsedSettlement.length,4,'Settlement CSV parser must preserve all data rows');
assert.equal(parsedSettlement[0].external_reference,'BANK, REF 1','Settlement CSV parser must preserve quoted commas');
const settlementResults=reconciliationSandbox.buildSettlementReconciliation(
  parsedSettlement,
  [
    {id:'11111111-1111-4111-8111-111111111111',currency:'SDG',commission_amount:50,status:'paid'},
    {id:'22222222-2222-4222-8222-222222222222',currency:'SDG',commission_amount:25,status:'due'}
  ],
  [{ledger_id:'11111111-1111-4111-8111-111111111111',currency:'SDG',amount_delta:-10}]
);
assert.equal(settlementResults[0].status,'matched','Settlement report must match net commission after adjustments');
assert.equal(settlementResults[0].expected_amount,40,'Settlement report must compare against adjusted commission, not original amount');
assert.equal(settlementResults[1].status,'duplicate_ledger','Duplicate ledger references must be flagged');
assert.equal(settlementResults[2].status,'duplicate_ledger','Every row for a duplicate ledger reference must be flagged');
assert.equal(settlementResults[3].status,'unknown_ledger','Unknown ledger references must be flagged, not accepted');

const exceptionResults=reconciliationSandbox.buildSettlementReconciliation(
  [
    {ledger_id:'44444444-4444-4444-8444-444444444444',amount:'29.00',currency:'SDG'},
    {ledger_id:'55555555-5555-4555-8555-555555555555',amount:'15.00',currency:'USD'},
    {ledger_id:'66666666-6666-4666-8666-666666666666',amount:'1,000.00',currency:'SDG'}
  ],
  [
    {id:'44444444-4444-4444-8444-444444444444',currency:'SDG',commission_amount:30,status:'due'},
    {id:'55555555-5555-4555-8555-555555555555',currency:'SDG',commission_amount:15,status:'paid'},
    {id:'66666666-6666-4666-8666-666666666666',currency:'SDG',commission_amount:1000,status:'paid'}
  ],
  []
);
assert.equal(exceptionResults[0].status,'amount_mismatch','Different settlement amounts must be flagged');
assert.equal(exceptionResults[1].status,'currency_mismatch','Different settlement currencies must be flagged');
assert.equal(exceptionResults[2].status,'invalid_row','Amounts with thousands separators must be rejected by the declared CSV format');
assert.ok(moduleSource.includes("filter(id=>/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id))"),'Reconciliation must validate UUIDs before sending them to PostgreSQL');
const invalidIdResults=reconciliationSandbox.buildSettlementReconciliation(
  [{ledger_id:'not-a-uuid',amount:'1.00',currency:'SDG'}],
  [],
  []
);
assert.equal(invalidIdResults[0].status,'invalid_row','Malformed ledger UUIDs must be rejected before database lookup');
assert.throws(
  ()=>reconciliationSandbox.parseSettlementCsv('ledger_id,amount'+String.fromCharCode(10)+'11111111-1111-4111-8111-111111111111,2'),
  /عمود مطلوب مفقود: currency/,
  'Settlement CSV parser must reject files without required currency column'
);
assert.ok(moduleSource.includes('id="ecoReconciliationFile"'),'Admin revenue dashboard must expose a settlement CSV input');
assert.ok(moduleSource.includes("if(e.target.id==='ecoReconciliationFile'"),'Settlement CSV input must be processed through the change handler');
assert.ok(moduleSource.includes("eq('payer_id',user.id)")&&moduleSource.includes(".in('ledger_id',chunk)"),'Reconciliation must fetch the ledger and its append-only adjustments by exact IDs');
assert.ok(moduleSource.includes('لا تعدّل هذه اللوحة قواعد العمولة أو القيود المالية'),'Reconciliation UI must disclose its read-only financial boundary');
assert.ok(moduleSource.includes('لا تستنتج أن القيود الغائبة غير مدفوعة'),'Reconciliation UI must not infer missing report rows are unpaid');
assert.ok(moduleSource.includes('function processSettlementFile(file)'),'Reconciliation must process reports without a server upload');

const revenueQueryTrace = [];
revenueCsvSandbox.db = {
  from(table) {
    assert.equal(table,'ammar_commission_adjustments','Revenue adjustment loader must query the append-only adjustments table');
    return {
      select() {
        const query = {ids:[]};
        query.in = function(field,ids) { assert.equal(field,'ledger_id'); this.ids=ids; return this; };
        query.order = function(field,options) { assert.equal(field,'created_at'); assert.equal(options.ascending,false); return this; };
        query.range = async function(from,to) {
          revenueQueryTrace.push({ids:this.ids.slice(),from,to});
          const total=this.ids.length===200?1001:1;
          const count=from===0?Math.min(1000,total):Math.max(0,total-from);
          return {count:total,data:Array.from({length:count},(_,index)=>({
            id:'adjustment-'+this.ids[0]+'-'+(from+index),
            ledger_id:this.ids[0],currency:'SDG',amount_delta:-0.01
          }))};
        };
        return query;
      }
    };
  }
};
const pagedAdjustments = await revenueCsvSandbox.loadRevenueAdjustments(
  Array.from({length:201},(_,index)=>({id:'ledger-'+index}))
);
assert.equal(pagedAdjustments.length,1002,'Revenue adjustment loader must fetch every adjustment page for every ledger ID chunk');
assert.equal(revenueQueryTrace.length,3,'Revenue adjustment loader must paginate and split large ledger ID sets');
assert.deepEqual(revenueQueryTrace.map(x=>x.ids.length),[200,200,1],'Revenue adjustment loader must use bounded ID chunks');
assert.deepEqual(revenueQueryTrace.map(x=>x.from),[0,1000,0],'Revenue adjustment loader must request subsequent pages without skipping rows');



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
const testNewline = String.fromCharCode(10);
const cbosBankEnd = moduleSource.indexOf(testNewline + '  ];', cbosBankStart);
assert.ok(cbosBankStart >= 0 && cbosBankEnd > cbosBankStart, 'CBOS bank list could not be parsed');
const cbosBankEntries = moduleSource.slice(cbosBankStart, cbosBankEnd).split(testNewline).filter(line => line.trim().startsWith("'"));
assert.equal(cbosBankEntries.length, 38, 'Expected 38 banks from the published CBOS licensed-institutions list');
assert.ok(moduleSource.includes('value="financial"'), 'Financial institution filter is missing');
assert.ok(moduleSource.includes('حالة التشغيل تحتاج تحققاً مباشراً'), 'Financial directory must not imply that every listed bank is operating');
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
assert.ok(moduleSource.includes("db.from('ammar_disputes')"), 'Admin dashboard must load commercial disputes');
assert.ok(moduleSource.includes('${adminDisputeCards(disputes)}'), 'Admin dashboard must render the commercial dispute queue');
assert.ok(moduleSource.includes('async function handleAdminDisputeChange(select)'), 'Admin dispute status handler is missing');
assert.ok(moduleSource.includes("if(!isAdmin)throw new Error('ليست لديك صلاحية إدارة عَمِّر')"), 'Admin dispute handler must enforce the local admin guard');
assert.ok(moduleSource.includes("resolved_at:['resolved','rejected'].includes(select.value)"), 'Admin dispute closure must record its resolution timestamp');
assert.ok(trustTests.includes('An unrelated account can read a commercial dispute'), 'Commercial dispute isolation regression is missing');
assert.ok(trustTests.includes('Administrator could not resolve the commercial dispute'), 'Admin dispute resolution regression is missing');
assert.ok(operationalAlertsMigration.includes('public.ammar_admin_list_operational_alerts'), 'Admin operational alerts RPC is missing');
assert.ok(operationalAlertsMigration.includes('auth.uid() IS NULL OR NOT public.is_admin()'), 'Admin operational alerts RPC must reject non-admin callers');
assert.ok(operationalAlertsMigration.includes("r.status IN ('open','closing')"), 'Overdue RFQ filter is missing');
assert.ok(operationalAlertsMigration.includes("d.status IN ('planned','dispatched','partially_received','exception')"), 'Delivery follow-up filter is missing');
assert.ok(operationalAlertsMigration.includes('REVOKE ALL ON FUNCTION public.ammar_admin_list_operational_alerts(integer) FROM PUBLIC, anon'), 'Anon execution must be revoked for admin alerts');
assert.ok(moduleSource.includes("db.rpc('ammar_admin_list_operational_alerts',{p_limit:100})"), 'Admin dashboard must call the bounded operational alerts RPC');
assert.ok(moduleSource.includes('${adminOperationalAlertCards(operationalAlerts)}'), 'Admin dashboard must render operational alert cards');
assert.ok(moduleSource.includes('function adminOperationalAlertCards(rows)'), 'Operational alert renderer is missing');
assert.ok(operationalAlertsTests.includes('An unrelated authenticated account executed the admin alerts RPC'), 'Non-admin RPC denial test is missing');
assert.ok(operationalAlertsTests.includes('AMMIR ADMIN OPERATIONAL ALERTS TESTS PASSED'), 'Operational alert integration test marker is missing');




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
assert.match(serviceWorker, /const CACHE_NAME=['"]ammir-shell-v\d+-[a-z0-9-]+['"]/i, 'Service worker cache must use a versioned AMMIR shell cache name');
assert.ok(!serviceWorker.includes("html.replace('</head>'"), 'Service worker must not rewrite HTML to inject identity assets; first-load HTML must declare them directly');

console.log('AMMIR static application and migration checks passed.');

assert.match(html, /function passwordPolicyError\(password\)/, 'Password policy helper must exist');
assert.match(html, /password\.length<12/, 'Signup and recovery must require at least 12 characters');
assert.match(html, /classes<3/, 'Password policy must require three character classes');
assert.match(html, /minlength="12"/, 'Password inputs must expose the 12-character minimum');

assert.ok(moduleSource.includes('ammar_commission_adjustments'), 'Payer statement must include append-only commission adjustments');
assert.ok(moduleSource.includes(".eq('payer_id',user.id)"), 'Payer statement must be scoped to the authenticated payer');
assert.ok(moduleSource.includes('statementTotals'), 'Payer statement currency totals are missing');
assert.ok(moduleSource.includes('data-statement-export'), 'Payer statement CSV export control is missing');
assert.ok(moduleSource.includes('net_commission_amount') || moduleSource.includes('net_commission'), 'Payer statement must calculate net commission after adjustments');
assert.ok(moduleSource.includes('ليس فاتورة ضريبية') || moduleSource.includes('إثبات تحصيل نقدي'), 'Payer statement must disclose that it is not tax invoice or cash-settlement evidence');

const statementHelperStart = moduleSource.indexOf('function statementCsvCell');
const statementHelperEnd = moduleSource.indexOf('async function fetchStatementPages', statementHelperStart);
assert.ok(statementHelperStart >= 0 && statementHelperEnd > statementHelperStart, 'Commission statement helpers are missing');
const statementSandbox = {};
vm.runInNewContext(
  moduleSource.slice(statementHelperStart, statementHelperEnd) +
    '\n globalThis.buildCommissionStatementRows = buildCommissionStatementRows;' +
    '\n globalThis.summarizeCommissionStatement = summarizeCommissionStatement;' +
    '\n globalThis.statementCsvCell = statementCsvCell;',
  statementSandbox
);
const statementLedger = [
  {id:'l1',recorded_at:'2026-11-02T10:00:00Z',activity_type:'market_materials',source_type:'project_delivery',source_id:'d1:SDG',gross_amount:1000,currency:'SDG',rate_percent:5,commission_amount:50,status:'due'},
  {id:'l2',recorded_at:'2026-11-03T10:00:00Z',activity_type:'contracting',source_type:'project_service_award',source_id:'a1:USD',gross_amount:200,currency:'USD',rate_percent:5,commission_amount:10,status:'paid'}
];
const statementAdjustments = [
  {id:'a1',ledger_id:'l1',created_at:'2026-11-04T10:00:00Z',adjustment_kind:'partial_refund',amount_delta:-15,currency:'SDG',reason:'Partial reversal',source_reference:'refund-1'},
  {id:'a2',ledger_id:'l2',created_at:'2026-11-05T10:00:00Z',adjustment_kind:'fee_increase',amount_delta:2,currency:'USD',reason:'Fee correction',source_reference:'correction-1'}
];
const statementRows = statementSandbox.buildCommissionStatementRows(statementLedger,statementAdjustments,statementLedger);
const statementTotals = statementSandbox.summarizeCommissionStatement(statementRows);
assert.equal(statementRows.length,4,'Statement must include each commission and adjustment as separate rows');
assert.equal(statementRows[2].record_type,'adjustment','Statement rows must be chronologically ordered');
assert.equal(statementRows[2].source_reference,'refund-1','Adjustment source reference must be retained');
assert.equal(statementTotals.length,2,'Statement totals must never combine different currencies');
assert.equal(statementTotals.find(x=>x.currency==='SDG').net_activity,35,'SDG net activity must include its negative adjustment');
assert.equal(statementTotals.find(x=>x.currency==='USD').net_activity,12,'USD net activity must include its positive adjustment');
const priorMonthLedger = [
  {id:'old-l1',recorded_at:'2026-10-31T23:59:59Z',activity_type:'market_materials',source_type:'project_delivery',source_id:'delivery-old',gross_amount:900,currency:'SDG',rate_percent:5,commission_amount:45,status:'due'}
];
const currentMonthAdjustment = [
  {id:'a3',ledger_id:'old-l1',created_at:'2026-11-01T00:00:00Z',adjustment_kind:'partial_refund',amount_delta:-5,currency:'SDG',reason:'Adjustment in selected month',source_reference:'nov-refund'}
];
const periodRows = statementSandbox.buildCommissionStatementRows([],currentMonthAdjustment,priorMonthLedger);
assert.equal(periodRows.length,1,'A current-period adjustment must appear even when its original commission belongs to a prior month');
assert.equal(periodRows[0].source_id,'delivery-old','Prior-period source metadata must be resolved for a current-period adjustment');
assert.equal(periodRows[0].source_reference,'nov-refund','Current-period adjustment must retain its external source reference');
const periodTotals = statementSandbox.summarizeCommissionStatement(periodRows);
assert.equal(periodTotals[0].gross_amount,0,'An adjustment-only period must not duplicate prior-period GMV');
assert.equal(periodTotals[0].commission_count,0,'An adjustment-only period must not count a prior-period commission as a new commission');
assert.equal(periodTotals[0].net_activity,-5,'An adjustment-only period total must include the adjustment delta');
assert.equal(statementSandbox.statementCsvCell('=SUM(A1:A2)','reason'),'"\'=SUM(A1:A2)"','CSV text cells must be guarded against formula injection');
assert.equal(statementSandbox.statementCsvCell(-15,'adjustment_delta'),'"-15"','Signed numeric adjustments must remain numeric in CSV');


assert.ok(moduleSource.includes('Date.UTC(year,monthNumber-1,1)'), 'Monthly statement start must use a UTC calendar boundary');
assert.ok(moduleSource.includes('Date.UTC(year,monthNumber,1)'), 'Monthly statement end must use a UTC calendar boundary');
assert.ok(moduleSource.includes('شهر الكشف (UTC)'), 'Monthly statement timezone must be disclosed in the UI');
assert.ok(moduleSource.includes("if(!/^\\d{4}-(0[1-9]|1[0-2])$/.test(month))"), 'Monthly statement must validate YYYY-MM using a real digit escape');
assert.doesNotMatch(moduleSource, /if\(!\/\^\\\\d\{4\}/, 'Monthly statement must not use an escaped literal backslash instead of a digit class');


const accountResetStart = moduleSource.indexOf('function resetAccountState(){');
const accountResetEnd = moduleSource.indexOf('function start(sessionUser)', accountResetStart);
assert.ok(accountResetStart >= 0 && accountResetEnd > accountResetStart, 'Account-scoped reset helper must exist before session startup');
const accountResetBody = moduleSource.slice(accountResetStart, accountResetEnd);
for (const stateName of ['supplier=null','provider=null','products=[]','myProducts=[]','projects=[]','serviceProviders=[]','availableConversations=[]','revenueRows=[]','revenueAdjustments=[]','activeConversation=null','replyToMessageId=null','tab=\'market\'','isAdmin=false']) {
  assert.ok(accountResetBody.includes(stateName), 'Account switch reset must clear ' + stateName);
}
assert.ok(accountResetBody.includes('db.removeChannel(messageChannel)'), 'Account reset must detach the previous user realtime channel');
assert.ok(accountResetBody.includes("$('ecoPanel').replaceChildren()"), 'Account reset must clear rendered account-specific content');
assert.ok(moduleSource.includes('if(user&&user.id!==sessionUser.id)resetAccountState();'), 'Switching directly between signed-in accounts must clear the previous account state');
assert.match(moduleSource, /onAuthStateChange\(\(event,session\)=>\{[\s\S]*?else\{\s*resetAccountState\(\);/, 'Sign-out events must clear account-scoped state');

