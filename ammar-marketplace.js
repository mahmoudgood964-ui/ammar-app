(function () {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const esc = (v) => String(v == null ? '' : v).replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));
  const money = (v,c) => `${new Intl.NumberFormat('en-US',{maximumFractionDigits:2}).format(Number(v||0))} ${esc(c||'SDG')}`;
  const short = (v) => String(v||'').slice(0,8);
  const statusText = {
    submitted:'مرسل',quoted:'وصل عرض سعر',accepted:'مقبول',fulfilling:'قيد التوريد',
    delivered:'تم التسليم',completed:'مكتمل',cancelled:'ملغي',disputed:'قيد النزاع',
    proposed:'عرض مقدم',rejected:'مرفوض',open:'مفتوح',awarded:'تم اختيار مقدم الخدمة'
  };

  let db=null,user=null,supplier=null,provider=null,products=[],myProducts=[],projects=[];
  let tab='market',activeConversation=null,messageChannel=null,refreshTimer=null,presenceTimer=null,mounted=false;
  let replyToMessageId=null,availableConversations=[],showLastSeen=true;

  function styles(){
    if($('ammarEcosystemStyles'))return;
    const s=document.createElement('style');s.id='ammarEcosystemStyles';
    s.textContent=`
      #ammarEcosystemView{display:none}#ammarEcosystemView.active{display:block}
      .eco-shell{background:#fff;border:1px solid var(--line);border-radius:16px;padding:18px;min-height:560px}
      .eco-header{display:flex;align-items:flex-start;justify-content:space-between;gap:14px;flex-wrap:wrap;margin-bottom:16px}
      .eco-header h2{margin:0;color:var(--gd);font-size:24px}.eco-header p{margin:5px 0 0;color:var(--muted);font-size:13px}
      .eco-tabs{display:flex;gap:7px;flex-wrap:wrap;padding:8px;background:#f5f8f6;border-radius:12px;margin-bottom:18px}
      .eco-tab{border:0;border-radius:9px;padding:9px 13px;background:transparent;color:#52615a;font-weight:700;font-size:13px}
      .eco-tab.active{background:var(--gd);color:#fff}
      .eco-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:13px}
      .eco-card{border:1px solid var(--line);border-radius:13px;padding:14px;min-width:0;background:#fff}
      .eco-card h3{font-size:15px;color:var(--gd);margin:0 0 8px;overflow-wrap:anywhere}
      .eco-card p{margin:5px 0;color:#52615a;font-size:13px;white-space:pre-wrap;overflow-wrap:anywhere}
      .eco-meta{display:flex;flex-wrap:wrap;gap:6px;margin:9px 0}
      .eco-pill{display:inline-flex;border-radius:20px;padding:4px 8px;background:#eef4f0;color:#496057;font-size:11px}
      .eco-price{font-size:20px;font-weight:800;color:var(--gd);margin:8px 0}
      .eco-form{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}
      .eco-form label{display:block;font-size:12px;font-weight:700;color:#46564d;margin-bottom:5px}
      .eco-form input,.eco-form select,.eco-form textarea,.eco-inline-input{width:100%;border:1px solid #d9e2dc;border-radius:9px;padding:10px;background:#fff;color:var(--ink);font:inherit;min-width:0}
      .eco-form textarea{min-height:84px;resize:vertical}.eco-form .wide{grid-column:1/-1}
      .eco-actions{display:flex;align-items:center;gap:7px;flex-wrap:wrap;margin-top:12px}
      .eco-actions .btn{font-size:12px;padding:8px 11px}
      .eco-empty{border:1px dashed #cbd8d0;border-radius:12px;padding:24px;text-align:center;color:var(--muted);font-size:13px;grid-column:1/-1}
      .eco-note{background:#f4f8f5;border-right:3px solid var(--g);border-radius:8px;padding:11px 13px;font-size:12px;color:#52615a;margin:12px 0}
      .eco-row{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:10px 0;border-bottom:1px solid var(--line);flex-wrap:wrap}
      .eco-row:last-child{border-bottom:0}
      .eco-messages{display:grid;grid-template-columns:260px minmax(0,1fr);gap:12px;min-height:420px}
      .eco-chat-list{border:1px solid var(--line);border-radius:12px;padding:8px;max-height:560px;overflow:auto}
      .eco-chat-item{display:block;text-align:right;width:100%;border:0;border-radius:9px;padding:10px;background:transparent;color:var(--ink);margin-bottom:4px}
      .eco-chat-item.active,.eco-chat-item:hover{background:#edf5f0}
      .eco-chat-item strong{display:block;color:var(--gd);font-size:13px}
      .eco-chat-item small{display:block;color:var(--muted);font-size:11px;overflow-wrap:anywhere}
      .eco-chat-pane{border:1px solid var(--line);border-radius:12px;display:flex;flex-direction:column;min-width:0;min-height:420px}
      .eco-chat-head{padding:11px 13px;border-bottom:1px solid var(--line);font-weight:700;color:var(--gd)}
      .eco-chat-body{padding:13px;flex:1;overflow:auto;max-height:430px;background:#fafcfb}
      .eco-bubble{max-width:82%;padding:9px 11px;border-radius:12px;background:#edf3ef;margin:8px 0 8px auto;overflow-wrap:anywhere;font-size:13px}
      .eco-bubble.mine{background:#dceee5;margin:8px auto 8px 0}
      .eco-bubble small{display:block;color:#718078;font-size:10px;margin-top:4px}
      .eco-chat-send{display:flex;gap:7px;padding:10px;border-top:1px solid var(--line);flex-wrap:wrap}
      .eco-chat-send input[type=text]{flex:1;min-width:100px;border:1px solid var(--line);border-radius:9px;padding:10px}
      .eco-chat-send input[type=file]{max-width:180px}
      .eco-message-actions{display:flex;gap:5px;flex-wrap:wrap;margin-top:7px}
      .eco-message-actions button{border:1px solid #dce6df;background:#fff;border-radius:7px;padding:4px 7px;font-size:10px;color:#486056}
      .eco-chat-toolbar{display:flex;gap:7px;flex-wrap:wrap;margin-bottom:8px}
      .eco-chat-toolbar input,.eco-chat-toolbar select{border:1px solid var(--line);border-radius:8px;padding:8px;min-width:0}
      .eco-chat-head-actions{display:flex;gap:6px;flex-wrap:wrap;margin-top:7px}
      .eco-chat-head-actions .btn{font-size:11px;padding:6px 9px}
      .eco-reply-preview{border-right:3px solid var(--g);background:#f1f6f3;padding:6px 9px;margin:4px 0 8px;border-radius:7px;font-size:11px;color:#506159}
      .eco-bubble video{max-width:240px;width:100%;border-radius:9px}
      .eco-presence{font-size:11px;color:var(--muted);font-weight:400}
      .eco-subsection{margin-bottom:18px}.eco-subsection h3{font-size:16px;color:var(--gd);margin:0 0 11px}
      @media(max-width:760px){.eco-grid{grid-template-columns:1fr}.eco-messages{grid-template-columns:1fr}.eco-chat-list{max-height:190px}.eco-chat-pane{min-height:380px}.eco-form{grid-template-columns:1fr}.eco-form .wide{grid-column:auto}.eco-shell{padding:12px}.eco-header h2{font-size:21px}}
    `;
    document.head.appendChild(s);
  }

  function nav(){
    const sidebar=document.querySelector('.sidebar'),mobile=document.querySelector('.mobile-nav');
    const make=(small)=>{
      const b=document.createElement('button');b.type='button';b.className='nav-btn';b.dataset.ammarOpen='market';
      b.innerHTML='<span class="nav-icon">▦</span>'+(small?'السوق':'السوق والرسائل')+' <span class="notification-badge eco-unread-count" data-eco-unread hidden>0</span>';
      return b;
    };
    if(sidebar&&!sidebar.querySelector('[data-ammar-open]'))sidebar.insertBefore(make(false),sidebar.querySelector('.sidebar-bottom')||null);
    if(mobile&&!mobile.querySelector('[data-ammar-open]'))mobile.insertBefore(make(true),mobile.lastElementChild);
  }

  function mount(){
    if(mounted||!document.querySelector('#appShell .content'))return;
    styles();nav();
    const view=document.createElement('section');view.id='ammarEcosystemView';view.className='view';
    view.innerHTML=`
      <div class="eco-shell">
        <div class="eco-header"><div><h2>سوق عَمِّر والتواصل التجاري</h2><p>مواد البناء والموردون وطلبات الشراء والمراسلات والاتفاقات في مساحة واحدة.</p></div><button class="btn light" type="button" data-eco-action="refresh">تحديث البيانات</button></div>
        <div class="eco-tabs" role="tablist">
          <button class="eco-tab active" type="button" data-eco-tab="market">السوق</button>
          <button class="eco-tab" type="button" data-eco-tab="orders">طلبات الشراء</button>
          <button class="eco-tab" type="button" data-eco-tab="messages">الرسائل</button>
          <button class="eco-tab" type="button" data-eco-tab="supplier">حساب المورد</button>
          <button class="eco-tab" type="button" data-eco-tab="services">المقاولون والخدمات</button>
          <button class="eco-tab" type="button" data-eco-tab="agreements">الاتفاقات</button>
        </div>
        <div id="ecoNotice" class="message" role="status" aria-live="polite"></div>
        <div id="ecoPanel"><div class="eco-empty">جارٍ تحميل سوق عَمِّر...</div></div>
      </div>`;
    document.querySelector('#appShell .content').appendChild(view);
    view.addEventListener('click',click);view.addEventListener('submit',submit);
    view.addEventListener('input',e=>{if(e.target.id==='ecoChatSearch')filterChatList();if(e.target.id==='ecoMessageSearch')filterMessageBubbles();});
    view.addEventListener('change',e=>{if(e.target.id==='ecoChatFilter')filterChatList();});
    mounted=true;
  }

  function tell(text,type='info'){
    const el=$('ecoNotice');if(!el)return;el.textContent=text||'';el.className='message'+(text?' '+type:'');
  }

  function open(next='market'){
    if(!user||!mounted)return;
    document.querySelectorAll('#appShell .content > .view').forEach(v=>v.classList.remove('active'));
    $('ammarEcosystemView')?.classList.add('active');
    document.querySelectorAll('#appShell [data-view],#appShell [data-ammar-open]').forEach(b=>b.classList.remove('active'));
    document.querySelectorAll('[data-ammar-open]').forEach(b=>b.classList.add('active'));
    $('detailBackdrop')?.setAttribute('hidden','');
    chooseTab(next);
  }

  async function loadProfiles(){
    const [s,p]=await Promise.all([
      db.from('ammar_market_suppliers').select('*').eq('owner_id',user.id).maybeSingle(),
      db.from('ammar_service_providers').select('*').eq('owner_id',user.id).maybeSingle()
    ]);
    if(s.error)throw s.error;if(p.error)throw p.error;
    supplier=s.data||null;provider=p.data||null;
  }

  async function loadProducts(){
    const r=await db.from('ammar_market_products')
      .select('id,supplier_id,title,category,brand,description,unit,price,currency,quantity_available,availability,image_path,price_updated_at,supplier:ammar_market_suppliers!inner(id,owner_id,business_name,governorate,city,area,market_name,is_verified)')
      .eq('is_active',true).neq('availability','unavailable')
      .order('created_at',{ascending:false}).limit(150);
    if(r.error)throw r.error;products=r.data||[];
  }

  async function loadMyProducts(){
    if(!supplier){myProducts=[];return;}
    const r=await db.from('ammar_market_products').select('*').eq('supplier_id',supplier.id).order('created_at',{ascending:false});
    if(r.error)throw r.error;myProducts=r.data||[];
  }

  async function loadProjects(){
    const own=await db.from('projects').select('id,title,created_at').eq('client_id',user.id).order('created_at',{ascending:false}).limit(100);
    if(own.error)throw own.error;
    const m=await db.from('project_members').select('project_id').eq('user_id',user.id);
    if(m.error)throw m.error;
    const ids=[...new Set((m.data||[]).map(x=>String(x.project_id)).filter(Boolean))];
    let shared=[];
    if(ids.length){const r=await db.from('projects').select('id,title,created_at').in('id',ids);if(r.error)throw r.error;shared=r.data||[];}
    const seen=new Set();projects=[...(own.data||[]),...shared].filter(p=>{const k=String(p.id);if(seen.has(k))return false;seen.add(k);return true;});
  }

  async function refreshUnreadCount(){
    const badges=document.querySelectorAll('[data-eco-unread]');if(!badges.length||!user)return;
    const r=await db.from('ammar_user_notifications').select('id',{count:'exact',head:true}).eq('user_id',user.id).is('read_at',null);
    if(r.error)return;
    badges.forEach(b=>{b.textContent=String(r.count||0);b.hidden=!r.count;});
  }

  function chooseTab(next){
    tab=next;document.querySelectorAll('[data-eco-tab]').forEach(b=>b.classList.toggle('active',b.dataset.ecoTab===next));
    render().catch(e=>tell('تعذر تحميل القسم: '+(e.message||'خطأ غير معروف'),'error'));
  }

  async function render(){
    if(!db||!user)return;tell('');
    await refreshUnreadCount();
    const panel=$('ecoPanel');if(!panel)return;
    if(tab==='market'){
      await Promise.all([loadProducts(),loadProjects()]);
      panel.innerHTML=marketHtml();bindMarketFilters();
    }else if(tab==='supplier'){
      await loadProfiles();await loadMyProducts();panel.innerHTML=supplierHtml();
    }else if(tab==='orders'){
      await loadProfiles();panel.innerHTML=await ordersHtml();
    }else if(tab==='messages'){
      panel.innerHTML=await messagesHtml();const body=$('ecoChatBody');if(body)body.scrollTop=body.scrollHeight;
    }else if(tab==='services'){
      await loadProfiles();panel.innerHTML=await servicesHtml();
    }else if(tab==='agreements'){
      panel.innerHTML=await agreementsHtml();
    }
  }

  function marketHtml(){
    const places=[...new Set(products.map(p=>{const s=Array.isArray(p.supplier)?p.supplier[0]:p.supplier;return [s?.governorate,s?.city,s?.area,s?.market_name].filter(Boolean).join(' – ')}).filter(Boolean))];
    const projectOpts=['<option value="">طلب غير مرتبط بمشروع</option>',...projects.map(p=>`<option value="${esc(p.id)}">${esc(p.title)}</option>`)].join('');
    return `<div class="eco-note">الأسعار والكميات يضيفها الموردون بأنفسهم. راجع وقت تحديث السعر وحالة التوفر قبل إرسال الطلب.</div>
      <div class="eco-form" style="margin-bottom:15px">
        <div><label for="ecoSearch">ابحث عن منتج</label><input id="ecoSearch" placeholder="أسمنت، حديد، سيراميك..."></div>
        <div><label for="ecoAreaFilter">المنطقة أو السوق</label><select id="ecoAreaFilter"><option value="">كل المناطق</option>${places.map(x=>`<option>${esc(x)}</option>`).join('')}</select></div>
        <div class="wide"><label for="ecoProjectSelect">ربط الطلب بمشروع</label><select id="ecoProjectSelect">${projectOpts}</select></div>
      </div><div id="ecoProductGrid" class="eco-grid">${productCards(products)}</div>`;
  }

  function productCards(rows){
    if(!rows.length)return '<div class="eco-empty">لا توجد منتجات منشورة حالياً. يمكن للموردين إنشاء حساب وإضافة منتجاتهم.</div>';
    return rows.map(p=>{
      const s=Array.isArray(p.supplier)?p.supplier[0]:p.supplier;
      const loc=[s?.governorate,s?.city,s?.area,s?.market_name].filter(Boolean).join(' – ');
      const own=s?.owner_id===user.id;
      const imageUrl=p.image_path?db.storage.from('ammar-market-files').getPublicUrl(p.image_path).data.publicUrl:null;
      return `<article class="eco-card">${imageUrl?`<img src="${esc(imageUrl)}" alt="${esc(p.title)}" loading="lazy" style="width:100%;max-height:170px;object-fit:cover;border-radius:10px;margin-bottom:9px">`:''}<h3>${esc(p.title)}</h3>
        <div class="eco-meta"><span class="eco-pill">${esc(p.category)}</span><span class="eco-pill">${esc(p.availability==='limited'?'كمية محدودة':'متوفر')}</span>${s?.is_verified?'<span class="eco-pill">AMMAR Verified</span>':''}</div>
        <p>${esc(p.description||p.brand||'')}</p><div class="eco-price">${money(p.price,p.currency)} / ${esc(p.unit)}</div>
        <p><strong>${esc(s?.business_name||'مورد')}</strong></p><p>${esc(loc||'الموقع غير محدد')}</p>
        <p class="muted">آخر تحديث للسعر: ${esc(p.price_updated_at?new Date(p.price_updated_at).toLocaleString('ar'):'غير متاح')}</p>
        <div class="eco-actions">${own?'<span class="eco-pill">منتجك</span>':`<input class="eco-inline-input" style="width:92px" type="number" min="0.001" step="0.001" value="1" aria-label="الكمية" id="ecoQty-${esc(p.id)}">
          <button class="btn primary" type="button" data-eco-buy="${esc(p.id)}">طلب شراء</button>
          <button class="btn light" type="button" data-eco-contact="${esc(p.id)}" data-owner="${esc(s?.owner_id)}">مراسلة المورد</button>`}</div>
      </article>`;
    }).join('');
  }

  function bindMarketFilters(){
    const search=$('ecoSearch'),area=$('ecoAreaFilter');
    const apply=()=>{
      const q=(search?.value||'').trim().toLowerCase(),a=area?.value||'';
      const found=products.filter(p=>{
        const s=Array.isArray(p.supplier)?p.supplier[0]:p.supplier;
        const hay=[p.title,p.category,p.brand,p.description,s?.business_name].join(' ').toLowerCase();
        const place=[s?.governorate,s?.city,s?.area,s?.market_name].filter(Boolean).join(' – ');
        return (!q||hay.includes(q))&&(!a||place===a);
      });
      const grid=$('ecoProductGrid');if(grid)grid.innerHTML=productCards(found);
    };
    search?.addEventListener('input',apply);area?.addEventListener('change',apply);
  }

  function supplierHtml(){
    const p=supplier;
    const profile=`<section class="eco-card eco-subsection"><h3>${p?'تحديث ملف نشاطك التجاري':'إنشاء حساب مورد'}</h3>
      <form id="ecoSupplierForm" class="eco-form">
        <div><label>اسم المحل أو المؤسسة *</label><input name="business_name" required maxlength="180" value="${esc(p?.business_name)}"></div>
        <div><label>اسم المسؤول</label><input name="contact_name" value="${esc(p?.contact_name)}"></div>
        <div><label>رقم الهاتف</label><input name="contact_phone" value="${esc(p?.contact_phone)}"></div>
        <div><label>واتساب</label><input name="whatsapp_phone" value="${esc(p?.whatsapp_phone)}"></div>
        <div><label>الولاية</label><input name="governorate" value="${esc(p?.governorate)}"></div>
        <div><label>المدينة</label><input name="city" value="${esc(p?.city)}"></div>
        <div><label>المنطقة</label><input name="area" value="${esc(p?.area)}"></div>
        <div><label>السوق</label><input name="market_name" value="${esc(p?.market_name)}" placeholder="مثلاً: السجانة"></div>
        <div class="wide"><label>العنوان</label><input name="address" value="${esc(p?.address)}"></div>
        <div class="wide"><label>نبذة عن النشاط</label><textarea name="description">${esc(p?.description)}</textarea></div>
        <div class="wide"><button class="btn primary" type="submit">${p?'حفظ بيانات المورد':'إنشاء حساب المورد'}</button></div>
      </form>${p?`<div class="eco-meta"><span class="eco-pill">حالة الحساب: ${esc(p.status)}</span><span class="eco-pill">${p.is_verified?'تم التحقق':'لم يتم التحقق بعد'}</span></div>`:''}
    </section>`;
    if(!p)return profile+'<div class="eco-note">بعد إنشاء الحساب يمكنك إضافة منتجاتك وإدارة طلبات الشراء. شارة التحقق تمنحها إدارة عَمِّر فقط.</div>';
    const add=`<section class="eco-card eco-subsection"><h3>إضافة منتج جديد</h3>
      <form id="ecoProductForm" class="eco-form">
        <div><label>اسم المنتج *</label><input name="title" required maxlength="180"></div>
        <div><label>التصنيف *</label><input name="category" required placeholder="أسمنت / حديد / دهانات"></div>
        <div><label>الماركة</label><input name="brand"></div>
        <div><label>وحدة البيع *</label><input name="unit" required placeholder="جوال، طن، متر، قطعة"></div>
        <div><label>السعر *</label><input name="price" type="number" min="0" step="0.01" required></div>
        <div><label>العملة</label><select name="currency"><option value="SDG">جنيه سوداني SDG</option><option value="USD">دولار USD</option><option value="EGP">جنيه مصري EGP</option></select></div>
        <div><label>الكمية المتاحة</label><input name="quantity_available" type="number" min="0" step="0.001"></div>
        <div><label>حالة التوفر</label><select name="availability"><option value="available">متوفر</option><option value="limited">كمية محدودة</option><option value="unavailable">غير متوفر</option></select></div>
        <div class="wide"><label>صورة المنتج (JPG أو PNG أو WebP، حد 5 ميجابايت)</label><input name="image" type="file" accept="image/jpeg,image/png,image/webp"></div>
        <div class="wide"><label>وصف ومواصفات</label><textarea name="description"></textarea></div>
        <div class="wide"><button class="btn primary" type="submit">نشر المنتج في السوق</button></div>
      </form></section>`;
    const own=myProducts.length?myProducts.map(x=>`<div class="eco-row"><div><strong>${esc(x.title)}</strong><div class="muted">${money(x.price,x.currency)} / ${esc(x.unit)} · ${esc(x.availability)}</div></div><button class="btn ${x.is_active?'quiet':'light'}" type="button" data-eco-toggle-product="${esc(x.id)}" data-active="${x.is_active?'true':'false'}">${x.is_active?'إيقاف العرض':'إعادة النشر'}</button></div>`).join(''):'<div class="eco-empty">لم تضف منتجات بعد.</div>';
    return profile+add+`<section class="eco-card"><h3>منتجاتي</h3>${own}</section>`;
  }

  async function ordersHtml(){
    const b=await db.from('ammar_market_requests').select('*').eq('buyer_id',user.id).order('created_at',{ascending:false}).limit(100);
    if(b.error)throw b.error;
    let s={data:[]};
    if(supplier){s=await db.from('ammar_market_requests').select('*').eq('supplier_id',supplier.id).order('created_at',{ascending:false}).limit(100);if(s.error)throw s.error;}
    const map=new Map();[...(b.data||[]),...(s.data||[])].forEach(x=>map.set(x.id,x));
    const rows=[...map.values()].sort((x,y)=>new Date(y.created_at)-new Date(x.created_at));
    if(!rows.length)return '<div class="eco-empty">لا توجد طلبات شراء حتى الآن.</div>';
    const ids=rows.map(x=>x.id),supplierIds=[...new Set(rows.map(x=>x.supplier_id))];
    const [ir,qr,sr,rv]=await Promise.all([
      db.from('ammar_market_request_items').select('*').in('request_id',ids),
      db.from('ammar_market_quotes').select('*').in('request_id',ids),
      db.from('ammar_market_suppliers').select('id,business_name,owner_id').in('id',supplierIds),
      db.from('ammar_reviews').select('request_id').eq('reviewer_id',user.id).in('request_id',ids)
    ]);
    if(ir.error)throw ir.error;if(qr.error)throw qr.error;if(sr.error)throw sr.error;if(rv.error)throw rv.error;
    const reviewed=new Set((rv.data||[]).map(x=>x.request_id));
    const sm=new Map((sr.data||[]).map(x=>[x.id,x])),im=new Map(),qm=new Map();
    (ir.data||[]).forEach(x=>{if(!im.has(x.request_id))im.set(x.request_id,[]);im.get(x.request_id).push(x);});
    (qr.data||[]).forEach(x=>{if(!qm.has(x.request_id))qm.set(x.request_id,[]);qm.get(x.request_id).push(x);});
    return `<div class="eco-grid">${rows.map(r=>{
      const buyer=r.buyer_id===user.id,sp=sm.get(r.supplier_id);
      const items=(im.get(r.id)||[]).map(x=>`<p>${esc(x.product_title)} — ${esc(x.quantity)} ${esc(x.unit)}</p>`).join('');
      const quotes=(qm.get(r.id)||[]).map(q=>`<div class="eco-row"><div><strong>${money(q.total_amount,q.currency)}</strong><div class="muted">${esc(q.delivery_days==null?'المدة غير محددة':q.delivery_days+' يوم')} · ${esc(statusText[q.status]||q.status)}</div></div>${buyer&&q.status==='proposed'?`<button class="btn primary" type="button" data-eco-accept-quote="${esc(q.id)}">قبول العرض</button>`:''}</div>`).join('');
      let acts='';
      if(!buyer&&r.status==='submitted')acts+=`<div class="eco-form"><div><label>قيمة العرض</label><input id="ecoQuoteAmount-${esc(r.id)}" type="number" min="0" step="0.01"></div><div><label>مدة التوريد بالأيام</label><input id="ecoQuoteDays-${esc(r.id)}" type="number" min="0" step="1"></div><div class="wide"><label>ملاحظات</label><input id="ecoQuoteNote-${esc(r.id)}"></div><div class="wide"><button class="btn primary" type="button" data-eco-submit-quote="${esc(r.id)}">إرسال عرض السعر</button></div></div>`;
      if(!buyer&&r.status==='accepted')acts+='<button class="btn primary" type="button" data-eco-advance="'+esc(r.id)+'" data-next="fulfilling">بدء التوريد</button>';
      if(!buyer&&r.status==='fulfilling')acts+='<button class="btn primary" type="button" data-eco-advance="'+esc(r.id)+'" data-next="delivered">تأكيد التسليم</button>';
      if(buyer&&r.status==='delivered')acts+='<button class="btn primary" type="button" data-eco-advance="'+esc(r.id)+'" data-next="completed">تأكيد الاستلام وإكمال الطلب</button>';
      if(!['completed','cancelled','disputed'].includes(r.status))acts+='<button class="btn quiet" type="button" data-eco-advance="'+esc(r.id)+'" data-next="cancelled">إلغاء الطلب</button><button class="btn light" type="button" data-eco-advance="'+esc(r.id)+'" data-next="disputed">فتح نزاع</button>';
      acts+='<button class="btn light" type="button" data-eco-order-chat="'+esc(r.id)+'" data-other="'+esc(buyer?sp?.owner_id:r.buyer_id)+'">مراسلة الطرف الآخر</button>';
      if(r.status==='accepted')acts+='<button class="btn light" type="button" data-eco-create-agreement="'+esc(r.id)+'">إنشاء اتفاق موثق</button>';
      if(r.status==='completed'&&!reviewed.has(r.id)){
        const target=buyer?sp?.owner_id:r.buyer_id;
        acts+=`<div class="eco-form"><div><label>تقييم التعامل</label><select id="ecoReviewRating-${esc(r.id)}"><option value="5">5 - ممتاز</option><option value="4">4 - جيد جداً</option><option value="3">3 - جيد</option><option value="2">2 - ضعيف</option><option value="1">1 - سيئ</option></select></div><div class="wide"><label>ملاحظاتك</label><input id="ecoReviewText-${esc(r.id)}" maxlength="2000"></div><div class="wide"><button class="btn light" type="button" data-eco-submit-review="${esc(r.id)}" data-reviewed-user="${esc(target)}">إرسال التقييم</button></div></div>`;
      }
      return `<article class="eco-card"><h3>طلب #${short(r.id)}</h3><div class="eco-meta"><span class="eco-pill">${esc(statusText[r.status]||r.status)}</span><span class="eco-pill">${buyer?'طلب أرسلته':'طلب وارد'}</span></div><p>المورد: ${esc(sp?.business_name||'مورد')}</p>${items}<p>القيمة المتفق عليها: ${r.agreed_total==null?'لم تحدد':money(r.agreed_total,r.currency)}</p><div class="eco-subsection"><strong>العروض</strong>${quotes||'<p class="muted">لا توجد عروض بعد.</p>'}</div><div class="eco-actions">${acts}</div></article>`;
    }).join('')}</div>`;
  }

  async function messagesHtml(){
    const mine=await db.from('ammar_conversation_participants').select('conversation_id').eq('user_id',user.id).order('joined_at',{ascending:false}).limit(200);
    if(mine.error)throw mine.error;
    const ids=(mine.data||[]).map(x=>x.conversation_id);
    if(!ids.length)return '<div class="eco-empty">لا توجد محادثات بعد. ابدأ من زر «مراسلة المورد» أو من طلب شراء.</div>';
    const [cr,pr,prefs,unread]=await Promise.all([
      db.from('ammar_conversations').select('*').in('id',ids).order('last_message_at',{ascending:false}),
      db.from('ammar_conversation_participants').select('conversation_id,user_id').in('conversation_id',ids),
      db.from('ammar_conversation_preferences').select('conversation_id,archived_at').eq('user_id',user.id).in('conversation_id',ids),
      db.from('ammar_user_notifications').select('conversation_id').eq('user_id',user.id).is('read_at',null).in('conversation_id',ids)
    ]);
    if(cr.error)throw cr.error;if(pr.error)throw pr.error;if(prefs.error)throw prefs.error;if(unread.error)throw unread.error;
    availableConversations=cr.data||[];
    const other=new Map();(pr.data||[]).forEach(x=>{if(x.user_id!==user.id)other.set(x.conversation_id,x.user_id);});
    const otherIds=[...new Set([...other.values()])];
    let supplierOwners=new Set(),providerOwners=new Set();
    if(otherIds.length){
      const [s,p]=await Promise.all([
        db.from('ammar_market_suppliers').select('owner_id').in('owner_id',otherIds),
        db.from('ammar_service_providers').select('owner_id').in('owner_id',otherIds)
      ]);
      if(!s.error)supplierOwners=new Set((s.data||[]).map(x=>x.owner_id));
      if(!p.error)providerOwners=new Set((p.data||[]).map(x=>x.owner_id));
    }
    const archived=new Set((prefs.data||[]).filter(x=>x.archived_at).map(x=>x.conversation_id));
    const unreadCounts=new Map();(unread.data||[]).forEach(x=>unreadCounts.set(x.conversation_id,(unreadCounts.get(x.conversation_id)||0)+1));
    const list=availableConversations.map(c=>{
      const counterpart=other.get(c.id),isArchived=archived.has(c.id),count=unreadCounts.get(c.id)||0;
      const role=c.context_type==='project'?'project':supplierOwners.has(counterpart)?'supplier':providerOwners.has(counterpart)?'contractor':'customer';
      const label={project:'مشروع',supplier:'مورد',contractor:'مقاول / خدمة',customer:'عميل'}[role];
      const search=[c.subject,c.context_type,label,counterpart].join(' ').toLowerCase();
      return `<button class="eco-chat-item ${activeConversation===c.id?'active':''}" type="button"
        data-eco-open-chat="${esc(c.id)}" data-eco-chat-item
        data-role="${role}" data-unread="${count>0?'true':'false'}" data-archived="${isArchived?'true':'false'}"
        data-search="${esc(search)}">
        <strong>${esc(c.subject||'محادثة عَمِّر')} ${count?`<span class="notification-badge">${count}</span>`:''} ${isArchived?'<span class="eco-pill">مؤرشفة</span>':''}</strong>
        <small>${label} · الطرف الآخر ${short(counterpart)} · ${esc(new Date(c.last_message_at).toLocaleString('ar'))}</small>
      </button>`;
    }).join('');
    const pane=activeConversation?await chatPane(activeConversation):'<div class="eco-empty">اختر محادثة لعرض الرسائل.</div>';
    return `<div class="eco-chat-toolbar">
      <input id="ecoChatSearch" type="search" placeholder="ابحث في المحادثات أو اسم الطرف..." aria-label="بحث المحادثات">
      <select id="ecoChatFilter" aria-label="تصفية المحادثات">
        <option value="all">كل المحادثات</option><option value="unread">غير المقروءة</option>
        <option value="archived">المؤرشفة</option><option value="customer">العملاء</option>
        <option value="supplier">الموردون</option><option value="contractor">المقاولون والخدمات</option>
        <option value="project">محادثات المشاريع</option>
      </select>
    </div>
    <div class="eco-messages"><aside class="eco-chat-list">${list||'<div class="eco-empty">لا توجد محادثات.</div>'}</aside><section class="eco-chat-pane">${pane}</section></div>`;
  }

  function filterChatList(){
    const q=($('ecoChatSearch')?.value||'').trim().toLowerCase();
    const f=$('ecoChatFilter')?.value||'all';
    document.querySelectorAll('[data-eco-chat-item]').forEach(el=>{
      const archived=el.dataset.archived==='true',unread=el.dataset.unread==='true';
      const matchQuery=!q||(el.dataset.search||'').includes(q)||el.textContent.toLowerCase().includes(q);
      let matchFilter=true;
      if(f==='unread')matchFilter=unread&&!archived;
      else if(f==='archived')matchFilter=archived;
      else if(f==='all')matchFilter=!archived;
      else matchFilter=el.dataset.role===f&&!archived;
      el.hidden=!(matchQuery&&matchFilter);
    });
  }

  function filterMessageBubbles(){
    const q=($('ecoMessageSearch')?.value||'').trim().toLowerCase();
    document.querySelectorAll('#ecoChatBody .eco-bubble').forEach(el=>{
      el.hidden=!!q&&!el.textContent.toLowerCase().includes(q);
    });
  }

  async function chatPane(id){
    const c=await db.from('ammar_conversations').select('*').eq('id',id).maybeSingle();
    if(c.error)throw c.error;if(!c.data)return '<div class="eco-empty">المحادثة غير متاحة.</div>';
    const r=await db.from('ammar_messages').select('*').eq('conversation_id',id).order('created_at',{ascending:true}).limit(500);
    if(r.error)throw r.error;
    const members=await db.from('ammar_conversation_participants').select('user_id').eq('conversation_id',id);
    if(members.error)throw members.error;
    const other=(members.data||[]).find(x=>x.user_id!==user.id)?.user_id||null;
    const pref=await db.from('ammar_conversation_preferences').select('archived_at').eq('conversation_id',id).eq('user_id',user.id).maybeSingle();
    if(pref.error)throw pref.error;
    const marked=await db.rpc('ammar_mark_conversation_delivered',{p_conversation_id:id});
    if(marked.error)throw marked.error;
    const read=await db.rpc('ammar_mark_conversation_read',{p_conversation_id:id});
    if(read.error)throw read.error;
    const messageIds=(r.data||[]).map(x=>x.id);
    let receipts=[],pins=[];
    if(messageIds.length){
      const rr=await db.from('ammar_message_receipts').select('message_id,user_id,delivered_at,read_at').in('message_id',messageIds);
      if(rr.error)throw rr.error;receipts=rr.data||[];
    }
    const pr=await db.from('ammar_pinned_messages').select('message_id').eq('conversation_id',id);
    if(pr.error)throw pr.error;pins=(pr.data||[]).map(x=>x.message_id);
    let presenceText='';
    if(other){
      const presence=await db.rpc('ammar_get_conversation_presence',{p_conversation_id:id,p_other_user:other});
      if(!presence.error&&presence.data?.length){
        const last=new Date(presence.data[0].last_seen_at),age=Date.now()-last.getTime();
        presenceText=age<120000?'متصل الآن':'آخر ظهور '+last.toLocaleString('ar');
      }else presenceText='آخر الظهور مخفي';
    }
    await refreshUnreadCount();
    const byId=new Map((r.data||[]).map(x=>[x.id,x]));
    const forwardOptions=availableConversations.filter(x=>x.id!==id).map(x=>`<option value="${esc(x.id)}">${esc(x.subject||'محادثة')} · ${esc(x.context_type)}</option>`).join('');
    const bubbles=await Promise.all((r.data||[]).map(async m=>{
      let body=esc(m.body||'');
      if(m.message_type==='location'&&m.location_lat!=null&&m.location_lng!=null){
        const mapUrl='https://www.google.com/maps?q='+encodeURIComponent(m.location_lat+','+m.location_lng);
        body+=`<div><a href="${esc(mapUrl)}" target="_blank" rel="noopener">📍 ${esc(m.location_label||'موقع مشترك')} (${esc(m.location_lat)}, ${esc(m.location_lng)})</a></div>`;
      }
      if(m.file_path){
        const signed=await db.storage.from('ammar-chat-files').createSignedUrl(m.file_path,3600);
        if(!signed.error&&signed.data?.signedUrl){
          if(m.message_type==='image')body+=`<div><img src="${esc(signed.data.signedUrl)}" alt="${esc(m.file_name||'صورة')}" loading="lazy" style="max-width:220px;border-radius:9px"></div>`;
          else if(m.message_type==='video')body+=`<div><video controls preload="metadata"><source src="${esc(signed.data.signedUrl)}" type="${esc(m.mime_type||'video/mp4')}"></video></div>`;
          else body+=`<div><a href="${esc(signed.data.signedUrl)}" target="_blank" rel="noopener">${esc(m.file_name||'فتح المرفق')}</a></div>`;
        }else body+='<div class="muted">تعذر فتح المرفق.</div>';
      }
      if(m.reply_to_id){
        const parent=byId.get(m.reply_to_id);
        body=`<div class="eco-reply-preview">رد على: ${esc(parent?.body||parent?.file_name||'رسالة سابقة')}</div>`+body;
      }
      const received=receipts.filter(x=>x.message_id===m.id);
      const state=m.sender_id!==user.id?'':received.some(x=>x.read_at)?' · تمت القراءة':received.some(x=>x.delivered_at)?' · تم التسليم':' · أُرسلت';
      const pinned=pins.includes(m.id);
      const actions=`<div class="eco-message-actions">
        <button type="button" data-eco-reply="${esc(m.id)}">رد</button>
        <button type="button" ${pinned?'data-eco-unpin':'data-eco-pin'}="${esc(m.id)}">${pinned?'إزالة التثبيت':'تثبيت'}</button>
        <button type="button" data-eco-report="${esc(m.id)}">إبلاغ</button>
        <button type="button" data-eco-forward="${esc(m.id)}">إعادة توجيه</button>
        ${c.data.context_type==='project'?`<button type="button" data-eco-to-task="${esc(m.id)}">تحويل لمهمة</button><button type="button" data-eco-to-change="${esc(m.id)}">طلب تغيير</button>`:''}
      </div>`;
      return `<div class="eco-bubble ${m.sender_id===user.id?'mine':''}" data-eco-message="${esc(m.id)}">
        ${pinned?'<span class="eco-pill">مثبتة</span>':''}${body}
        <small>${m.sender_id===user.id?'أنت':'الطرف الآخر'} · ${esc(new Date(m.created_at).toLocaleString('ar'))}${state}</small>${actions}
      </div>`;
    }));
    const archived=!!pref.data?.archived_at;
    const replyMessage=replyToMessageId?byId.get(replyToMessageId):null;
    const replyHtml=replyMessage?`<div id="ecoReplyHint" class="eco-reply-preview">الرد على: ${esc(replyMessage.body||replyMessage.file_name||'رسالة')} <button type="button" data-eco-clear-reply>إلغاء</button></div>`:'';
    return `<div class="eco-chat-head">${esc(c.data.subject||'محادثة عَمِّر')} <span class="eco-presence">· ${esc(c.data.context_type)} ${presenceText?'· '+esc(presenceText):''}</span>
      <div class="eco-chat-head-actions">
        <button class="btn quiet" type="button" data-eco-archive="${esc(id)}" data-archived="${archived?'true':'false'}">${archived?'إلغاء الأرشفة':'أرشفة'}</button>
        <button class="btn quiet" type="button" data-eco-block="${esc(other||'')}">حظر الطرف</button>
        <button class="btn quiet" type="button" data-eco-presence-toggle>${showLastSeen?'إخفاء آخر ظهور':'إظهار آخر ظهور'}</button>
      </div></div>
      <div class="eco-chat-toolbar"><input id="ecoMessageSearch" type="search" placeholder="ابحث داخل الرسائل...">
        ${forwardOptions?`<select id="ecoForwardTarget"><option value="">وجهة إعادة التوجيه...</option>${forwardOptions}</select>`:''}
      </div>
      <div id="ecoChatBody" class="eco-chat-body">${bubbles.join('')||'<div class="eco-empty">ابدأ المحادثة برسالة واضحة.</div>'}</div>
      ${replyHtml}
      <form id="ecoSendMessageForm" class="eco-chat-send">
        <input type="hidden" name="reply_to_id" value="${esc(replyToMessageId||'')}">
        <input type="text" name="body" maxlength="5000" placeholder="اكتب رسالتك..." autocomplete="off">
        <input type="file" name="attachment" accept="image/jpeg,image/png,image/webp,application/pdf,.doc,.docx,.xls,.xlsx,video/mp4,video/webm,video/quicktime">
        <button class="btn light" type="button" data-eco-location>مشاركة الموقع</button>
        <button class="btn primary" type="submit">إرسال</button>
      </form>`;
  }

async function servicesHtml(){
    const p=provider;
    const profile=`<section class="eco-card eco-subsection"><h3>${p?'ملف مقدم الخدمة':'إنشاء ملف مقاول أو مقدم خدمة'}</h3>
      <form id="ecoProviderForm" class="eco-form">
        <div><label>اسم النشاط *</label><input name="business_name" required value="${esc(p?.business_name)}"></div>
        <div><label>نوع النشاط *</label><select name="provider_type"><option value="contractor">مقاولات</option><option value="maintenance">صيانة</option><option value="engineering">خدمات هندسية</option><option value="transport">نقل</option><option value="equipment_rental">تأجير معدات</option><option value="other">أخرى</option></select></div>
        <div><label>اسم المسؤول</label><input name="contact_name" value="${esc(p?.contact_name)}"></div><div><label>الهاتف</label><input name="contact_phone" value="${esc(p?.contact_phone)}"></div>
        <div><label>الولاية</label><input name="governorate" value="${esc(p?.governorate)}"></div><div><label>المدينة</label><input name="city" value="${esc(p?.city)}"></div><div><label>المنطقة</label><input name="area" value="${esc(p?.area)}"></div>
        <div class="wide"><label>وصف الخدمات والخبرة</label><textarea name="description">${esc(p?.description)}</textarea></div>
        <div class="wide"><button class="btn primary" type="submit">${p?'تحديث الملف':'إنشاء الملف'}</button></div>
      </form></section>`;
    const req=await db.from('ammar_service_requests').select('*').order('created_at',{ascending:false}).limit(100);
    if(req.error)throw req.error;
    const requestIds=(req.data||[]).map(x=>x.id);
    let offerRows=[];
    if(requestIds.length){
      const offers=await db.from('ammar_service_offers').select('*,provider:ammar_service_providers(owner_id,business_name)').in('request_id',requestIds).order('created_at',{ascending:false});
      if(offers.error)throw offers.error;offerRows=offers.data||[];
    }
    const offersMap=new Map();offerRows.forEach(o=>{if(!offersMap.has(o.request_id))offersMap.set(o.request_id,[]);offersMap.get(o.request_id).push(o);});
    const cards=(req.data||[]).map(r=>{
      const own=r.requester_id===user.id;
      const offersHtml=(offersMap.get(r.id)||[]).map(o=>{
        const sp=Array.isArray(o.provider)?o.provider[0]:o.provider;
        const actions=(own&&o.status==='proposed'?'<button class="btn primary" type="button" data-eco-accept-service="'+esc(o.id)+'">قبول العرض</button>':'')
          +(own?'<button class="btn light" type="button" data-eco-service-chat="'+esc(o.id)+'" data-other="'+esc(sp?.owner_id)+'">مراسلة مقدم الخدمة</button>':'<button class="btn light" type="button" data-eco-service-chat="'+esc(o.id)+'" data-other="'+esc(r.requester_id)+'">مراسلة صاحب الطلب</button>')
          +(o.status==='accepted'?'<button class="btn light" type="button" data-eco-service-agreement="'+esc(o.id)+'">إنشاء اتفاق</button>':'');
        return '<div class="eco-row"><div><strong>'+esc(sp?.business_name||'مقدم خدمة')+'</strong><div class="muted">'+money(o.amount,o.currency)+' · '+esc(o.duration_days==null?'المدة غير محددة':o.duration_days+' يوم')+' · '+esc(statusText[o.status]||o.status)+'</div></div><div class="eco-actions">'+actions+'</div></div>';
      }).join('');
      const offerForm=provider&&!own&&r.status==='open'?'<div class="eco-form"><div><label>عرضك المالي</label><input id="ecoSvcAmount-'+esc(r.id)+'" type="number" min="0" step="0.01"></div><div><label>مدة التنفيذ (يوم)</label><input id="ecoSvcDays-'+esc(r.id)+'" type="number" min="1"></div><div class="wide"><button class="btn primary" type="button" data-eco-service-offer="'+esc(r.id)+'">تقديم عرض</button></div></div>':'';
      const completeAction=own&&r.status==='awarded'?'<button class="btn primary" type="button" data-eco-complete-service="'+esc(r.id)+'">تأكيد اكتمال الخدمة</button>':'';
      return '<article class="eco-card"><h3>'+esc(r.title)+'</h3><div class="eco-meta"><span class="eco-pill">'+esc(r.service_type)+'</span><span class="eco-pill">'+esc(r.city||'الموقع غير محدد')+'</span><span class="eco-pill">'+esc(statusText[r.status]||r.status)+'</span></div><p>'+esc(r.description)+'</p><p>الميزانية القصوى: '+(r.budget_max==null?'غير محددة':money(r.budget_max,r.currency))+'</p>'+offerForm+'<div class="eco-subsection"><strong>العروض المقدمة</strong>'+(offersHtml||'<p class="muted">لا توجد عروض بعد.</p>')+'</div>'+completeAction+'</article>';
    }).join('');
    return `${profile}<section class="eco-card eco-subsection"><h3>نشر طلب خدمة أو مقاول</h3>
      <form id="ecoServiceRequestForm" class="eco-form">
        <div><label>نوع الخدمة *</label><select name="service_type"><option value="contractor">مقاولات</option><option value="renovation">ترميم</option><option value="maintenance">صيانة</option><option value="engineering">هندسة</option><option value="inspection">معاينة</option><option value="transport">نقل</option><option value="equipment_rental">تأجير معدات</option><option value="other">أخرى</option></select></div>
        <div><label>عنوان الطلب *</label><input name="title" required minlength="5" maxlength="180"></div>
        <div><label>الولاية</label><input name="governorate"></div><div><label>المدينة</label><input name="city"></div><div><label>المنطقة</label><input name="area"></div>
        <div><label>ربط بمشروع (اختياري)</label><select name="project_id"><option value="">بدون ربط</option>${projects.map(p=>'<option value="'+esc(p.id)+'">'+esc(p.title)+'</option>').join('')}</select></div>
        <div><label>الميزانية القصوى</label><input name="budget_max" type="number" min="0" step="0.01"></div>
        <div class="wide"><label>التفاصيل المطلوبة *</label><textarea name="description" required minlength="10" maxlength="6000"></textarea></div>
        <div class="wide"><button class="btn primary" type="submit">نشر طلب الخدمة</button></div>
      </form></section><section class="eco-card"><h3>طلبات الخدمات المفتوحة</h3><div class="eco-grid">${cards||'<div class="eco-empty">لا توجد طلبات خدمات مفتوحة.</div>'}</div></section>`;
  }

  async function agreementsHtml(){
    const [a,l]=await Promise.all([
      db.from('ammar_agreements').select('*').order('created_at',{ascending:false}).limit(100),
      db.from('ammar_commission_ledger').select('gross_amount,currency,commission_amount,status,recorded_at').eq('payer_id',user.id).order('recorded_at',{ascending:false}).limit(30)
    ]);
    if(a.error)throw a.error;if(l.error)throw l.error;
    const agreements=(a.data||[]).map(x=>`<article class="eco-card"><h3>${esc(x.title)}</h3><div class="eco-meta"><span class="eco-pill">${esc(statusText[x.status]||x.status)}</span><span class="eco-pill">${x.client_id===user.id?'أنت العميل':'أنت مقدم الخدمة'}</span></div><p>${esc(x.scope)}</p><p>القيمة: ${money(x.amount,x.currency)}</p><p class="muted">تاريخ الإنشاء: ${esc(new Date(x.created_at).toLocaleDateString('ar'))}</p>${x.status!=='accepted'&&!['cancelled','rejected'].includes(x.status)?`<button class="btn primary" type="button" data-eco-accept-agreement="${esc(x.id)}">اعتماد الاتفاق</button>`:''}</article>`).join('');
    const ledger=(l.data||[]).map(x=>`<div class="eco-row"><div>${money(x.gross_amount,x.currency)} · عمولة ${money(x.commission_amount,x.currency)}</div><span class="eco-pill">${esc(x.status)}</span></div>`).join('');
    return `<section class="eco-card eco-subsection"><h3>الاتفاقات</h3><div class="eco-grid">${agreements||'<div class="eco-empty">لا توجد اتفاقات موثقة.</div>'}</div></section><section class="eco-card"><h3>سجل العمولات المستحقة</h3>${ledger||'<p class="muted">لا توجد عمولات مسجلة لهذا الحساب.</p>'}</section><div class="eco-note">العمولات هنا سجلات محاسبية فقط؛ لا ينفذ عَمِّر تحصيلاً أو حيازة أموال أو تحويلات بنكية.</div>`;
  }

  async function startConversation(other,context,contextId,subject){
    if(!other||other===user.id)throw new Error('بيانات الطرف الآخر غير صالحة.');
    const r=await db.rpc('ammar_start_conversation',{p_other_user:other,p_context_type:context,p_context_id:String(contextId),p_subject:subject||null});
    if(r.error)throw r.error;
    activeConversation=r.data;await chooseTabAsync('messages');switchRealtime(activeConversation);
  }

  async function chooseTabAsync(next){
    tab=next;document.querySelectorAll('[data-eco-tab]').forEach(b=>b.classList.toggle('active',b.dataset.ecoTab===next));
    await render();
  }

  function switchRealtime(id){
    if(messageChannel)db.removeChannel(messageChannel).catch(()=>{});
    messageChannel=db.channel('ammar-chat-'+id)
      .on('postgres_changes',{event:'INSERT',schema:'public',table:'ammar_messages',filter:'conversation_id=eq.'+id},()=>{
        if(tab==='messages'&&activeConversation===id)render().catch(e=>tell(e.message,'error'));
      }).subscribe();
  }

  async function click(e){
    const t=e.target.closest('[data-eco-tab]');if(t){chooseTab(t.dataset.ecoTab);return;}
    const b=e.target.closest('[data-eco-action],[data-eco-buy],[data-eco-contact],[data-eco-toggle-product],[data-eco-open-chat],[data-eco-accept-quote],[data-eco-submit-quote],[data-eco-advance],[data-eco-order-chat],[data-eco-create-agreement],[data-eco-service-offer],[data-eco-accept-service],[data-eco-service-chat],[data-eco-service-agreement],[data-eco-complete-service],[data-eco-accept-agreement],[data-eco-submit-review],[data-eco-reply],[data-eco-clear-reply],[data-eco-pin],[data-eco-unpin],[data-eco-report],[data-eco-forward],[data-eco-archive],[data-eco-block],[data-eco-presence-toggle],[data-eco-location],[data-eco-to-task],[data-eco-to-change]');
    if(!b)return;
    try{
      if(b.dataset.ecoReply){replyToMessageId=b.dataset.ecoReply;await render();return;}
      if(b.hasAttribute('data-eco-clear-reply')){replyToMessageId=null;await render();return;}
      if(b.dataset.ecoPin){
        const r=await db.from('ammar_pinned_messages').insert({conversation_id:activeConversation,message_id:b.dataset.ecoPin,pinned_by:user.id});
        if(r.error)throw r.error;await render();tell('تم تثبيت الرسالة.','success');return;
      }
      if(b.dataset.ecoUnpin){
        const r=await db.from('ammar_pinned_messages').delete().eq('conversation_id',activeConversation).eq('message_id',b.dataset.ecoUnpin).eq('pinned_by',user.id);
        if(r.error)throw r.error;await render();tell('تم إلغاء تثبيت الرسالة.','success');return;
      }
      if(b.dataset.ecoReport){
        const reason=window.prompt('ما سبب الإبلاغ عن هذه الرسالة؟');
        if(!reason||reason.trim().length<5)return;
        const r=await db.from('ammar_message_reports').insert({conversation_id:activeConversation,message_id:b.dataset.ecoReport,reporter_id:user.id,reason:reason.trim()});
        if(r.error)throw r.error;tell('تم تسجيل البلاغ للمراجعة.','success');return;
      }
      if(b.dataset.ecoForward){
        const target=$('ecoForwardTarget')?.value;
        if(!target)throw new Error('اختر محادثة مستهدفة أولاً.');
        const r=await db.rpc('ammar_forward_message',{p_message_id:b.dataset.ecoForward,p_target_conversation_id:target});
        if(r.error)throw r.error;tell('تمت إعادة توجيه الرسالة.','success');return;
      }
      if(b.dataset.ecoArchive){
        const archived=b.dataset.archived==='true';
        const r=await db.from('ammar_conversation_preferences').upsert({
          conversation_id:b.dataset.ecoArchive,user_id:user.id,archived_at:archived?null:new Date().toISOString(),updated_at:new Date().toISOString()
        },{onConflict:'conversation_id,user_id'});
        if(r.error)throw r.error;await render();tell(archived?'تمت إعادة المحادثة إلى القائمة.':'تمت أرشفة المحادثة.','success');return;
      }
      if(b.dataset.ecoBlock){
        if(!b.dataset.ecoBlock)throw new Error('لم يتم تحديد الطرف الآخر.');
        if(!window.confirm('حظر هذا الحساب؟ لن يتمكن الطرفان من إرسال رسائل جديدة لبعضهما.'))return;
        const r=await db.from('ammar_user_blocks').upsert({blocker_id:user.id,blocked_id:b.dataset.ecoBlock},{onConflict:'blocker_id,blocked_id'});
        if(r.error)throw r.error;tell('تم حظر الحساب.','success');await render();return;
      }
      if(b.hasAttribute('data-eco-presence-toggle')){
        showLastSeen=!showLastSeen;
        const r=await db.rpc('ammar_set_presence',{p_show_last_seen:showLastSeen});
        if(r.error)throw r.error;await render();tell(showLastSeen?'أصبح آخر ظهور مرئياً.':'تم إخفاء آخر ظهور.','success');return;
      }
      if(b.hasAttribute('data-eco-location')){
        if(!navigator.geolocation)throw new Error('المتصفح لا يدعم مشاركة الموقع.');
        navigator.geolocation.getCurrentPosition(async pos=>{
          try{
            const loc={conversation_id:activeConversation,sender_id:user.id,message_type:'location',body:'موقع مشترك',location_lat:pos.coords.latitude,location_lng:pos.coords.longitude,location_label:'الموقع الحالي'};
            const r=await db.from('ammar_messages').insert(loc);if(r.error)throw r.error;
            await render();switchRealtime(activeConversation);
          }catch(err){tell('تعذر مشاركة الموقع: '+(err.message||'خطأ'),'error');}
        },err=>tell('تعذر الحصول على الموقع: '+err.message,'error'),{enableHighAccuracy:false,timeout:10000,maximumAge:60000});
        return;
      }
      if(b.dataset.ecoToTask){
        const r=await db.rpc('ammar_message_to_project_task',{p_message_id:b.dataset.ecoToTask});
        if(r.error)throw r.error;tell('تم تحويل الرسالة إلى مهمة داخل المشروع.','success');return;
      }
      if(b.dataset.ecoToChange){
        const title=window.prompt('عنوان طلب التغيير:','طلب تغيير من المحادثة');
        if(!title)return;
        const reason=window.prompt('اشرح التغيير المطلوب:', 'تم تحويل رسالة المشروع إلى طلب تغيير لمراجعته.');
        if(!reason)return;
        const r=await db.rpc('ammar_message_to_change_order',{p_message_id:b.dataset.ecoToChange,p_title:title,p_reason:reason,p_cost_impact:0,p_currency:'SDG',p_days_impact:0});
        if(r.error)throw r.error;tell('تم إنشاء طلب تغيير للمراجعة.','success');return;
      }
      if(b.dataset.ecoAction==='refresh'){await render();tell('تم تحديث البيانات.','success');return;}
      if(b.dataset.ecoBuy){
        const p=products.find(x=>x.id===b.dataset.ecoBuy),qty=Number($('ecoQty-'+b.dataset.ecoBuy)?.value||0);
        if(!p||qty<=0)throw new Error('حدد كمية صحيحة.');
        const projectId=$('ecoProjectSelect')?.value||null;
        const r=await db.rpc('ammar_create_market_request',{p_supplier_id:p.supplier_id,p_product_id:p.id,p_quantity:qty,p_project_id:projectId,p_buyer_note:null});
        if(r.error)throw r.error;chooseTab('orders');tell('تم إنشاء طلب الشراء.','success');return;
      }
      if(b.dataset.ecoContact){
        const p=products.find(x=>x.id===b.dataset.ecoContact);
        await startConversation(b.dataset.owner,'market_product',b.dataset.ecoContact,'استفسار عن: '+(p?.title||'منتج'));return;
      }
      if(b.dataset.ecoOpenChat){
        activeConversation=b.dataset.ecoOpenChat;await render();switchRealtime(activeConversation);return;
      }
      if(b.dataset.ecoToggleProduct){
        const res=await db.from('ammar_market_products').update({is_active:b.dataset.active!=='true'}).eq('id',b.dataset.ecoToggleProduct);
        if(res.error)throw res.error;await render();tell('تم تحديث حالة المنتج.','success');return;
      }
      if(b.dataset.ecoOpenChat){activeConversation=b.dataset.ecoOpenChat;await render();switchRealtime(activeConversation);return;}
      if(b.dataset.ecoAcceptQuote){
        const r=await db.rpc('ammar_accept_market_quote',{p_quote_id:b.dataset.ecoAcceptQuote});
        if(r.error)throw r.error;await render();tell('تم قبول العرض وتسجيل القيمة المتفق عليها.','success');return;
      }
      if(b.dataset.ecoSubmitQuote){
        if(!supplier)throw new Error('أنشئ حساب المورد أولاً.');
        const id=b.dataset.ecoSubmitQuote,amount=Number($('ecoQuoteAmount-'+id)?.value),days=$('ecoQuoteDays-'+id)?.value,notes=$('ecoQuoteNote-'+id)?.value||null;
        if(!Number.isFinite(amount)||amount<0)throw new Error('أدخل قيمة عرض صحيحة.');
        const req=await db.from('ammar_market_requests').select('currency').eq('id',id).single();if(req.error)throw req.error;
        const r=await db.from('ammar_market_quotes').insert({request_id:id,supplier_id:supplier.id,created_by:user.id,total_amount:amount,currency:req.data.currency||'SDG',delivery_days:days?Number(days):null,notes});
        if(r.error)throw r.error;await render();tell('تم إرسال عرض السعر.','success');return;
      }
      if(b.dataset.ecoAdvance){
        const next=b.dataset.next;let note=null;
        if(next==='disputed'){note=window.prompt('اكتب سبب النزاع بالتفصيل (10 أحرف على الأقل):');if(!note||note.trim().length<10)return;}
        if(next==='cancelled'&&!window.confirm('هل تريد إلغاء الطلب؟'))return;
        const r=await db.rpc('ammar_advance_market_request',{p_request_id:b.dataset.ecoAdvance,p_next_status:next,p_note:note});
        if(r.error)throw r.error;await render();tell('تم تحديث حالة المعاملة.','success');return;
      }
      if(b.dataset.ecoOrderChat){
        await startConversation(b.dataset.other,'market_request',b.dataset.ecoOrderChat,'طلب شراء #'+short(b.dataset.ecoOrderChat));return;
      }
      if(b.dataset.ecoCreateAgreement){
        const id=b.dataset.ecoCreateAgreement;
        const r=await db.from('ammar_market_requests').select('*,supplier:ammar_market_suppliers(owner_id,business_name)').eq('id',id).single();
        if(r.error)throw r.error;const s=Array.isArray(r.data.supplier)?r.data.supplier[0]:r.data.supplier;
        const title=window.prompt('عنوان الاتفاق:','اتفاق توريد مواد بناء');if(!title)return;
        const scope=window.prompt('نطاق التوريد والتفاصيل:','توريد المواد الموضحة في طلب الشراء وفق الكميات والمواصفات المعتمدة.');if(!scope)return;
        const agreement=await db.from('ammar_agreements').insert({source_type:'market_request',source_id:id,project_id:r.data.project_id,client_id:r.data.buyer_id,provider_id:s.owner_id,title,scope,amount:r.data.agreed_total,currency:r.data.currency,created_by:user.id});
        if(agreement.error)throw agreement.error;chooseTab('agreements');tell('تم إنشاء الاتفاق وإرساله للطرف الآخر.','success');return;
      }
      if(b.dataset.ecoServiceOffer){
        if(!provider)throw new Error('أنشئ ملف مقدم الخدمة أولاً.');
        const id=b.dataset.ecoServiceOffer,amount=Number($('ecoSvcAmount-'+id)?.value),days=$('ecoSvcDays-'+id)?.value;
        if(!Number.isFinite(amount)||amount<0)throw new Error('أدخل قيمة صحيحة.');
        const r=await db.from('ammar_service_offers').insert({request_id:id,provider_id:provider.id,created_by:user.id,amount,duration_days:days?Number(days):null,currency:'SDG'});
        if(r.error)throw r.error;await render();tell('تم تقديم عرض الخدمة.','success');return;
      }
      if(b.dataset.ecoAcceptService){
        const r=await db.rpc('ammar_accept_service_offer',{p_offer_id:b.dataset.ecoAcceptService});
        if(r.error)throw r.error;await render();tell('تم قبول عرض مقدم الخدمة.','success');return;
      }
      if(b.dataset.ecoServiceChat){
        await startConversation(b.dataset.other,'service_offer',b.dataset.ecoServiceChat,'محادثة عرض خدمة');return;
      }
      if(b.dataset.ecoCompleteService){
        if(!window.confirm('هل تؤكد اكتمال الخدمة واستلامها؟ سيُسجل المبلغ ضمن مصروفات المشروع وتُسجل عمولة عَمِّر المستحقة حسب إعدادات النشاط.'))return;
        const r=await db.rpc('ammar_complete_service_request',{p_request_id:b.dataset.ecoCompleteService});
        if(r.error)throw r.error;await render();tell('تم تأكيد اكتمال الخدمة وتسجيل مصروف المشروع والعمولة المستحقة.','success');return;
      }
      if(b.dataset.ecoServiceAgreement){
        const id=b.dataset.ecoServiceAgreement;
        const r=await db.from('ammar_service_offers').select('*,request:ammar_service_requests(*),provider:ammar_service_providers(owner_id,business_name)').eq('id',id).single();
        if(r.error)throw r.error;
        const req=Array.isArray(r.data.request)?r.data.request[0]:r.data.request;
        const sp=Array.isArray(r.data.provider)?r.data.provider[0]:r.data.provider;
        const title=window.prompt('عنوان الاتفاق:','اتفاق تنفيذ خدمات');if(!title)return;
        const scope=window.prompt('نطاق العمل والتفاصيل:',req?.description||'الخدمات الموضحة في طلب الخدمة والعرض المقبول.');if(!scope)return;
        const a=await db.from('ammar_agreements').insert({source_type:'service_offer',source_id:id,project_id:req?.project_id||null,client_id:req.requester_id,provider_id:sp.owner_id,title,scope,amount:r.data.amount,currency:r.data.currency,created_by:user.id});
        if(a.error)throw a.error;chooseTab('agreements');tell('تم إنشاء الاتفاق وإرساله للطرف الآخر.','success');return;
      }
      if(b.dataset.ecoAcceptAgreement){
        const r=await db.rpc('ammar_accept_agreement',{p_agreement_id:b.dataset.ecoAcceptAgreement});
        if(r.error)throw r.error;await render();tell('تم تسجيل موافقتك؛ يكتمل الاتفاق بعد موافقة الطرفين.','success');return;
      }
      if(b.dataset.ecoSubmitReview){
        const rating=Number($('ecoReviewRating-'+b.dataset.ecoSubmitReview)?.value||0);
        const review_text=$('ecoReviewText-'+b.dataset.ecoSubmitReview)?.value||null;
        const r=await db.from('ammar_reviews').insert({request_id:b.dataset.ecoSubmitReview,reviewer_id:user.id,reviewed_user_id:b.dataset.reviewedUser,rating,review_text});
        if(r.error)throw r.error;await render();tell('تم إرسال التقييم.','success');return;
      }
    }catch(err){tell('تعذر تنفيذ العملية: '+(err.message||'خطأ غير معروف'),'error');}
  }

  async function submit(e){
    const form=e.target;
    if(!form.matches('#ecoSupplierForm,#ecoProductForm,#ecoProviderForm,#ecoServiceRequestForm,#ecoSendMessageForm'))return;
    e.preventDefault();const btn=form.querySelector('button[type=submit]');
    if(btn){btn.disabled=true;btn.dataset.oldText=btn.textContent;btn.textContent='جارٍ الحفظ...';}
    try{
      const d=Object.fromEntries(new FormData(form).entries());
      if(form.id==='ecoSupplierForm'){
        const payload={business_name:d.business_name.trim(),contact_name:d.contact_name||null,contact_phone:d.contact_phone||null,whatsapp_phone:d.whatsapp_phone||null,governorate:d.governorate||null,city:d.city||null,area:d.area||null,market_name:d.market_name||null,address:d.address||null,description:d.description||null};
        const r=supplier?await db.from('ammar_market_suppliers').update(payload).eq('owner_id',user.id):await db.from('ammar_market_suppliers').insert({...payload,owner_id:user.id});
        if(r.error)throw r.error;await loadProfiles();await loadMyProducts();await render();tell('تم حفظ ملف المورد.','success');
      }else if(form.id==='ecoProductForm'){
        if(!supplier)throw new Error('أنشئ حساب المورد أولاً.');
        let imagePath=null;
        const image=form.querySelector('input[name="image"]')?.files?.[0]||null;
        if(image){
          if(image.size>5*1024*1024)throw new Error('حجم صورة المنتج يجب ألا يتجاوز 5 ميجابايت.');
          if(!/^image\/(jpeg|png|webp)$/.test(image.type))throw new Error('صيغة صورة المنتج غير مدعومة.');
          const safe=image.name.replace(/[^a-zA-Z0-9._-]/g,'_');
          imagePath=`${supplier.id}/${user.id}/${Date.now()}-${safe}`;
          const upload=await db.storage.from('ammar-market-files').upload(imagePath,image,{upsert:false,contentType:image.type});
          if(upload.error)throw upload.error;
        }
        const r=await db.from('ammar_market_products').insert({supplier_id:supplier.id,title:d.title.trim(),category:d.category.trim(),brand:d.brand||null,unit:d.unit.trim(),price:Number(d.price),currency:d.currency||'SDG',quantity_available:d.quantity_available?Number(d.quantity_available):null,availability:d.availability||'available',description:d.description||null,image_path:imagePath});
        if(r.error)throw r.error;await loadMyProducts();await render();tell('تم نشر المنتج في السوق.','success');
      }else if(form.id==='ecoProviderForm'){
        const payload={business_name:d.business_name.trim(),provider_type:d.provider_type,contact_name:d.contact_name||null,contact_phone:d.contact_phone||null,governorate:d.governorate||null,city:d.city||null,area:d.area||null,description:d.description||null};
        const r=provider?await db.from('ammar_service_providers').update(payload).eq('owner_id',user.id):await db.from('ammar_service_providers').insert({...payload,owner_id:user.id});
        if(r.error)throw r.error;await loadProfiles();await render();tell('تم حفظ ملف مقدم الخدمة.','success');
      }else if(form.id==='ecoServiceRequestForm'){
        const r=await db.from('ammar_service_requests').insert({requester_id:user.id,project_id:d.project_id||null,service_type:d.service_type,title:d.title.trim(),description:d.description.trim(),governorate:d.governorate||null,city:d.city||null,area:d.area||null,budget_max:d.budget_max?Number(d.budget_max):null,currency:'SDG'});
        if(r.error)throw r.error;await render();tell('تم نشر طلب الخدمة.','success');
      }else if(form.id==='ecoSendMessageForm'){
        if(!activeConversation)throw new Error('اختر محادثة أولاً.');
        const body=(d.body||'').trim(),file=form.querySelector('input[name=attachment]')?.files?.[0]||null;
        const replyTo=d.reply_to_id||null;
        if(!body&&!file)throw new Error('اكتب رسالة أو اختر مرفقاً.');
        if(body){
          const m=await db.from('ammar_messages').insert({conversation_id:activeConversation,sender_id:user.id,message_type:'text',body,reply_to_id:replyTo});
          if(m.error)throw m.error;
        }
        if(file){
          if(file.size>50*1024*1024)throw new Error('الحد الأقصى للمرفق 50 ميجابايت.');
          const safe=file.name.replace(/[^a-zA-Z0-9._-]/g,'_'),path=`${activeConversation}/${user.id}/${Date.now()}-${safe}`;
          const up=await db.storage.from('ammar-chat-files').upload(path,file,{upsert:false,contentType:file.type||'application/octet-stream'});if(up.error)throw up.error;
          const image=/^image\/(jpeg|png|webp)$/.test(file.type);
          const video=/^video\/(mp4|webm|quicktime)$/.test(file.type);
          const messageType=image?'image':video?'video':'file';
          const m=await db.from('ammar_messages').insert({conversation_id:activeConversation,sender_id:user.id,message_type:messageType,file_path:path,file_name:file.name,mime_type:file.type||null,reply_to_id:replyTo});
          if(m.error)throw m.error;
        }
        replyToMessageId=null;
        await render();switchRealtime(activeConversation);
      }
    }catch(err){tell('تعذر الحفظ: '+(err.message||'خطأ غير معروف'),'error');}
    finally{if(btn){btn.disabled=false;btn.textContent=btn.dataset.oldText||'حفظ';}}
  }

  function bind(){
    document.addEventListener('click',e=>{
      const b=e.target.closest('[data-ammar-open]');if(b){e.preventDefault();open('market');}
    });
    window.openAmmarEcosystem=open;
  }

  function start(sessionUser){
    user=sessionUser;if(!user)return;mount();if(!mounted)return;
    db.from('ammar_user_presence').select('show_last_seen').eq('user_id',user.id).maybeSingle()
      .then(r=>{if(!r.error&&r.data)showLastSeen=r.data.show_last_seen!==false;})
      .finally(()=>db.rpc('ammar_set_presence',{p_show_last_seen:showLastSeen}).then(()=>{}).catch(()=>{}));
    Promise.all([loadProfiles(),loadProjects()]).then(()=>render()).catch(err=>{
      const p=$('ecoPanel');
      if(p)p.innerHTML=`<div class="eco-empty">لم يتم تهيئة السوق بعد. طبّق ترحيل <strong>202611120006_ammar_marketplace_messaging.sql</strong> في Supabase ثم أعد تحميل التطبيق.<br><small>${esc(err.message||'')}</small></div>`;
    });
    if(refreshTimer)clearInterval(refreshTimer);
    if(presenceTimer)clearInterval(presenceTimer);
    refreshTimer=setInterval(()=>{if(user&&!document.hidden){refreshUnreadCount();if(tab==='messages')render().catch(()=>{});}},30000);
    presenceTimer=setInterval(()=>{if(user&&!document.hidden)db.rpc('ammar_set_presence',{p_show_last_seen:showLastSeen}).then(()=>{}).catch(()=>{});},60000);
  }

  function boot(){
    if(!window.ammarSupabase){setTimeout(boot,150);return;}
    db=window.ammarSupabase;
    db.auth.onAuthStateChange((event,session)=>{
      if(session?.user)start(session.user);
      else{
        user=null;activeConversation=null;
        if(refreshTimer)clearInterval(refreshTimer);
        if(presenceTimer)clearInterval(presenceTimer);
        if(messageChannel)db.removeChannel(messageChannel).catch(()=>{});
        $('ammarEcosystemView')?.classList.remove('active');
      }
    });
    db.auth.getSession().then(r=>{if(r.data?.session?.user)start(r.data.session.user);}).catch(err=>console.warn('AMMAR ecosystem auth:',err.message));
    bind();
  }

  boot();
})();