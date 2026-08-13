
(() => {
  const cfg = window.GOYA_CONFIG || {};
  let sb = null;
  const state = {token:null, user:null, data:null, cart:[], history:{}, admin:false};

  function $(id){return document.getElementById(id)}
  function esc(v){return String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}
  function fmtDate(v){if(!v)return ''; try{return new Date(v).toLocaleString('en-AE',{dateStyle:'medium',timeStyle:'short'})}catch{return v}}
  function today(){return new Date().toISOString().slice(0,10)}
  function monthStart(){const d=new Date();return new Date(d.getFullYear(),d.getMonth(),1).toISOString().slice(0,10)}
  function money(v){return v==null||v===''?'':Number(v).toFixed(2)}
  function toast(msg,error=false){const t=document.createElement('div');t.className='toast'+(error?' err':'');t.textContent=msg;document.body.appendChild(t);setTimeout(()=>t.remove(),3200)}
  function downloadBlob(name,blob){const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download=name;document.body.appendChild(a);a.click();setTimeout(()=>{URL.revokeObjectURL(a.href);a.remove()},500)}
  function csv(rows,headers,name){
    const q=v=>`"${String(v??'').replace(/"/g,'""')}"`;
    const text=[headers.map(q).join(','),...rows.map(r=>headers.map(h=>q(r[h])).join(','))].join('\r\n');
    downloadBlob(name,new Blob([text],{type:'text/csv;charset=utf-8'}));
  }
  function setActiveNav(btn){
    document.querySelectorAll('.nav button').forEach(b=>b.classList.remove('active'));
    btn?.classList.add('active');
  }
  function showPage(id){
    document.querySelectorAll('[data-page]').forEach(x=>x.classList.add('hidden'));
    $(id)?.classList.remove('hidden');
  }
  async function initClient(){
    if(!cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY || cfg.SUPABASE_ANON_KEY.includes('PASTE_')) throw new Error('Supabase key is not configured. Open config.js and paste your Publishable/anon key.');
    if(!window.supabase?.createClient) throw new Error('Supabase library did not load.');
    sb=window.supabase.createClient(cfg.SUPABASE_URL,cfg.SUPABASE_ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
    return sb;
  }
  async function rpc(name,args={}){
    if(!sb) await initClient();
    const {data,error}=await sb.rpc(name,args);
    if(error) throw new Error(error.message);
    return data;
  }
  function saveLocal(k,v){localStorage.setItem(k,JSON.stringify(v))}
  function getLocal(k){try{return JSON.parse(localStorage.getItem(k))}catch{return null}}
  function clearSession(){localStorage.removeItem('goya_staff_session');localStorage.removeItem('goya_admin_session');state.token=null;state.user=null;state.data=null}
  function itemUnits(item){
    const a=[];if(item.storage_unit)a.push(item.storage_unit);if(item.ingredient_unit && !a.includes(item.ingredient_unit))a.push(item.ingredient_unit);return a;
  }
  function findItem(list,sku){return list.find(x=>x.sku===sku)}
  function splitQty(item,unit,qty){return unit===item.storage_unit?{storage_quantity:qty,ingredients_quantity:''}:{storage_quantity:'',ingredients_quantity:qty}}

  // ---------- shared boot ----------
  window.GoyaApp={state,toast,esc,fmtDate,showPage,setActiveNav,rpc,downloadBlob,csv,itemUnits,findItem,splitQty,today,monthStart};

  // ---------- STAFF ----------
  async function staffLogin(){
    const pin=$('staffPin')?.value.trim();
    if(!/^\d{4}$/.test(pin)){toast('Enter the 4-digit staff PIN.',true);return}
    try{
      await initClient();
      const data=await rpc('staff_login',{p_pin:pin});
      state.token=data.token;state.user=data;
      saveLocal('goya_staff_session',{token:data.token,user:data});
      await staffLoad();
      $('staffLogin').classList.add('hidden');$('staffApp').classList.remove('hidden');
      $('welcome').textContent=`Welcome, ${data.name}`;
      toast(`Welcome, ${data.name}`);
    }catch(e){toast(e.message,true)}
  }
  async function staffLoad(){
    const d=await rpc('staff_bootstrap',{p_token:state.token});
    state.data=d;
    renderStaffAccess();
    populateStaffItems();
    renderReasons();
    renderInfo();
    renderInventoryAccess();
    await staffHistory();
  }
  function renderStaffAccess(){
    const a=state.user.access||{};
    const map={order:'navOrder',production:'navProduction',wastage:'navWastage',inventory:'navInventory'};
    Object.entries(map).forEach(([k,id])=>$(id)?.classList.toggle('hidden',!a[k]));
  }
  function populateStaffItems(){
    const list=state.data.internal_items||[];
    const el=$('prodSearch'); if(el) el.value='';
    const el2=$('wasteSearch'); if(el2) el2.value='';
    window._staffItemList=list;
  }
  function searchItems(kind){
    const input=$(kind==='production'?'prodSearch':'wasteSearch');
    const box=$(kind==='production'?'prodResults':'wasteResults');
    const q=input.value.trim().toLowerCase();
    const list=(state.data.internal_items||[]).filter(x=>!q||x.name.toLowerCase().includes(q)||x.sku.toLowerCase().includes(q)).slice(0,25);
    box.innerHTML=list.map(x=>`<div class="result" onclick="GoyaStaff.pickItem('${kind}','${esc(x.sku)}')"><div><div class="name">${esc(x.name)}</div><div class="small muted">${esc(x.sku)} · ${esc(x.items_type||'')}</div></div><span class="tag">${esc(x.storage_unit)} / ${esc(x.ingredient_unit)}</span></div>`).join('')||'<div class="empty">No matching item.</div>';
  }
  function pickItem(kind,sku){
    const item=findItem(state.data.internal_items||[],sku); if(!item)return;
    window._selectedStaffItem={kind,item};
    const box=$(kind==='production'?'prodSelected':'wasteSelected');
    box.classList.remove('hidden');
    box.innerHTML=`<div class="card" style="box-shadow:none"><div class="section-title"><div><strong>${esc(item.name)}</strong><div class="small muted">${esc(item.sku)}</div></div><span class="tag">${esc(item.items_type)}</span></div>
      <div class="form-grid">
        <div class="field"><label>Quantity</label><input id="${kind}Qty" type="number" step="0.001" min="0.001"></div>
        <div class="field"><label>Unit</label><select id="${kind}Unit">${itemUnits(item).map(u=>`<option>${esc(u)}</option>`).join('')}</select></div>
        ${kind==='wastage'?`<div class="field"><label>Reason</label><select id="wasteReason">${(state.data.wastage_reasons||[]).map(r=>`<option value="${esc(r.name)}">${esc(r.name)}</option>`).join('')}</select></div>`:''}
        <div class="field" style="align-self:end"><button class="btn" onclick="GoyaStaff.addLine('${kind}')">Add to review list</button></div>
      </div></div>`;
    inputClear(kind);
  }
  function inputClear(kind){$(kind==='production'?'prodResults':'wasteResults').innerHTML='';$(kind==='production'?'prodSearch':'wasteSearch').value=''}
  function addLine(kind){
    const sel=window._selectedStaffItem;if(!sel||sel.kind!==kind)return;
    const qty=Number($(kind+'Qty').value),unit=$(kind+'Unit').value;
    if(!qty||qty<=0){toast('Enter a valid quantity.',true);return}
    const item=sel.item;
    const x={name:item.name,sku:item.sku,quantity:qty,unit,...splitQty(item,unit,qty)};
    if(kind==='wastage')x.reason=$('wasteReason').value;
    const arr=kind==='production'?state.prodCart:(state.wasteCart||(state.wasteCart=[]));
    if(arr.some(a=>a.sku===x.sku)){toast('Same item is already in the list. Remove it first if you need to change it.',true);return}
    arr.push(x);renderStaffCart(kind);
    $(kind+'Selected').classList.add('hidden');window._selectedStaffItem=null;
  }
  function renderStaffCart(kind){
    const arr=kind==='production'?state.prodCart:(state.wasteCart||[]);
    const body=$(kind+'CartBody');
    body.innerHTML=arr.length?arr.map((x,i)=>`<tr><td>${esc(x.name)}<div class="small muted">${esc(x.sku)}</div></td><td>${x.quantity}</td><td>${esc(x.unit)}</td>${kind==='wastage'?`<td>${esc(x.reason)}</td>`:''}<td><button class="btn danger" style="padding:6px 9px" onclick="GoyaStaff.removeLine('${kind}',${i})">Remove</button></td></tr>`).join(''):`<tr><td colspan="${kind==='wastage'?5:4}" class="empty">Nothing added yet.</td></tr>`;
    $('submit'+kind[0].toUpperCase()+kind.slice(1)).disabled=!arr.length;
  }
  function removeLine(kind,i){(kind==='production'?state.prodCart:state.wasteCart).splice(i,1);renderStaffCart(kind)}
  async function submitProduction(){
    try{const r=await rpc('submit_production',{p_token:state.token,p_items:state.prodCart});state.prodCart=[];renderStaffCart('production');toast(`Production submitted (${r.count} item${r.count===1?'':'s'}).`);await staffHistory()}catch(e){toast(e.message,true)}
  }
  async function submitWastage(){
    try{const r=await rpc('submit_wastage',{p_token:state.token,p_items:state.wasteCart});state.wasteCart=[];renderStaffCart('wastage');toast(`Wastage submitted (${r.count} item${r.count===1?'':'s'}).`);await staffHistory()}catch(e){toast(e.message,true)}
  }

  function searchMaster(){
    const q=$('orderSearch').value.trim().toLowerCase(),box=$('orderResults');
    const list=(state.data.master_items||[]).filter(x=>!q||x.name.toLowerCase().includes(q)||x.sku.toLowerCase().includes(q)).slice(0,30);
    box.innerHTML=list.map(x=>`<div class="result" onclick="GoyaStaff.pickOrderItem('${esc(x.sku)}')"><div><div class="name">${esc(x.name)}</div><div class="small muted">${esc(x.sku)} · ${esc(x.supplier||'No supplier')}</div></div><span class="tag">${esc(x.storage_unit)} / ${esc(x.ingredient_unit)}</span></div>`).join('')||'<div class="empty">No matching item.</div>';
  }
  function pickOrderItem(sku){
    const item=findItem(state.data.master_items||[],sku);if(!item)return;
    window._selectedOrder=item;$('orderResults').innerHTML='';
    $('orderSelected').classList.remove('hidden');
    $('orderSelected').innerHTML=`<div class="card" style="box-shadow:none"><div class="section-title"><div><strong>${esc(item.name)}</strong><div class="small muted">${esc(item.sku)}</div></div><span class="tag">${esc(item.supplier||'No supplier')}</span></div>
    <div class="form-grid">
      <div class="field"><label>Quantity</label><input id="orderQty" type="number" min="0.001" step="0.001"></div>
      <div class="field"><label>Unit</label><select id="orderUnit">${itemUnits(item).map(u=>`<option>${esc(u)}</option>`).join('')}</select></div>
      <div class="field"><label>Supplier (automatic)</label><input value="${esc(item.supplier||'')}" disabled></div>
      <div class="field" style="align-self:end"><button class="btn" onclick="GoyaStaff.addOrderLine()">Add to cart</button></div>
    </div></div>`;
    $('orderSearch').value='';
  }
  function addOrderLine(){
    const item=window._selectedOrder;if(!item)return;const qty=Number($('orderQty').value),unit=$('orderUnit').value;
    if(!qty||qty<=0){toast('Enter a valid quantity.',true);return}
    if(state.cart.some(x=>x.sku===item.sku)){toast('Same item is already in the order.',true);return}
    state.cart.push({name:item.name,sku:item.sku,quantity:qty,unit,supplier:item.supplier||''});
    $('orderSelected').classList.add('hidden');window._selectedOrder=null;renderOrderCart();
  }
  function renderOrderCart(){
    const body=$('orderCartBody');
    body.innerHTML=state.cart.length?state.cart.map((x,i)=>`<tr><td>${esc(x.name)}<div class="small muted">${esc(x.sku)}</div></td><td>${x.quantity}</td><td>${esc(x.unit)}</td><td>${esc(x.supplier||'')}</td><td><button class="btn danger" style="padding:6px 9px" onclick="GoyaStaff.removeOrder(${i})">Remove</button></td></tr>`).join(''):`<tr><td colspan="5" class="empty">Your cart is empty.</td></tr>`;
    $('submitOrder').disabled=!state.cart.length;
  }
  function removeOrder(i){state.cart.splice(i,1);renderOrderCart()}
  async function submitOrder(){
    const notes=$('orderNotes').value.trim();
    try{
      const r=await rpc('submit_order',{p_token:state.token,p_notes:notes,p_items:state.cart});
      const lines=state.cart.map(x=>`${x.name} — ${x.quantity} ${x.unit}${x.supplier?' — '+x.supplier:''}`).join('\n');
      const msg=`GOYA PURCHASE ORDER\nOrder: ${r.order_no}\nSubmitted by: ${state.user.name}\n\n${lines}${notes?'\n\nNotes: '+notes:''}`;
      state.cart=[];renderOrderCart();$('orderNotes').value='';toast('Order submitted successfully.');
      $('lastOrderActions').classList.remove('hidden');
      $('waOrder').onclick=()=>window.open('https://wa.me/?text='+encodeURIComponent(msg),'_blank');
      $('emailOrder').onclick=()=>location.href='mailto:'+encodeURIComponent(cfg.MANAGER_EMAIL||'')+'?subject='+encodeURIComponent('Goya Purchase Order '+r.order_no)+'&body='+encodeURIComponent(msg);
      $('lastOrderNo').textContent=r.order_no;
      await staffHistory();
    }catch(e){toast(e.message,true)}
  }

  async function staffHistory(){
    if(!state.token)return;
    try{const hm=$('historyMonth')?.value||new Date().toISOString().slice(0,7);state.history=await rpc('staff_history',{p_token:state.token,p_month:hm+'-01'});renderHistory()}catch(e){console.warn(e)}
  }
  function renderHistory(){
    const h=state.history||{};
    const active=document.querySelector('#historyTabs button.active')?.dataset.kind||'orders';
    const map={orders:['Order History',['order_no','name','quantity','unit','supplier','status','logged_by','created_at']],production:['Production History',['name','sku','quantity','unit','logged_by','created_at']],wastage:['Wastage History',['name','sku','quantity','unit','reason','logged_by','created_at']],inventory:['Inventory History',['item_name','sku','section','storage_quantity','ingredients_quantity','counted_by','counted_at']]};
    const [title,cols]=map[active],rows=h[active==='orders'?'orders':active]||[];
    $('historyTitle').textContent=title;
    $('historyBody').innerHTML=rows.length?rows.map(r=>`<tr>${cols.map(c=>`<td>${esc(c.includes('at')||c==='created_at'?fmtDate(r[c]):r[c])}</td>`).join('')}</tr>`).join(''):`<tr><td colspan="${cols.length}" class="empty">No records for this month.</td></tr>`;
    $('historyHead').innerHTML=cols.map(c=>`<th>${esc(c.replaceAll('_',' '))}</th>`).join('');
  }
  function renderReasons(){/* loaded for wastage form */}
  function renderInfo(){
    const pages=state.data?.info_pages||[];const tab=$('navInfo'),body=$('infoBody');
    if(pages.length){tab.classList.remove('hidden');body.innerHTML=pages.map(p=>`<div class="card"><h3>${esc(p.title)}</h3><div>${esc(p.body).replace(/\n/g,'<br>')}</div></div>`).join('')}
    else tab.classList.add('hidden');
  }
  function renderInventoryAccess(){
    const sessions=state.data?.inventory_sessions||[];const box=$('inventoryBody');
    if(!sessions.length){box.innerHTML='<div class="empty">No active inventory count assigned to you.</div>';return}
    box.innerHTML=sessions.map(s=>`<div class="card"><div class="section-title"><div><h3>${esc(s.title||'Inventory Count')}</h3><div class="small muted">${esc(s.month)} · Sections: ${esc((s.sections||[]).join(', ')||'All')}</div></div><span class="pill received">Active</span></div><div id="inv-${s.id}"></div></div>`).join('');
    sessions.forEach(s=>renderInventorySession(s));
  }
  function renderInventorySession(s){
    const internal=state.data.internal_items||[];const sections=s.sections?.length?s.sections:(state.user.access.sections?.length?state.user.access.sections:['Bar','Kitchen','Pastry','Packaging']);
    const target=$('inv-'+s.id);if(!target)return;
    target.innerHTML=`<div class="field"><label>Section</label><select id="invsec-${s.id}">${sections.map(x=>`<option>${esc(x)}</option>`).join('')}</select></div><div class="table-wrap" style="margin-top:10px"><table class="table"><thead><tr><th>Item</th><th>SKU</th><th>Storage Qty</th><th>Ingredients Qty</th></tr></thead><tbody>${internal.map(x=>`<tr><td>${esc(x.name)}</td><td>${esc(x.sku)}</td><td><input id="is-${s.id}-${esc(x.sku)}" type="number" step="0.001" min="0"></td><td><input id="ii-${s.id}-${esc(x.sku)}" type="number" step="0.001" min="0"></td></tr>`).join('')}</tbody></table></div><div style="margin-top:10px;text-align:right"><button class="btn ok" onclick="GoyaStaff.saveInventory('${s.id}')">Save Inventory Count</button></div>`;
  }
  async function saveInventory(sessionId){
    const s=(state.data.inventory_sessions||[]).find(x=>x.id===sessionId);if(!s)return;const sec=$('invsec-'+sessionId).value;
    const items=(state.data.internal_items||[]).map(x=>({item_name:x.name,sku:x.sku,section:sec,storage_quantity:$('is-'+sessionId+'-'+x.sku)?.value||'',ingredients_quantity:$('ii-'+sessionId+'-'+x.sku)?.value||''})).filter(x=>x.storage_quantity!==''||x.ingredients_quantity!=='');
    if(!items.length){toast('Enter at least one count.',true);return}
    try{await rpc('save_inventory_count',{p_token:state.token,p_session_id:sessionId,p_items:items});toast('Inventory count saved.');await staffHistory()}catch(e){toast(e.message,true)}
  }
  function staffLogout(){clearSession();location.reload()}
  function mobileMenu(){$('sidebar')?.classList.toggle('open')}

  window.GoyaStaff={staffLogin,searchItems,pickItem,addLine,removeLine,submitProduction,submitWastage,searchMaster,pickOrderItem,addOrderLine,removeOrder,submitOrder,staffHistory,renderHistory,saveInventory,staffLogout,mobileMenu};

  // ---------- ADMIN ----------
  async function adminLogin(){
    const pin=$('adminPin')?.value.trim();
    if(pin!=='9988'){toast('Invalid admin PIN.',true);return}
    try{
      await initClient();const d=await rpc('admin_login',{p_pin:pin});state.token=d.token;state.admin=true;saveLocal('goya_admin_session',{token:d.token});
      await adminLoad();$('adminLogin').classList.add('hidden');$('adminApp').classList.remove('hidden');toast('Admin panel unlocked.');
    }catch(e){toast(e.message,true)}
  }
  async function adminLoad(){state.adminData=await rpc('admin_bootstrap',{p_token:state.token});renderAdminAll();await loadAdminOrders()}
  function renderAdminAll(){
    const d=state.adminData||{};renderMasterTable();renderInternalTable();renderSuppliers();renderStaffTable();renderReasonsAdmin();renderSettings();renderInfoAdmin();renderInventorySessions();
    $('statItems').textContent=(d.master_items||[]).length;$('statInternal').textContent=(d.internal_items||[]).length;$('statStaff').textContent=(d.staff||[]).filter(x=>x.active).length;$('statSuppliers').textContent=(d.suppliers||[]).filter(x=>x.active).length;
  }
  function renderMasterTable(){
    const rows=state.adminData.master_items||[];$('masterBody').innerHTML=rows.map(x=>`<tr><td>${esc(x.row_id||'')}</td><td>${esc(x.name)}</td><td>${esc(x.sku)}</td><td>${esc(x.storage_unit)}</td><td>${esc(x.ingredient_unit)}</td><td>${esc(x.supplier||'')}</td><td>${esc(x.items_type)}</td><td><button class="btn danger" style="padding:6px 9px" onclick="GoyaAdmin.deleteItem('master_items','${x.id}')">Delete</button></td></tr>`).join('')||'<tr><td colspan="8" class="empty">No master items.</td></tr>';
  }
  function renderInternalTable(){
    const rows=state.adminData.internal_items||[];$('internalBody').innerHTML=rows.map(x=>`<tr><td>${esc(x.row_id||'')}</td><td>${esc(x.name)}</td><td>${esc(x.sku)}</td><td>${esc(x.storage_unit)}</td><td>${esc(x.ingredient_unit)}</td><td>${esc(x.items_type)}</td><td><button class="btn danger" style="padding:6px 9px" onclick="GoyaAdmin.deleteItem('internal_items','${x.id}')">Delete</button></td></tr>`).join('')||'<tr><td colspan="7" class="empty">No internal items.</td></tr>';
  }
  function renderSuppliers(){
    const rows=state.adminData.suppliers||[];$('supplierBody').innerHTML=rows.map(x=>`<tr><td>${esc(x.name)}</td><td>${esc(x.phone||'')}</td><td>${esc(x.email||'')}</td><td>${x.active?'Yes':'No'}</td><td><button class="btn secondary" style="padding:6px 9px" onclick="GoyaAdmin.editSupplier('${x.id}')">Edit</button> <button class="btn danger" style="padding:6px 9px" onclick="GoyaAdmin.deleteItem('suppliers','${x.id}')">Delete</button></td></tr>`).join('')||'<tr><td colspan="5" class="empty">No suppliers.</td></tr>';
  }
  function renderStaffTable(){
    const rows=state.adminData.staff||[];$('staffBody').innerHTML=rows.map(x=>`<tr><td>${esc(x.name)}</td><td>${x.active?'Active':'Disabled'}</td><td>${x.can_order?'✓':'—'}</td><td>${x.can_production?'✓':'—'}</td><td>${x.can_wastage?'✓':'—'}</td><td>${x.can_inventory?'✓':'—'}</td><td>${esc((x.sections||[]).join(', '))}</td><td><button class="btn secondary" style="padding:6px 9px" onclick="GoyaAdmin.editStaff('${x.id}')">Edit</button> <button class="btn danger" style="padding:6px 9px" onclick="GoyaAdmin.deleteStaff('${x.id}')">Delete</button></td></tr>`).join('')||'<tr><td colspan="8" class="empty">No staff.</td></tr>';
  }
  function renderReasonsAdmin(){
    const rows=state.adminData.reasons||[];$('reasonBody').innerHTML=rows.map(x=>`<tr><td>${esc(x.name)}</td><td>${x.active?'Active':'Disabled'}</td><td><button class="btn danger" style="padding:6px 9px" onclick="GoyaAdmin.deleteReason('${x.id}')">Delete</button></td></tr>`).join('')||'<tr><td colspan="3" class="empty">No reasons.</td></tr>';
  }
  function renderSettings(){
    const s=state.adminData.settings||{};const wa=s.whatsapp?.phone||'';const email=s.admin?.email||cfg.MANAGER_EMAIL||'';
    $('managerEmail').value=email;$('waPhone').value=wa;$('infoEnabled').checked=!!s.portal?.additional_info_enabled;
  }
  function renderInfoAdmin(){
    const rows=state.adminData.info_pages||[];$('infoAdminBody').innerHTML=rows.map(x=>`<tr><td>${esc(x.title)}</td><td>${x.active?'Yes':'No'}</td><td>${x.sort_order}</td><td><button class="btn secondary" style="padding:6px 9px" onclick="GoyaAdmin.editInfo('${x.id}')">Edit</button> <button class="btn danger" style="padding:6px 9px" onclick="GoyaAdmin.deleteInfo('${x.id}')">Delete</button></td></tr>`).join('')||'<tr><td colspan="4" class="empty">No additional pages.</td></tr>';
  }
  function renderInventorySessions(){
    const rows=state.adminData.inventory_sessions||[];const staff=state.adminData.staff||[];$('invAssigned').innerHTML=staff.filter(x=>x.active).map(x=>`<option value="${x.id}">${esc(x.name)}</option>`).join('');$('invSessionBody').innerHTML=rows.map(x=>`<tr><td>${esc(x.month)}</td><td>${esc(x.title||'')}</td><td>${x.active?'Active':'Off'}</td><td>${esc((x.sections||[]).join(', '))}</td><td>${esc((x.assigned_staff_ids||[]).map(id=>staff.find(s=>s.id===id)?.name||id).join(', '))}</td><td><button class="btn secondary" style="padding:6px 9px" onclick="GoyaAdmin.editInventory('${x.id}')">Edit</button> <button class="btn danger" style="padding:6px 9px" onclick="GoyaAdmin.deleteInventory('${x.id}')">Delete</button></td></tr>`).join('')||'<tr><td colspan="6" class="empty">No inventory sessions.</td></tr>';
  }
  async function loadAdminOrders(){
    const args={p_token:state.token,p_from:null,p_to:null,p_status:$('orderStatusFilter')?.value||null,p_supplier:$('orderSupplierFilter')?.value||null,p_search:$('orderAdminSearch')?.value||null};
    const from=$('orderFrom')?.value,to=$('orderTo')?.value;if(from)args.p_from=new Date(from+'T00:00:00').toISOString();if(to)args.p_to=new Date(to+'T23:59:59.999').toISOString();
    try{state.adminOrders=await rpc('admin_orders',args);renderAdminOrders()}catch(e){toast(e.message,true)}
  }
  function renderAdminOrders(){
    const rows=state.adminOrders||[];$('dashboardOrdersBody').innerHTML=rows.slice(0,8).map(x=>`<tr><td>${esc(x.order_no)}</td><td>${esc(x.name)}</td><td>${x.quantity} ${esc(x.unit)}</td><td>${esc(x.supplier||'')}</td><td><span class="pill ${x.status.toLowerCase().replaceAll(' ','-')}">${esc(x.status)}</span></td><td>${esc(x.logged_by)}</td><td>${fmtDate(x.created_at)}</td></tr>`).join('')||'<tr><td colspan="7" class="empty">No orders.</td></tr>';$('adminOrdersBody').innerHTML=rows.map(x=>`<tr><td><input type="checkbox" class="orderCheck" value="${x.id}"></td><td>${esc(x.order_no)}</td><td>${esc(x.name)}<div class="small muted">${esc(x.sku)}</div></td><td>${x.quantity}</td><td>${esc(x.unit)}</td><td>${esc(x.supplier||'')}</td><td><span class="pill ${x.status.toLowerCase().replaceAll(' ','-')}">${esc(x.status)}</span></td><td>${esc(x.logged_by)}</td><td>${fmtDate(x.created_at)}</td><td>${esc(x.notes||x.group_notes||'')}</td></tr>`).join('')||'<tr><td colspan="10" class="empty">No orders match the filters.</td></tr>';
    const suppliers=[...new Set((state.adminData.suppliers||[]).map(x=>x.name))];$('orderSupplierFilter').innerHTML='<option value="">All suppliers</option>'+suppliers.map(x=>`<option>${esc(x)}</option>`).join('');
  }
  function selectedOrderIds(){return [...document.querySelectorAll('.orderCheck:checked')].map(x=>Number(x.value))}
  async function bulkStatus(){
    const ids=selectedOrderIds(),st=$('bulkStatus').value;if(!ids.length){toast('Select at least one order.',true);return}
    try{await rpc('admin_update_orders',{p_token:state.token,p_ids:ids,p_status:st,p_notes:$('bulkNotes').value||null});toast('Order status updated.');await loadAdminOrders()}catch(e){toast(e.message,true)}
  }
  async function deleteSelectedOrders(){
    const ids=selectedOrderIds();if(!ids.length){toast('Select at least one order.',true);return}if(!confirm(`Delete ${ids.length} selected order row(s)?`))return;
    try{await rpc('admin_delete_orders',{p_token:state.token,p_ids:ids});toast('Deleted.');await loadAdminOrders()}catch(e){toast(e.message,true)}
  }
  function exportOrders(){
    const rows=state.adminOrders||[];const masters=state.adminData?.master_items||[];
    csv(rows.map(x=>{const m=masters.find(z=>z.sku===x.sku)||{};return {name:x.name,sku:x.sku,order_quantity:x.quantity,storage_quantity:x.unit===m.storage_unit?x.quantity:'',total_cost:''}}),['name','sku','order_quantity','storage_quantity','total_cost'],'purchase_order.csv');
  }
  async function loadProductionWastage(kind){
    try{const from=$('pwFrom').value,to=$('pwTo').value;const d=await rpc('admin_production_wastage',{p_token:state.token,p_kind:kind,p_from:from?new Date(from+'T00:00:00').toISOString():null,p_to:to?new Date(to+'T23:59:59.999').toISOString():null});state.pw={kind,data:d};renderPW();}catch(e){toast(e.message,true)}
  }
  function renderPW(){const d=state.pw?.data||[];$('pwBody').innerHTML=d.map(x=>`<tr><td>${esc(x.name)}</td><td>${esc(x.sku)}</td><td>${x.storage_quantity??''}</td><td>${x.ingredients_quantity??''}</td><td>${esc(x.logged_by)}</td><td>${fmtDate(x.created_at)}</td>${state.pw.kind==='wastage'?`<td>${esc(x.reason)}</td>`:''}</tr>`).join('')||`<tr><td colspan="${state.pw.kind==='wastage'?7:6}" class="empty">No records.</td></tr>`}
  function exportPW(){
    const d=state.pw?.data||[],kind=state.pw.kind||'production';
    csv(d.map(x=>({name:x.name,sku:x.sku,storage_quantity:x.storage_quantity??'',ingredients_quantity:x.ingredients_quantity??''})),['name','sku','storage_quantity','ingredients_quantity'],kind+'.csv');
  }
  async function loadInventoryCounts(){
    try{const d=await rpc('admin_inventory_counts',{p_token:state.token,p_month:(($('invMonth').value||new Date().toISOString().slice(0,7))+'-01'),p_section:$('invSection').value||null});state.invCounts=d;renderInventoryCounts()}catch(e){toast(e.message,true)}
  }
  function renderInventoryCounts(){const d=state.invCounts||[];$('invCountBody').innerHTML=d.map(x=>`<tr><td>${esc(x.item_name)}</td><td>${esc(x.sku)}</td><td>${esc(x.section)}</td><td>${x.storage_quantity??''}</td><td>${x.ingredients_quantity??''}</td><td>${esc(x.counted_by||'')}</td><td>${fmtDate(x.counted_at)}</td></tr>`).join('')||'<tr><td colspan="7" class="empty">No inventory counts.</td></tr>'}
  function exportInventory(){const d=state.invCounts||[];csv(d.map(x=>({'Inventory Item Name':x.item_name,'Inventory Item SKU':x.sku,'Storage quantity':x.storage_quantity??'','Ingredients quantity':x.ingredients_quantity??'','Inventory Count ID':''})),['Inventory Item Name','Inventory Item SKU','Storage quantity','Ingredients quantity','Inventory Count ID'],'foodics-inventory-count.csv')}
  async function deleteItem(table,id){if(!confirm('Delete this item?'))return;try{await rpc('admin_delete_item',{p_token:state.token,p_table:table,p_id:id});await adminLoad();toast('Deleted.')}catch(e){toast(e.message,true)}}
  function editSupplier(id){const x=(state.adminData.suppliers||[]).find(y=>y.id===id);if(!x)return;$('supplierId').value=x.id;$('supplierName').value=x.name;$('supplierPhone').value=x.phone||'';$('supplierEmail').value=x.email||''}
  async function saveSupplier(){const row={id:$('supplierId').value||null,name:$('supplierName').value.trim(),phone:$('supplierPhone').value.trim(),email:$('supplierEmail').value.trim(),active:true};if(!row.name){toast('Supplier name required.',true);return}try{await rpc('admin_save_supplier',{p_token:state.token,p_row:row});$('supplierId').value='';$('supplierName').value='';$('supplierPhone').value='';$('supplierEmail').value='';await adminLoad();toast('Supplier saved.')}catch(e){toast(e.message,true)}}
  function editStaff(id){const x=(state.adminData.staff||[]).find(y=>y.id===id);if(!x)return;$('staffId').value=x.id;$('staffName').value=x.name;$('staffPinNew').value='';$('staffActive').checked=x.active;$('canOrder').checked=x.can_order;$('canProd').checked=x.can_production;$('canWaste').checked=x.can_wastage;$('canInv').checked=x.can_inventory;$('staffSections').value=(x.sections||[]).join(', ')}
  async function saveStaff(){const row={id:$('staffId').value||null,name:$('staffName').value.trim(),pin:$('staffPinNew').value.trim(),active:$('staffActive').checked,can_order:$('canOrder').checked,can_production:$('canProd').checked,can_wastage:$('canWaste').checked,can_inventory:$('canInv').checked,sections:$('staffSections').value.split(',').map(x=>x.trim()).filter(Boolean)};if(!row.name){toast('Staff name required.',true);return}if(!row.id&&!/^\d{4}$/.test(row.pin)){toast('New staff PIN must be 4 digits.',true);return}try{await rpc('admin_save_staff',{p_token:state.token,p_row:row});['staffId','staffName','staffPinNew','staffSections'].forEach(id=>$(id).value='');await adminLoad();toast('Staff saved.')}catch(e){toast(e.message,true)}}
  async function deleteStaff(id){if(!confirm('Delete this staff?'))return;try{await rpc('admin_delete_staff',{p_token:state.token,p_id:id});await adminLoad();toast('Staff deleted.')}catch(e){toast(e.message,true)}}
  async function saveReason(){const n=$('reasonName').value.trim();if(!n)return;try{await rpc('admin_save_reason',{p_token:state.token,p_name:n,p_id:null});$('reasonName').value='';await adminLoad();toast('Reason saved.')}catch(e){toast(e.message,true)}}
  async function deleteReason(id){if(!confirm('Delete this reason?'))return;try{await rpc('admin_delete_reason',{p_token:state.token,p_id:id});await adminLoad();toast('Reason deleted.')}catch(e){toast(e.message,true)}}
  async function saveSettings(){const settings={admin:{email:$('managerEmail').value.trim()},whatsapp:{phone:$('waPhone').value.trim()},portal:{additional_info_enabled:$('infoEnabled').checked}};try{await rpc('admin_save_settings',{p_token:state.token,p_settings:settings});await adminLoad();toast('Settings saved.')}catch(e){toast(e.message,true)}}
  function editInfo(id){const x=(state.adminData.info_pages||[]).find(y=>y.id===id);if(!x)return;$('infoId').value=x.id;$('infoTitle').value=x.title;$('infoBodyText').value=x.body;$('infoSort').value=x.sort_order;$('infoActive').checked=x.active}
  async function saveInfo(){const row={id:$('infoId').value||null,title:$('infoTitle').value.trim(),body:$('infoBodyText').value,sort_order:Number($('infoSort').value||0),active:$('infoActive').checked};if(!row.title){toast('Title required.',true);return}try{await rpc('admin_save_info_page',{p_token:state.token,p_row:row});['infoId','infoTitle','infoBodyText'].forEach(id=>$(id).value='');$('infoSort').value=0;$('infoActive').checked=true;await adminLoad();toast('Info page saved.')}catch(e){toast(e.message,true)}}
  async function deleteInfo(id){if(!confirm('Delete this page?'))return;try{await rpc('admin_delete_info_page',{p_token:state.token,p_id:id});await adminLoad();toast('Deleted.')}catch(e){toast(e.message,true)}}
  function editInventory(id){const x=(state.adminData.inventory_sessions||[]).find(y=>y.id===id);if(!x)return;$('invId').value=x.id;$('invSessionMonth').value=x.month;$('invTitle').value=x.title||'';$('invActive').checked=x.active;$('invSections').value=(x.sections||[]).join(', ');[...$('invAssigned').options].forEach(o=>o.selected=(x.assigned_staff_ids||[]).includes(o.value))}
  async function saveInventorySession(){const row={id:$('invId').value||null,month:$('invSessionMonth').value,title:$('invTitle').value.trim(),active:$('invActive').checked,sections:$('invSections').value.split(',').map(x=>x.trim()).filter(Boolean),assigned_staff_ids:[...$('invAssigned').selectedOptions].map(o=>o.value)};if(!row.month){toast('Month required.',true);return}try{await rpc('admin_inventory_save_session',{p_token:state.token,p_row:row});await adminLoad();toast('Inventory session saved.')}catch(e){toast(e.message,true)}}
  async function deleteInventory(id){if(!confirm('Delete this inventory session?'))return;try{await rpc('admin_delete_inventory_session',{p_token:state.token,p_id:id});await adminLoad();toast('Deleted.')}catch(e){toast(e.message,true)}}

  function handleUpload(kind,file){
    if(!file)return;
    const reader=new FileReader();
    reader.onload=async e=>{
      try{
        let rows=[];
        if(file.name.toLowerCase().endsWith('.csv')){
          const text=new TextDecoder().decode(e.target.result);rows=parseCSV(text);
        }else{
          if(!window.XLSX)throw new Error('Excel reader is not loaded.');
          const wb=XLSX.read(e.target.result,{type:'array'});const ws=wb.Sheets[wb.SheetNames[0]];rows=XLSX.utils.sheet_to_json(ws,{defval:''});
        }
        const normalized=rows.map(r=>normalizeImportRow(kind,r)).filter(x=>x.name&&x.sku);
        if(!normalized.length)throw new Error('No valid rows found. Check the template headers.');
        if(!confirm(`Import ${normalized.length} ${kind==='master'?'master':'internal'} item(s)? This replaces the current ${kind==='master'?'Master Items':'Internal Items'} table.`))return;
        const fn=kind==='master'?'admin_replace_master_items':'admin_replace_internal_items';
        const n=await rpc(fn,{p_token:state.token,p_rows:normalized});toast(`Imported ${n} rows.`);await adminLoad();
      }catch(err){toast(err.message,true)}
    };
    if(file.name.toLowerCase().endsWith('.csv'))reader.readAsArrayBuffer(file);else reader.readAsArrayBuffer(file);
  }
  function normalizeImportRow(kind,r){
    const get=(...names)=>{for(const n of names){if(r[n]!==undefined)return r[n];const key=Object.keys(r).find(k=>k.toLowerCase().replace(/[\s_]/g,'')===n.toLowerCase().replace(/[\s_]/g,''));if(key)return r[key]}return ''};
    return {row_id:get('Row ID','row_id','raw id'),name:String(get('Name','name')).trim(),sku:String(get('SKU','sku')).trim(),storage_unit:String(get('Storage Unit','storage_unit')).trim(),ingredient_unit:String(get('Ingredient Unit','ingredient_unit','Ingredients Unit')).trim(),supplier:kind==='master'?String(get('Supplier','supplier')).trim():undefined,items_type:String(get('Items Type','items_type','Item Type')).trim()||'Bar'};
  }
  function parseCSV(text){
    const rows=[];let row=[],cell='',quoted=false;
    for(let i=0;i<text.length;i++){const c=text[i],n=text[i+1];if(c==='"'&&quoted&&n==='"'){cell+='"';i++;continue}if(c==='"'){quoted=!quoted;continue}if(c===','&&!quoted){row.push(cell);cell='';continue}if((c==='\n'||c==='\r')&&!quoted){if(c==='\r'&&n==='\n')i++;row.push(cell);cell='';if(row.some(x=>x!==''))rows.push(row);row=[];continue}cell+=c}
    if(cell||row.length){row.push(cell);rows.push(row)}const headers=rows.shift()||[];return rows.map(r=>Object.fromEntries(headers.map((h,i)=>[h,r[i]??''])));
  }
  function downloadTemplate(kind){
    const rows=kind==='master'?[{'Row ID':'','Name':'','SKU':'','Storage Unit':'','Ingredient Unit':'','Supplier':'','Items Type':''}]:[{'Row ID':'','Name':'','SKU':'','Storage Unit':'','Ingredient Unit':'','Items Type':''}];
    csv(rows,Object.keys(rows[0]),kind==='master'?'Master_Items_Template.csv':'Internal_Items_Template.csv');
  }
  function uploadChange(kind){$(kind+'Upload').click()}

  function whatsappSupplier(){
    const rows=state.adminOrders||[];
    const groups={};rows.forEach(x=>{const k=x.supplier||'Unassigned';(groups[k]??=[]).push(x)});
    const keys=Object.keys(groups);if(!keys.length){toast('No filtered orders.',true);return}
    if(keys.length===1 || $('orderSupplierFilter').value){
      const k=$('orderSupplierFilter').value||keys[0],phone=(state.adminData.suppliers||[]).find(x=>x.name===k)?.phone||'';
      const lines=groups[k].map(x=>`• ${x.name} — ${x.quantity} ${x.unit}`).join('\n');
      const msg=`GOYA ORDER REQUEST\nSupplier: ${k}\n\n${lines}\n\nPlease confirm availability.`;
      const target=phone.replace(/\D/g,'');window.open((target?'https://wa.me/'+target+'?text=':'https://wa.me/?text=')+encodeURIComponent(msg),'_blank');return;
    }
    const first=keys[0], lines=groups[first].map(x=>`• ${x.name} — ${x.quantity} ${x.unit}`).join('\n');
    window.open('https://wa.me/?text='+encodeURIComponent(`GOYA ORDER REQUEST\nSupplier: ${first}\n\n${lines}`),'_blank');
    toast('Multiple suppliers found. Use the Supplier filter to send each supplier separately.');
  }
  function exportMasterFiltered(){
    const supplier=$('exportSupplier').value,type=$('exportType').value;
    const rows=(state.adminData.master_items||[]).filter(x=>(!supplier||x.supplier===supplier)&&(!type||x.items_type.toLowerCase()===type.toLowerCase()));
    csv(rows.map(x=>({'Row ID':x.row_id,'Name':x.name,'SKU':x.sku,'Storage Unit':x.storage_unit,'Ingredient Unit':x.ingredient_unit,'Supplier':x.supplier||'','Items Type':x.items_type})),['Row ID','Name','SKU','Storage Unit','Ingredient Unit','Supplier','Items Type'],'Master_Items.csv');
  }
  function exportInternalAll(){
    const rows=state.adminData.internal_items||[];
    csv(rows.map(x=>({'Row ID':x.row_id,'Name':x.name,'SKU':x.sku,'Storage Unit':x.storage_unit,'Ingredient Unit':x.ingredient_unit,'Items Type':x.items_type})),['Row ID','Name','SKU','Storage Unit','Ingredient Unit','Items Type'],'Internal_Items.csv');
  }

  function adminLogout(){clearSession();location.reload()}
  function adminNav(btn,page){setActiveNav(btn);showPage(page);$('sidebar')?.classList.remove('open')}
  function openMobileAdmin(){$('sidebar')?.classList.toggle('open')}

  window.GoyaAdmin={adminLogin,adminNav,openMobileAdmin,loadAdminOrders,bulkStatus,deleteSelectedOrders,exportOrders,whatsappSupplier,loadProductionWastage,exportPW,loadInventoryCounts,exportInventory,deleteItem,editSupplier,saveSupplier,editStaff,saveStaff,deleteStaff,saveReason,deleteReason,saveSettings,editInfo,saveInfo,deleteInfo,editInventory,saveInventorySession,deleteInventory,handleUpload,downloadTemplate,uploadChange,exportMasterFiltered,exportInternalAll,adminLogout};

  // ---------- generic startup ----------
  function bindSession(page){
    const key=page==='staff'?'goya_staff_session':'goya_admin_session';const s=getLocal(key);
    if(!s)return;
    state.token=s.token;state.user=s.user||null;state.admin=page==='admin';
    (async()=>{try{await initClient();if(page==='staff'){state.user=s.user;await staffLoad();$('staffLogin').classList.add('hidden');$('staffApp').classList.remove('hidden');$('welcome').textContent=`Welcome, ${state.user.name}`}else{await adminLoad();$('adminLogin').classList.add('hidden');$('adminApp').classList.remove('hidden')}}catch(e){localStorage.removeItem(key);toast(e.message,true)}})();
  }
  document.addEventListener('DOMContentLoaded',()=>{
    if(document.body.dataset.page==='staff'){state.prodCart=[];state.wasteCart=[];bindSession('staff')}
    if(document.body.dataset.page==='admin'){bindSession('admin')}
  });
})();
