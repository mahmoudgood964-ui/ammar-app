(function () {
'use strict';
const $ = id => document.getElementById(id);
const esc = v => String(v == null ? '' : v).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const labels = {supplier:'مورد',contractor:'مقاول',service_provider:'مقدم خدمة',transport:'ناقل / شركة نقل',other:'جهة أخرى'};
const s = {db:null,user:null,projects:[],projectId:'',team:false,invites:[],quotes:[],deliveries:[],items:[],loading:false,mounted:false};

function styles(){
 if($('ammirPerformanceStyles'))return;
 const el=document.createElement('style');el.id='ammirPerformanceStyles';
 el.textContent=
 '#ammirPerformanceView{display:none}#ammirPerformanceView.active{display:block}'+
 '.perf-shell{background:#fff;border:1px solid var(--line);border-radius:18px;padding:20px;min-height:480px}'+
 '.perf-head{display:flex;justify-content:space-between;align-items:flex-start;gap:14px;flex-wrap:wrap;margin-bottom:18px}'+
 '.perf-head h2{margin:0;color:var(--gd);font-size:23px}.perf-head p{margin:6px 0 0;color:var(--muted);font-size:13px;line-height:1.8}'+
 '.perf-actions{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.perf-select{border:1px solid #d9e2dc;background:#fff;border-radius:10px;padding:10px 12px;color:var(--ink);min-width:190px;max-width:100%;font:inherit}'+
 '.perf-kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:11px;margin:16px 0}.perf-kpi{border:1px solid var(--line);border-radius:14px;padding:15px;background:#fff;min-width:0}'+
 '.perf-kpi small{display:block;color:var(--muted);font-size:11px;line-height:1.6}.perf-kpi strong{display:block;color:var(--gd);font-size:27px;margin-top:6px;direction:ltr;text-align:right;overflow-wrap:anywhere}.perf-kpi span{display:block;color:#87928c;font-size:10px;margin-top:4px;line-height:1.6}'+
 '.perf-panel{border:1px solid var(--line);border-radius:15px;padding:16px;margin-top:14px}.perf-panel h3{margin:0 0 5px;color:var(--gd);font-size:16px}.perf-panel>p{margin:0 0 12px;color:var(--muted);font-size:11px;line-height:1.8}'+
 '.perf-table-wrap{overflow-x:auto}.perf-table{width:100%;border-collapse:collapse;min-width:720px;font-size:12px}.perf-table th,.perf-table td{padding:12px 10px;text-align:right;border-bottom:1px solid #edf1ee;vertical-align:middle}.perf-table th{color:#718078;font-size:11px;font-weight:700;background:#f8faf8;white-space:nowrap}.perf-table tr:last-child td{border-bottom:0}'+
 '.perf-provider strong{display:block;color:var(--gd);font-size:13px}.perf-provider small{display:block;color:var(--muted);font-size:10px;margin-top:3px}.perf-value{font-weight:800;color:var(--gd);direction:ltr;white-space:nowrap}.perf-sample{display:inline-flex;padding:4px 8px;border-radius:20px;background:#f1f4f1;color:#637168;font-size:10px;white-space:nowrap}'+
 '.perf-note{border-right:3px solid #b58b5c;background:#f7f8f5;border-radius:9px;padding:11px 13px;color:#5f6d64;font-size:11px;line-height:1.9;margin-top:13px}.perf-empty{border:1px dashed #cbd8d0;border-radius:12px;padding:25px;text-align:center;color:var(--muted);font-size:13px;line-height:1.9}.perf-error{background:#fff0ef;border:1px solid #f1d3d0;color:#982b24;border-radius:10px;padding:12px;font-size:12px;line-height:1.8}.perf-loading{padding:35px;text-align:center;color:var(--muted);font-size:13px}.perf-muted{color:var(--muted);font-size:11px}'+
 '@media(max-width:850px){.perf-kpis{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:600px){.perf-shell{padding:13px}.perf-head h2{font-size:20px}.perf-kpi{padding:12px}.perf-kpi strong{font-size:23px}.perf-actions{width:100%}.perf-select{flex:1;min-width:0;width:100%}.perf-panel{padding:12px}}';
 document.head.appendChild(el);
}
function navButton(compact){
 const b=document.createElement('button');b.type='button';b.className='nav-btn';b.dataset.ammirPerformanceOpen='1';
 b.innerHTML='<span class="nav-icon">◷</span>'+(compact?'الأداء':'أداء الموردين والمقاولين');return b;
}
function mount(){
 if(s.mounted||!document.querySelector('#appShell .content'))return;
 styles();
 const side=document.querySelector('#appShell .sidebar'),mobile=document.querySelector('#appShell .mobile-nav');
 if(side&&!side.querySelector('[data-ammir-performance-open]'))side.insertBefore(navButton(false),side.querySelector('.sidebar-bottom')||null);
 if(mobile&&!mobile.querySelector('[data-ammir-performance-open]'))mobile.insertBefore(navButton(true),mobile.lastElementChild);
 const view=document.createElement('section');view.id='ammirPerformanceView';view.className='view';
 view.innerHTML='<div class="perf-shell"><header class="perf-head"><div><h2>أداء الموردين والمقاولين</h2><p id="perfIntro">مؤشرات محسوبة من دعوات عروض الأسعار وسجلات التسليم الفعلية.</p></div><div class="perf-actions"><select id="perfProjectSelect" class="perf-select" aria-label="اختر المشروع" hidden></select><button class="btn light" type="button" data-perf-refresh>تحديث البيانات</button></div></header><div id="perfMessage" role="status" aria-live="polite"></div><div id="perfContent"><div class="perf-loading">جارٍ تحميل سجلات الأداء…</div></div></div>';
 document.querySelector('#appShell .content').appendChild(view);
 view.addEventListener('click',e=>{if(e.target.closest('[data-perf-refresh]'))load().catch(showError);});
 view.addEventListener('change',e=>{if(e.target.id==='perfProjectSelect'){s.projectId=e.target.value;render();}});
 s.mounted=true;
}
function open(){
 if(!s.user||!s.mounted)return;
 document.querySelectorAll('#appShell .content > .view').forEach(v=>v.classList.remove('active'));
 $('ammirPerformanceView').classList.add('active');
 document.querySelectorAll('#appShell [data-view],#appShell [data-ammar-open],#appShell [data-ammir-performance-open]').forEach(b=>b.classList.remove('active'));
 document.querySelectorAll('[data-ammir-performance-open]').forEach(b=>b.classList.add('active'));
 $('detailBackdrop')?.setAttribute('hidden','');load().catch(showError);
}
async function fetchAll(table,columns,filter,orderColumn){
 const out=[],size=500;
 for(let offset=0;offset<10000;offset+=size){
  let q=s.db.from(table).select(columns);if(filter)q=filter(q);if(orderColumn)q=q.order(orderColumn,{ascending:true});
  const r=await q.range(offset,offset+size-1);if(r.error)throw r.error;
  const page=r.data||[];out.push(...page);if(page.length<size)return out;
 }
 throw new Error('تجاوز عدد السجلات حد القراءة الآمن. استخدم مرشح المشروع أو الفترة.');
}
async function load(){
 if(!s.db||!s.user||s.loading)return;s.loading=true;
 $('perfMessage').innerHTML='';$('perfContent').innerHTML='<div class="perf-loading">جارٍ قراءة السجلات المصرح بها…</div>';
 try{
  const p=await s.db.from('projects').select('id,title,created_at').order('created_at',{ascending:false}).limit(300);
  if(p.error)throw p.error;s.projects=p.data||[];s.team=s.projects.length>0;
  const ids=s.projects.map(x=>x.id);if(s.team&&!ids.includes(s.projectId))s.projectId=ids[0]||'';
  if(s.team&&!ids.length){s.invites=[];s.quotes=[];s.deliveries=[];s.items=[];}
  else{
   const fi=q=>s.team?q.in('project_id',ids):q.eq('provider_user_id',s.user.id);
   const fd=q=>s.team?q.in('project_id',ids):q.eq('supplier_user_id',s.user.id);
   const data=await Promise.all([
    fetchAll('ammir_project_rfq_invites','id,rfq_id,project_id,provider_user_id,provider_type,provider_name_snapshot,status,invited_at,responded_at',fi,'invited_at'),
    fetchAll('ammir_project_rfq_quotes','id,rfq_id,project_id,provider_user_id,status,submitted_at,created_at',fi,'created_at'),
    fetchAll('ammir_project_deliveries','id,project_id,supplier_user_id,scheduled_at,received_at,status,delivery_reference,created_at',fd,'created_at')
   ]);
   s.invites=data[0];s.quotes=data[1];s.deliveries=data[2];
   const deliveryIds=s.deliveries.map(x=>x.id);
   s.items=deliveryIds.length?await fetchAll('ammir_project_delivery_items','id,delivery_id,project_id,expected_quantity,received_quantity,damaged_quantity,missing_quantity',q=>q.in('delivery_id',deliveryIds),'created_at'):[];
  }
  render();
 }finally{s.loading=false;}
}
function pct(n,d){return d>0?Math.round(n/d*100):null;}
function pctText(v){return v==null?'—':v+'%';}
function fmt(v,d=0){return new Intl.NumberFormat('ar',{maximumFractionDigits:d}).format(v||0);}
function dateEnd(v){if(!v)return null;const d=new Date(v+'T23:59:59');return Number.isNaN(d.getTime())?null:d;}
function hours(a,b){if(!a||!b)return null;const n=(new Date(b)-new Date(a))/3600000;return Number.isFinite(n)&&n>=0?n:null;}
function sample(n){return '<span class="perf-sample">'+fmt(n)+(n===1?' سجل':' سجلات')+'</span>';}
function groupsForView(){
 const pid=s.projectId;
 const inv=s.team?s.invites.filter(x=>x.project_id===pid):s.invites;
 const quotes=s.team?s.quotes.filter(x=>x.project_id===pid):s.quotes;
 const deliveries=s.team?s.deliveries.filter(x=>x.project_id===pid):s.deliveries;
 const dids=new Set(deliveries.map(x=>x.id)),items=s.items.filter(x=>dids.has(x.delivery_id)),map=new Map();
 function get(id,type,name){
  const key=id||('unknown-'+(type||'provider'));
  if(!map.has(key))map.set(key,{id,type:type||'other',name:name||'مقدم خدمة مسجل',invites:[],quotes:[],deliveries:[],items:[]});
  const g=map.get(key);if(name&&g.name==='مقدم خدمة مسجل')g.name=name;if(type&&g.type==='other')g.type=type;return g;
 }
 inv.forEach(x=>get(x.provider_user_id,x.provider_type,x.provider_name_snapshot).invites.push(x));
 quotes.forEach(x=>get(x.provider_user_id,null,null).quotes.push(x));
 deliveries.forEach(x=>get(x.supplier_user_id,null,null).deliveries.push(x));
 items.forEach(x=>{const d=deliveries.find(y=>y.id===x.delivery_id);if(d)get(d.supplier_user_id,null,null).items.push(x);});
 return [...map.values()].map(g=>{
  const quoteMap=new Map();
  g.quotes.filter(q=>q.status==='submitted'&&q.submitted_at).forEach(q=>{if(!quoteMap.has(q.rfq_id)||new Date(q.submitted_at)<new Date(quoteMap.get(q.rfq_id).submitted_at))quoteMap.set(q.rfq_id,q);});
  let responded=0;const times=[];
  g.invites.forEach(i=>{const q=quoteMap.get(i.rfq_id),at=q?.submitted_at||i.responded_at;const yes=!!q||['accepted','declined'].includes(i.status)||!!i.responded_at;if(yes)responded++;const h=hours(i.invited_at,at);if(h!=null)times.push(h);});
  const valid=g.deliveries.filter(d=>d.status!=='cancelled'),today=new Date();
  const due=valid.filter(d=>!!d.received_at||(!!dateEnd(d.scheduled_at)&&dateEnd(d.scheduled_at)<=today));
  const ontime=due.filter(d=>{const end=dateEnd(d.scheduled_at);return !!d.received_at&&!!end&&new Date(d.received_at)<=end&&d.status==='received';}).length;
  const goodItems=g.items.filter(x=>valid.some(d=>d.id===x.delivery_id));
  const expected=goodItems.reduce((n,x)=>n+Number(x.expected_quantity||0),0),received=goodItems.reduce((n,x)=>n+Number(x.received_quantity||0),0);
  const measured=new Set(goodItems.map(x=>x.delivery_id));
  const complete=new Set(valid.filter(d=>{const lines=goodItems.filter(x=>x.delivery_id===d.id);return lines.length>0&&lines.every(x=>Number(x.received_quantity)>=Number(x.expected_quantity)&&Number(x.damaged_quantity||0)===0&&Number(x.missing_quantity||0)===0);}).map(x=>x.id));
  return {...g,responseRate:pct(responded,g.invites.length),responded,submitted:g.quotes.filter(x=>x.status==='submitted').length,avg:times.length?times.reduce((a,b)=>a+b,0)/times.length:null,dueCount:due.length,onTime:ontime,onTimeRate:pct(ontime,due.length),expected,received,completion:pct(received,expected),measured:measured.size,complete:complete.size};
 }).sort((a,b)=>(b.invites.length+b.deliveries.length)-(a.invites.length+a.deliveries.length));
}
function render(){
 const select=$('perfProjectSelect');
 if(s.team){
  select.hidden=false;select.innerHTML=s.projects.map(p=>'<option value="'+esc(p.id)+'" '+(p.id===s.projectId?'selected':'')+'>'+esc(p.title||'مشروع بلا عنوان')+'</option>').join('');
  $('perfIntro').textContent='تعرض هذه الصفحة بيانات المشروع المحدد فقط. لا تُدمج سجلات المشاريع المختلفة في تقييم واحد.';
 }else{select.hidden=true;$('perfIntro').textContent='ملخص خاص بحسابك من تعاملاتك المسجلة. لا تظهر أسماء المشاريع أو بيانات العملاء أو عروض الأطراف الأخرى.';}
 const gs=groupsForView(),inv=gs.reduce((n,g)=>n+g.invites.length,0),resp=gs.reduce((n,g)=>n+g.responded,0),due=gs.reduce((n,g)=>n+g.dueCount,0),ontime=gs.reduce((n,g)=>n+g.onTime,0),exp=gs.reduce((n,g)=>n+g.expected,0),rec=gs.reduce((n,g)=>n+g.received,0);
 const avg=gs.filter(g=>g.avg!=null).map(g=>g.avg),mean=avg.length?avg.reduce((a,b)=>a+b,0)/avg.length:null;
 const cards='<div class="perf-kpis">'+
 '<article class="perf-kpi"><small>الاستجابة لدعوات عروض الأسعار</small><strong>'+pctText(pct(resp,inv))+'</strong><span>'+fmt(resp)+' استجابة من '+fmt(inv)+' دعوة</span></article>'+
 '<article class="perf-kpi"><small>التسليم في الموعد</small><strong>'+pctText(pct(ontime,due))+'</strong><span>'+fmt(ontime)+' في الموعد من '+fmt(due)+' تسليم مستحق</span></article>'+
 '<article class="perf-kpi"><small>اكتمال الكميات المستلمة</small><strong>'+pctText(pct(rec,exp))+'</strong><span>'+fmt(rec,2)+' من '+fmt(exp,2)+' وحدة مسجلة</span></article>'+
 '<article class="perf-kpi"><small>متوسط زمن الاستجابة</small><strong>'+(mean==null?'—':fmt(mean,1))+'</strong><span>'+(mean==null?'لا توجد أزمنة استجابة مكتملة':'ساعة من الدعوة إلى الرد')+'</span></article></div>';
 if(!gs.length){$('perfContent').innerHTML=cards+'<div class="perf-empty">لا توجد سجلات أداء كافية لهذا النطاق حتى الآن.<br>ستظهر المؤشرات بعد تسجيل دعوات عروض الأسعار والردود والتسليمات الفعلية.</div>';return;}
 const rows=gs.map(g=>{
  const deliveryText=g.measured?fmt(g.complete)+' / '+fmt(g.measured)+' مكتمل':'لا توجد بنود تسليم';
  const name=s.team?g.name:'أداؤك المسجل',type=s.team?(labels[g.type]||labels.other):'حساب مقدم الخدمة';
  return '<tr><td class="perf-provider"><strong>'+esc(name)+'</strong><small>'+esc(type)+'</small></td>'+
  '<td><span class="perf-value">'+pctText(g.responseRate)+'</span><br>'+sample(g.invites.length)+'<small class="perf-muted">'+fmt(g.submitted)+' عرض مرسل</small></td>'+
  '<td><span class="perf-value">'+pctText(g.onTimeRate)+'</span><br>'+sample(g.dueCount)+'</td>'+
  '<td><span class="perf-value">'+pctText(g.completion)+'</span><br>'+sample(g.measured)+'<small class="perf-muted">'+esc(deliveryText)+'</small></td>'+
  '<td><span class="perf-value">'+(g.avg==null?'—':fmt(g.avg,1)+' س')+'</span><br><small class="perf-muted">'+fmt(g.deliveries.length)+' تسليم مسجل</small></td></tr>';
 }).join('');
 $('perfContent').innerHTML=cards+'<section class="perf-panel"><h3>'+(s.team?'مقارنة أداء الجهات في هذا المشروع':'ملخص أدائك')+'</h3><p>'+(s.team?'كل صف يخص مورداً أو مقاولاً داخل المشروع المختار فقط. لا تُعرض تفاصيل عروض الأسعار أو أسماء المشاريع الأخرى.':'هذه مؤشرات مجمعة لسجلات حسابك فقط، ولا تكشف هوية العملاء أو تفاصيل المشاريع.')+'</p><div class="perf-table-wrap"><table class="perf-table"><thead><tr><th>'+(s.team?'المورد / المقاول':'الجهة')+'</th><th>استجابة RFQ</th><th>الالتزام بالموعد</th><th>اكتمال التسليم</th><th>زمن الاستجابة / التسليمات</th></tr></thead><tbody>'+rows+'</tbody></table></div></section><div class="perf-note">منهجية القياس: الاستجابة تُحسب من قبول/رفض الدعوة أو إرسال عرض؛ الالتزام يُحسب للتسليمات المستحقة فقط؛ اكتمال التسليم يعتمد على الكميات المستلمة مقارنة بالكميات المتوقعة. لا تُنشأ درجة إجمالية أو ترتيب تنافسي، ولا تُعرض نسبة عند غياب مقام قياس صالح. العينة الصغيرة لا تكفي وحدها للحكم على الجهة.</div>';
}
function showError(error){
 const target=$('perfContent');if(target)target.innerHTML='<div class="perf-error">تعذر تحميل بيانات الأداء. لم نعرض أصفاراً بديلة حتى لا نخلط بين غياب السجلات وفشل القراءة.<br>'+esc(error?.message||'خطأ غير معروف')+'</div>';
}
function start(user){s.user=user||null;if(!s.user)return;mount();if(s.mounted)load().catch(showError);}
function boot(){
 const wait=()=>{if(!window.ammarSupabase){setTimeout(wait,120);return;}
  s.db=window.ammarSupabase;
  s.db.auth.onAuthStateChange((event,session)=>{if(session?.user)start(session.user);else{s.user=null;s.projects=[];s.invites=[];s.quotes=[];s.deliveries=[];s.items=[];$('ammirPerformanceView')?.classList.remove('active');}});
  s.db.auth.getSession().then(r=>{if(r.data?.session?.user)start(r.data.session.user);}).catch(e=>console.warn('AMMIR performance dashboard:',e?.message));
 };
 wait();
 document.addEventListener('click',e=>{if(e.target.closest('[data-ammir-performance-open]')){e.preventDefault();open();}});
 window.openAmmirPerformance=open;
}
boot();
})();