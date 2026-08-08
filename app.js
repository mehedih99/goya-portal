(() => {
  const C = window.GOYA_CONFIG || {};
  const state = {
    role: null,
    staff: null,
    admin: false,
    tab: "dashboard",
    data: null,
    orderCart: [],
    apiUrl: C.API_URL || "",
    demo: !!C.ENABLE_DEMO_MODE
  };

  const demo = {
    settings: { MasterPin: C.DEFAULT_ADMIN_PIN || "9988", OwnerEmail: "", InventoryCountEnabled: "TRUE" },
    staff: [
      { "PIN Code":"1234", "Staff Full Name":"Demo Staff", "Allowed Sections":"kitchen,bar" },
      { "PIN Code":"5678", "Staff Full Name":"Demo Barista", "Allowed Sections":"bar" }
    ],
    suppliers: [{Name:"Safco",Phone:"0500000000"},{Name:"Demo Supplier",Phone:"0550000000"}],
    master_items: [
      {"Row ID":"1",Name:"Coffee Beans",SKU:"COF-001","Storage Unit":"kg","Ingredient Unit":"g",Supplier:"Safco","Items Type":"Bar"},
      {"Row ID":"2",Name:"Milk",SKU:"MIL-001","Storage Unit":"carton","Ingredient Unit":"ml",Supplier:"Safco","Items Type":"Bar"},
      {"Row ID":"3",Name:"Sugar Syrup",SKU:"SYP-001","Storage Unit":"bottle","Ingredient Unit":"ml",Supplier:"Demo Supplier","Items Type":"Internal"},
      {"Row ID":"4",Name:"Mozzarella",SKU:"MOZ-001","Storage Unit":"kg","Ingredient Unit":"g",Supplier:"Safco","Items Type":"Kitchen"},
      {"Row ID":"5",Name:"Cake Box",SKU:"PKG-001","Storage Unit":"pcs","Ingredient Unit":"pcs",Supplier:"Demo Supplier","Items Type":"Packaging"}
    ],
    orders: [
      {"Row ID":"1001",Timestamp:"2026-08-08 09:10", "Order Date":"2026-08-08", "Item Name":"Coffee Beans",Quantity:"5",Unit:"kg",Supplier:"Safco","Note/Remarks":"Urgent requirement","Status":"Pending","Logged By":"Demo Staff"},
      {"Row ID":"1002",Timestamp:"2026-08-07 15:20", "Order Date":"2026-08-07", "Item Name":"Milk",Quantity:"20",Unit:"carton",Supplier:"Safco","Note/Remarks":"","Status":"Ordered","Logged By":"Demo Barista"}
    ],
    production: [
      {Timestamp:"2026-08-08 08:30",Date:"2026-08-08","Item Name":"Sugar Syrup",Quantity:"3",Unit:"bottle","Logged By":"Demo Staff",Status:"Logged"}
    ],
    wastage: [
      {Timestamp:"2026-08-08 11:15",Date:"2026-08-08","Item Name":"Milk",Quantity:"1",Unit:"carton",Reason:"Expired","Logged By":"Demo Staff",Status:"Logged"}
    ],
    inventory_counts: []
  };

  function clone(x){ return JSON.parse(JSON.stringify(x)); }
  function esc(s){ return String(s ?? "").replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m])); }
  function toast(msg){ const d=document.createElement("div"); d.className="toast"; d.textContent=msg; document.body.appendChild(d); setTimeout(()=>d.remove(),2800); }
  function uid(){ return Date.now().toString(36)+Math.random().toString(36).slice(2,7); }
  function fmtDate(){ return new Date().toISOString().slice(0,10); }
  function badge(status){ const s=String(status||"").toLowerCase(); return `<span class="badge ${s}">${esc(status)}</span>`; }

  async function api(action, payload={}) {
    if (!state.apiUrl) {
      if (!state.demo) throw new Error("API URL is not configured.");
      return demoApi(action,payload);
    }
    const params = new URLSearchParams({action, payload: JSON.stringify(payload)});
    const url = state.apiUrl + (state.apiUrl.includes("?") ? "&" : "?") + params.toString();
    return new Promise((resolve,reject)=>{
      const cb = "__goya_cb_" + uid();
      const script = document.createElement("script");
      const timer = setTimeout(()=>{ cleanup(); reject(new Error("API request timed out.")); }, 15000);
      window[cb] = data => { cleanup(); resolve(data); };
      function cleanup(){ clearTimeout(timer); delete window[cb]; script.remove(); }
      script.onerror = ()=>{ cleanup(); reject(new Error("Unable to connect to Apps Script.")); };
      script.src = url + "&callback=" + cb;
      document.body.appendChild(script);
    });
  }

  function demoApi(action,payload){
    const d = demo;
    if(action==="getBootstrap") return clone(d);
    if(action==="loginStaff") return d.staff.find(x=>x["Staff Full Name"]===payload.name && x["PIN Code"]===payload.pin) || null;
    if(action==="verifyAdmin") return payload.pin === d.settings.MasterPin;
    if(action==="saveOrder") {
      payload.items.forEach(i=>d.orders.unshift({"Row ID":uid(),"Timestamp":new Date().toLocaleString(),"Order Date":fmtDate(),"Item Name":i.name,Quantity:i.qty,Unit:i.unit,Supplier:i.supplier,"Note/Remarks":i.note||"","Status":"Pending","Logged By":payload.loggedBy}));
      return {ok:true};
    }
    if(action==="saveProduction"){ d.production.unshift({...payload.item,Timestamp:new Date().toLocaleString(),Date:fmtDate(),LoggedBy:payload.loggedBy,Status:"Logged"}); return {ok:true}; }
    if(action==="saveWastage"){ d.wastage.unshift({...payload.item,Timestamp:new Date().toLocaleString(),Date:fmtDate(),LoggedBy:payload.loggedBy,Status:"Logged"}); return {ok:true}; }
    if(action==="updateOrder"){ const x=d.orders.find(r=>r["Row ID"]==payload.id); if(x) Object.assign(x,payload.patch); return {ok:true}; }
    if(action==="updateLog"){ const arr=payload.type==="Production"?d.production:d.wastage; const x=arr.find(r=>r.Timestamp===payload.id); if(x)x.Status=payload.status; return {ok:true}; }
    if(action==="saveItem"){ d.master_items.push({...payload.item,"Row ID":uid()}); return {ok:true}; }
    if(action==="saveStaff"){ d.staff.push(payload.staff); return {ok:true}; }
    if(action==="saveSupplier"){ d.suppliers.push(payload.supplier); return {ok:true}; }
    if(action==="saveSettings"){ Object.assign(d.settings,payload.settings); return {ok:true}; }
    if(action==="saveInventory"){ d.inventory_counts.push(...payload.rows); return {ok:true}; }
    return {ok:true};
  }

  function shell(title, subtitle, content, nav=true){
    const navItems = state.admin
      ? [["dashboard","Dashboard"],["orders","Orders"],["items","Items & Suppliers"],["staff","Staff"],["monitor","Monitor"],["counts","Inventory Counts"],["export","Export"],["settings","Settings"]]
      : [["order","Send Order"],["production","Production"],["wastage","Wastage"],["count","Inventory Count"],["history","History"]];
    const navHtml = nav ? navItems.map(([id,label])=>`<button class="nav-btn ${state.tab===id?'active':''}" data-tab="${id}">${label}</button>`).join("") : "";
    return `<div class="app-shell">
      <header class="topbar">
        <div class="brand"><div class="brand-mark">G</div><div>${esc(C.COMPANY_NAME||"Goya")}<small>${esc(C.COMPANY_SUBTITLE||"Operations Portal")}</small></div></div>
        <div class="top-actions"><span class="note">${state.admin?"Admin Workspace":esc(state.staff?.["Staff Full Name"]||"Staff Portal")}</span><button class="btn small" id="logout">Logout</button></div>
      </header>
      <div class="layout">
        <aside class="sidebar">${navHtml}</aside>
        <main class="main"><div class="page-head"><div><h1>${esc(title)}</h1><p>${esc(subtitle)}</p></div></div>${content}</main>
      </div>
      <nav class="mobile-nav">${navHtml}</nav>
      <div id="modal-root"></div>
    </div>`;
  }

  async function loadData(){
    state.data = await api("getBootstrap");
    return state.data;
  }

  function render(){
    if(!state.role){ renderLogin(); return; }
    if(state.admin){ renderAdmin(); } else { renderStaff(); }
  }

  function renderLogin(){
    document.getElementById("app").innerHTML = `<div class="pin-screen">
      <div class="auth-card">
        <div class="brand"><div class="brand-mark">G</div><div>Goya<small>Operations Portal V2</small></div></div>
        <div style="margin-top:26px">
          <h2 style="margin-bottom:6px">Choose access</h2>
          <p class="note">Mobile-first operations workspace for orders, production, wastage and inventory.</p>
        </div>
        <div class="grid grid-2" style="margin-top:20px">
          <button class="btn primary" id="staffAccess">Staff Portal</button>
          <button class="btn" id="adminAccess">Admin Workspace</button>
        </div>
        <p class="note" style="margin-top:18px">Backend: ${state.apiUrl ? "Connected URL configured" : "Demo mode — configure config.js before production use"}</p>
      </div>
    </div>`;
    document.getElementById("staffAccess").onclick=()=>staffLogin();
    document.getElementById("adminAccess").onclick=()=>adminLogin();
  }

  async function staffLogin(){
    try { state.data = await loadData(); } catch(e){ toast(e.message); return; }
    let selected = null, pin="";
    const renderAuth=()=>{
      document.getElementById("app").innerHTML=`<div class="pin-screen"><div class="auth-card">
        <div class="brand"><div class="brand-mark">G</div><div>Goya<small>Staff Portal</small></div></div>
        <h2 style="margin:24px 0 4px">Select your name</h2>
        <p class="note">Then enter your 4-digit staff PIN.</p>
        <div class="staff-grid">${state.data.staff.map(s=>`<button class="staff-choice ${selected?.["Staff Full Name"]===s["Staff Full Name"]?'active':''}" data-name="${esc(s["Staff Full Name"])}">${esc(s["Staff Full Name"])}</button>`).join("")}</div>
        <div class="pin-display">${[0,1,2,3].map(i=>`<span class="pin-dot ${pin.length>i?'filled':''}"></span>`).join("")}</div>
        <div class="keypad">${["1","2","3","4","5","6","7","8","9","⌫","0","Enter"].map(k=>`<button class="key" data-key="${k}">${k}</button>`).join("")}</div>
        <button class="btn" id="back" style="width:100%;margin-top:12px">Back</button>
      </div></div>`;
      document.querySelectorAll(".staff-choice").forEach(b=>b.onclick=()=>{ selected=state.data.staff.find(s=>s["Staff Full Name"]===b.dataset.name); pin=""; renderAuth(); });
      document.querySelectorAll(".key").forEach(b=>b.onclick=async()=>{ const k=b.dataset.key; if(k==="⌫") pin=pin.slice(0,-1); else if(k==="Enter"){ if(!selected){toast("Select a staff member.");return;} if(pin.length!==4){toast("Enter 4 digits.");return;} const ok=await api("loginStaff",{name:selected["Staff Full Name"],pin}); if(ok){state.role="staff";state.staff=ok;state.admin=false;state.tab="order";render();}else{toast("Invalid PIN.");pin="";}} else if(pin.length<4) pin+=k; renderAuth(); });
      document.getElementById("back").onclick=renderLogin;
    };
    renderAuth();
  }

  async function adminLogin(){
    let pin="";
    const renderAuth=()=>{ document.getElementById("app").innerHTML=`<div class="pin-screen"><div class="auth-card">
      <div class="brand"><div class="brand-mark">G</div><div>Goya<small>Admin Workspace</small></div></div>
      <h2 style="margin:24px 0 4px">Master PIN</h2><p class="note">Enter the 4-digit administrator PIN.</p>
      <div class="pin-display">${[0,1,2,3].map(i=>`<span class="pin-dot ${pin.length>i?'filled':''}"></span>`).join("")}</div>
      <div class="keypad">${["1","2","3","4","5","6","7","8","9","⌫","0","Enter"].map(k=>`<button class="key" data-key="${k}">${k}</button>`).join("")}</div>
      <button class="btn" id="back" style="width:100%;margin-top:12px">Back</button>
    </div></div>`;
      document.querySelectorAll(".key").forEach(b=>b.onclick=async()=>{const k=b.dataset.key;if(k==="⌫")pin=pin.slice(0,-1);else if(k==="Enter"){if(pin.length!==4){toast("Enter 4 digits.");return;}const ok=await api("verifyAdmin",{pin});if(ok){state.role="admin";state.admin=true;state.tab="dashboard";await loadData();render();}else{toast("Invalid Master PIN.");pin="";}}else if(pin.length<4)pin+=k;renderAuth();});
      document.getElementById("back").onclick=renderLogin;
    }; renderAuth();
  }

  function bindNav(){
    document.querySelectorAll("[data-tab]").forEach(b=>b.onclick=()=>{state.tab=b.dataset.tab;render();});
    const out=document.getElementById("logout"); if(out)out.onclick=()=>{state.role=null;state.staff=null;state.admin=false;state.data=null;render();};
  }

  async function renderStaff(){
    if(!state.data) await loadData();
    let title="", sub="", content="";
    if(state.tab==="order"){ title="Send Order";sub="Build and dispatch a supplier purchase order.";
      const items=state.data.master_items.filter(x=>!["Internal"].includes(x["Items Type"]));
      content=`<div class="card"><div class="toolbar"><input id="orderSearch" class="input" placeholder="Search items..." /><select id="supplierFilter"><option value="">All suppliers</option>${[...new Set(items.map(x=>x.Supplier).filter(Boolean))].map(x=>`<option>${esc(x)}</option>`).join("")}</select></div><div id="orderItems"></div></div>
      <div class="card" style="margin-top:16px"><div class="page-head" style="margin-bottom:12px"><div><h3 style="margin:0">Order Cart</h3><p class="note">Add quantities, units and remarks.</p></div></div><div id="cart"></div><button class="btn primary" id="submitOrder" style="margin-top:12px">Submit Order & WhatsApp</button></div>`;
      document.getElementById("app").innerHTML=shell(title,sub,content); bindNav(); setupOrder(items);
    } else if(state.tab==="production"){ title="Production";sub="Log daily in-house batch preparations."; content=productionView(); document.getElementById("app").innerHTML=shell(title,sub,content);bindNav();setupProduction();
    } else if(state.tab==="wastage"){ title="Wastage";sub="Record expired, damaged or over-prepared stock."; content=wastageView();document.getElementById("app").innerHTML=shell(title,sub,content);bindNav();setupWastage();
    } else if(state.tab==="count"){ title="Inventory Count";sub="Monthly physical count by assigned section."; content=countView();document.getElementById("app").innerHTML=shell(title,sub,content);bindNav();setupCount();
    } else { title="History";sub="Review your previously submitted operational records."; content=historyView();document.getElementById("app").innerHTML=shell(title,sub,content);bindNav(); }
  }

  function setupOrder(items){
    const renderItems=()=>{
      const q=(document.getElementById("orderSearch").value||"").toLowerCase(), sup=document.getElementById("supplierFilter").value;
      const list=items.filter(x=>(!q||[x.Name,x.SKU,x.Supplier].join(" ").toLowerCase().includes(q))&&(!sup||x.Supplier===sup));
      document.getElementById("orderItems").innerHTML=list.map(x=>`<div class="item-row"><div><b>${esc(x.Name)}</b><div class="note">${esc(x.SKU)} · ${esc(x.Supplier||"No supplier")}</div></div><input class="input qty" type="number" min="0" step="any" data-id="${esc(x["Row ID"])}" placeholder="Qty"><div><select class="unit" data-id="${esc(x["Row ID"])}"><option>${esc(x["Storage Unit"])}</option></select></div><button class="btn small add-item" data-id="${esc(x["Row ID"])}">Add</button></div>`).join("") || `<div class="empty">No items found.</div>`;
      document.querySelectorAll(".add-item").forEach(b=>b.onclick=()=>{const x=items.find(i=>i["Row ID"]===b.dataset.id);const qty=document.querySelector(`.qty[data-id="${b.dataset.id}"]`).value;if(!qty||Number(qty)<=0){toast("Enter a quantity.");return;}state.orderCart.push({name:x.Name,qty,unit:x["Storage Unit"],supplier:x.Supplier||"",note:""});renderCart();toast("Added to cart.");});
    };
    const renderCart=()=>{ const el=document.getElementById("cart"); el.innerHTML=state.orderCart.length?state.orderCart.map((x,i)=>`<div class="item-row"><div><b>${esc(x.name)}</b><div class="note">${esc(x.supplier)}</div></div><input class="input" type="number" min="0" step="any" value="${esc(x.qty)}" data-i="${i}" data-field="qty"><div><b>${esc(x.unit)}</b></div><button class="btn small danger remove-cart" data-i="${i}">Remove</button><div class="remarks" style="grid-column:1/-1"><input class="input" placeholder="Note / Remarks" value="${esc(x.note)}" data-i="${i}" data-field="note"></div></div>`).join(""):`<div class="empty">Cart is empty.</div>`;
      document.querySelectorAll("[data-field]").forEach(e=>e.oninput=()=>state.orderCart[+e.dataset.i][e.dataset.field]=e.value);
      document.querySelectorAll(".remove-cart").forEach(b=>b.onclick=()=>{state.orderCart.splice(+b.dataset.i,1);renderCart();});
    };
    document.getElementById("orderSearch").oninput=renderItems;document.getElementById("supplierFilter").onchange=renderItems;renderItems();renderCart();
    document.getElementById("submitOrder").onclick=async()=>{if(!state.orderCart.length){toast("Add at least one item.");return;}try{await api("saveOrder",{items:state.orderCart,loggedBy:state.staff["Staff Full Name"]});const text=`Goya Order%0A%0A`+state.orderCart.map(x=>`• ${x.name} — ${x.qty} ${x.unit}${x.note?` — ${x.note}`:""}`).join("%0A");const phone=(state.data.suppliers.find(s=>s.Name===state.orderCart[0].supplier)||{}).Phone||"";window.open(`https://wa.me/${String(phone).replace(/\\D/g,"")}?text=${text}`,"_blank");state.orderCart=[];toast("Order saved.");await loadData();render();}catch(e){toast(e.message);}};
  }

  function productionView(){const items=state.data.master_items.filter(x=>x["Items Type"]==="Internal");return `<div class="card"><div class="form-grid"><div class="field"><label>Item</label><select id="prodItem">${items.map(x=>`<option value="${esc(x.Name)}" data-unit="${esc(x["Storage Unit"])}">${esc(x.Name)}</option>`).join("")}</select></div><div class="field"><label>Quantity</label><input id="prodQty" class="input" type="number" min="0" step="any"></div><div class="field"><label>Unit</label><input id="prodUnit" class="input" readonly></div></div><button class="btn primary" id="prodSave" style="margin-top:14px">Log Production</button></div>`}
  function setupProduction(){const sel=document.getElementById("prodItem"),unit=()=>document.getElementById("prodUnit").value=sel.selectedOptions[0]?.dataset.unit||"";sel.onchange=unit;unit();document.getElementById("prodSave").onclick=async()=>{const q=document.getElementById("prodQty").value;if(!q||q<=0){toast("Enter quantity.");return;}try{await api("saveProduction",{loggedBy:state.staff["Staff Full Name"],item:{"Item Name":sel.value,Quantity:q,Unit:document.getElementById("prodUnit").value}});toast("Production logged.");}catch(e){toast(e.message);}}}
  function wastageView(){const items=state.data.master_items;return `<div class="card"><div class="form-grid"><div class="field"><label>Item</label><select id="wItem">${items.map(x=>`<option>${esc(x.Name)}</option>`).join("")}</select></div><div class="field"><label>Quantity</label><input id="wQty" class="input" type="number" min="0" step="any"></div><div class="field"><label>Unit</label><input id="wUnit" class="input" value="pcs"></div><div class="field"><label>Reason</label><select id="wReason"><option>Expired</option><option>Spillage / Damaged</option><option>Over-prepared</option><option>Staff Mistake</option></select></div></div><button class="btn danger" id="wSave" style="margin-top:14px">Log Wastage</button></div>`}
  function setupWastage(){document.getElementById("wSave").onclick=async()=>{const q=document.getElementById("wQty").value;if(!q||q<=0){toast("Enter quantity.");return;}try{await api("saveWastage",{loggedBy:state.staff["Staff Full Name"],item:{"Item Name":document.getElementById("wItem").value,Quantity:q,Unit:document.getElementById("wUnit").value,Reason:document.getElementById("wReason").value}});toast("Wastage logged.");}catch(e){toast(e.message);}}}
  function countView(){const enabled=String(state.data.settings.InventoryCountEnabled).toUpperCase()==="TRUE";if(!enabled)return `<div class="card empty"><b>Inventory Count is currently disabled.</b><br>Ask an administrator to activate the module.</div>`;const allowed=(state.staff["Allowed Sections"]||"").split(",").map(x=>x.trim().toLowerCase());const items=state.data.master_items.filter(x=>allowed.includes(String(x["Items Type"]).toLowerCase())||allowed.includes(String(x["Items Type"]).toLowerCase()+"s"));return `<div class="card"><p class="note">Only your assigned sections are shown.</p><div class="table-wrap"><table><thead><tr><th>Item</th><th>SKU</th><th>Storage Qty</th><th>Ingredient Qty</th></tr></thead><tbody>${items.map((x,i)=>`<tr><td>${esc(x.Name)}</td><td>${esc(x.SKU)}</td><td><input class="input count-storage" data-i="${i}" type="number" step="any"></td><td><input class="input count-ingredient" data-i="${i}" type="number" step="any"></td></tr>`).join("")||`<tr><td colspan="4" class="empty">No items assigned to your sections.</td></tr>`}</tbody></table></div><button class="btn primary" id="countSave" style="margin-top:14px">Submit Monthly Count</button></div>`}
  function setupCount(){const btn=document.getElementById("countSave");if(!btn)return;btn.onclick=async()=>{const allowed=(state.staff["Allowed Sections"]||"").split(",").map(x=>x.trim().toLowerCase());const items=state.data.master_items.filter(x=>allowed.includes(String(x["Items Type"]).toLowerCase())||allowed.includes(String(x["Items Type"]).toLowerCase()+"s"));const rows=items.map((x,i)=>({"Count Date / Month":fmtDate().slice(0,7),"Section":x["Items Type"],"Item Name":x.Name,SKU:x.SKU,"Storage Quantity":document.querySelector(`.count-storage[data-i="${i}"]`).value,"Ingredient Quantity":document.querySelector(`.count-ingredient[data-i="${i}"]`).value,"Submitted By":state.staff["Staff Full Name"]}));try{await api("saveInventory",{rows});toast("Inventory count submitted.");}catch(e){toast(e.message);}}}
  function historyView(){const name=state.staff["Staff Full Name"];const o=state.data.orders.filter(x=>x["Logged By"]===name),p=state.data.production.filter(x=>x.LoggedBy===name),w=state.data.wastage.filter(x=>x.LoggedBy===name);return `<div class="grid grid-3"><div class="kpi card"><div class="label">Orders</div><div class="value">${o.length}</div></div><div class="kpi card"><div class="label">Production</div><div class="value">${p.length}</div></div><div class="kpi card"><div class="label">Wastage</div><div class="value">${w.length}</div></div></div><div class="card" style="margin-top:16px"><h3>Orders</h3>${historyTable(o,["Order Date","Item Name","Quantity","Unit","Supplier","Status","Note/Remarks"])}</div><div class="card" style="margin-top:16px"><h3>Production</h3>${historyTable(p,["Date","Item Name","Quantity","Unit","Status"])}</div><div class="card" style="margin-top:16px"><h3>Wastage</h3>${historyTable(w,["Date","Item Name","Quantity","Unit","Reason","Status"])}</div>`}
  function historyTable(rows,cols){if(!rows.length)return `<div class="empty">No records.</div>`;return `<div class="table-wrap"><table><thead><tr>${cols.map(c=>`<th>${esc(c)}</th>`).join("")}</tr></thead><tbody>${rows.map(r=>`<tr>${cols.map(c=>`<td>${c==="Status"?badge(r[c]):esc(r[c])}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`}

  async function renderAdmin(){
    if(!state.data) await loadData();
    let title="",sub="",content="";
    if(state.tab==="dashboard"){title="Dashboard";sub="Live overview of Goya operations.";content=dashboardView();}
    if(state.tab==="orders"){title="Orders Management";sub="Filter, review and update purchase orders.";content=adminOrdersView();}
    if(state.tab==="items"){title="Items & Suppliers";sub="Manage the master catalog and vendor directory.";content=itemsView();}
    if(state.tab==="staff"){title="Staff Directory";sub="Manage staff PINs and section permissions.";content=staffView();}
    if(state.tab==="monitor"){title="Production & Wastage Monitor";sub="Audit operational logs and review status.";content=monitorView();}
    if(state.tab==="counts"){title="Inventory Counts";sub="Control and audit monthly physical counts.";content=countsAdminView();}
    if(state.tab==="export"){title="Data Export Center";sub="Generate CSV files for Foodics and raw backups.";content=exportView();}
    if(state.tab==="settings"){title="Settings";sub="Configure connection, security and notifications.";content=settingsView();}
    document.getElementById("app").innerHTML=shell(title,sub,content);bindNav();
    if(state.tab==="orders")setupAdminOrders(); if(state.tab==="items")setupItems(); if(state.tab==="staff")setupStaff(); if(state.tab==="monitor")setupMonitor(); if(state.tab==="counts")setupCountsAdmin(); if(state.tab==="export")setupExport(); if(state.tab==="settings")setupSettings();
  }

  function dashboardView(){const d=state.data;const pending=d.orders.filter(x=>x.Status==="Pending").length,ordered=d.orders.filter(x=>x.Status==="Ordered").length,received=d.orders.filter(x=>x.Status==="Received").length;return `<div class="grid grid-4"><div class="kpi card"><div class="label">Pending Orders</div><div class="value">${pending}</div></div><div class="kpi card"><div class="label">Ordered</div><div class="value">${ordered}</div></div><div class="kpi card"><div class="label">Received</div><div class="value">${received}</div></div><div class="kpi card"><div class="label">Staff</div><div class="value">${d.staff.length}</div></div></div><div class="grid grid-2" style="margin-top:16px"><div class="card"><h3>Recent Orders</h3>${historyTable(d.orders.slice(0,8),["Order Date","Item Name","Quantity","Supplier","Status","Logged By"])}</div><div class="card"><h3>Recent Wastage</h3>${historyTable(d.wastage.slice(0,8),["Date","Item Name","Quantity","Reason","Status"])}</div></div>`}

  function adminOrdersView(){return `<div class="card"><div class="toolbar"><input id="aSearch" class="input" placeholder="Search item, supplier, staff..."><select id="aStatus"><option value="">All statuses</option><option>Pending</option><option>Ordered</option><option>Received</option></select><input id="aSupplier" class="input" placeholder="Supplier"><input id="aDate" class="input" type="date"><button class="btn" id="bulkOrdered">Bulk → Ordered</button><button class="btn" id="bulkReceived">Bulk → Received</button></div><div class="table-wrap"><table><thead><tr><th><input id="selectAll" type="checkbox"></th><th>Date</th><th>Item</th><th>Qty</th><th>Supplier</th><th>Remarks</th><th>Staff</th><th>Status</th></tr></thead><tbody id="ordersBody"></tbody></table></div></div>`}
  function setupAdminOrders(){const renderRows=()=>{const q=(document.getElementById("aSearch").value||"").toLowerCase(),st=document.getElementById("aStatus").value,sup=(document.getElementById("aSupplier").value||"").toLowerCase(),dt=document.getElementById("aDate").value;const rows=state.data.orders.filter(r=>(!q||Object.values(r).join(" ").toLowerCase().includes(q))&&(!st||r.Status===st)&&(!sup||String(r.Supplier).toLowerCase().includes(sup))&&(!dt||r["Order Date"]===dt));document.getElementById("ordersBody").innerHTML=rows.map(r=>`<tr><td><input class="row-check" data-id="${esc(r["Row ID"])}" type="checkbox"></td><td>${esc(r["Order Date"])}</td><td><b>${esc(r["Item Name"])}</b></td><td>${esc(r.Quantity)} ${esc(r.Unit)}</td><td>${esc(r.Supplier)}</td><td><input class="input inline-note" data-id="${esc(r["Row ID"])}" value="${esc(r["Note/Remarks"])}"></td><td>${esc(r["Logged By"])}</td><td><select class="status-select" data-id="${esc(r["Row ID"])}"><option ${r.Status==="Pending"?"selected":""}>Pending</option><option ${r.Status==="Ordered"?"selected":""}>Ordered</option><option ${r.Status==="Received"?"selected":""}>Received</option></select></td></tr>`).join("")||`<tr><td colspan="8" class="empty">No orders found.</td></tr>`;document.querySelectorAll(".status-select").forEach(e=>e.onchange=()=>updateOrder(e.dataset.id,{Status:e.value}));document.querySelectorAll(".inline-note").forEach(e=>e.onchange=()=>updateOrder(e.dataset.id,{"Note/Remarks":e.value}));};const updateOrder=async(id,patch)=>{try{await api("updateOrder",{id,patch});const r=state.data.orders.find(x=>x["Row ID"]==id);if(r)Object.assign(r,patch);toast("Saved.");renderRows();}catch(e){toast(e.message)}};window._goyaUpdateOrder=updateOrder;["aSearch","aStatus","aSupplier","aDate"].forEach(id=>document.getElementById(id).oninput=renderRows);document.getElementById("selectAll").onchange=e=>document.querySelectorAll(".row-check").forEach(x=>x.checked=e.target.checked);async function bulk(status){const ids=[...document.querySelectorAll(".row-check:checked")].map(x=>x.dataset.id);if(!ids.length){toast("Select orders first.");return;}for(const id of ids)await updateOrder(id,{Status:status});}document.getElementById("bulkOrdered").onclick=()=>bulk("Ordered");document.getElementById("bulkReceived").onclick=()=>bulk("Received");renderRows();}

  function itemsView(){return `<div class="grid grid-2"><div class="card"><div class="page-head"><div><h3>Supplier Directory</h3><p class="note">Name and WhatsApp contact.</p></div><button class="btn primary" id="addSupplier">Add Supplier</button></div>${historyTable(state.data.suppliers,["Name","Phone"])}</div><div class="card"><div class="page-head"><div><h3>Master Items Catalog</h3><p class="note">Catalog fields used by ordering, production and counts.</p></div><button class="btn primary" id="addItem">Add Item</button></div>${historyTable(state.data.master_items,["Name","SKU","Storage Unit","Ingredient Unit","Supplier","Items Type"])}</div></div>`}
  function setupItems(){document.getElementById("addSupplier").onclick=()=>modal("Add Supplier",`<div class="field"><label>Name</label><input id="mName" class="input"></div><div class="field" style="margin-top:10px"><label>WhatsApp Phone</label><input id="mPhone" class="input"></div>`,`<button class="btn primary" id="mSave">Save</button>`,"supplier");document.getElementById("addItem").onclick=()=>modal("Add Master Item",`<div class="form-grid"><div class="field"><label>Name</label><input id="iName" class="input"></div><div class="field"><label>SKU</label><input id="iSku" class="input"></div><div class="field"><label>Storage Unit</label><input id="iStorage" class="input" value="pcs"></div><div class="field"><label>Ingredient Unit</label><input id="iIngredient" class="input" value="pcs"></div><div class="field"><label>Supplier</label><select id="iSupplier">${state.data.suppliers.map(s=>`<option>${esc(s.Name)}</option>`).join("")}</select></div><div class="field"><label>Items Type</label><select id="iType"><option>Kitchen</option><option>Pastry</option><option>Bar</option><option>Packaging</option><option>Internal</option></select></div></div>`,`<button class="btn primary" id="mSave">Save</button>`,"item");}
  function staffView(){return `<div class="card"><div class="page-head"><div><h3>Staff Directory</h3><p class="note">PINs and comma-separated section permissions.</p></div><button class="btn primary" id="addStaff">Add Staff</button></div>${historyTable(state.data.staff,[ "PIN Code","Staff Full Name","Allowed Sections"])}</div>`}
  function setupStaff(){document.getElementById("addStaff").onclick=()=>modal("Add Staff",`<div class="form-grid"><div class="field"><label>Full Name</label><input id="sName" class="input"></div><div class="field"><label>4-digit PIN</label><input id="sPin" class="input" maxlength="4"></div></div><div class="field" style="margin-top:10px"><label>Allowed Sections</label><input id="sSections" class="input" placeholder="kitchen,bar"></div>`,`<button class="btn primary" id="mSave">Save</button>`,"staff");}
  function monitorView(){const p=state.data.production.map(x=>({...x,__type:"Production",__id:x.Timestamp})),w=state.data.wastage.map(x=>({...x,__type:"Wastage",__id:x.Timestamp}));const all=[...p,...w].sort((a,b)=>String(b.Timestamp).localeCompare(String(a.Timestamp)));return `<div class="card"><div class="toolbar"><input id="mSearch" class="input" placeholder="Search..."><select id="mType"><option value="">All</option><option>Production</option><option>Wastage</option></select></div><div id="monitorRows"></div></div>`}
  function setupMonitor(){const render=()=>{const q=(document.getElementById("mSearch").value||"").toLowerCase(),t=document.getElementById("mType").value;const p=state.data.production.map(x=>({...x,__type:"Production",__id:x.Timestamp})),w=state.data.wastage.map(x=>({...x,__type:"Wastage",__id:x.Timestamp}));const rows=[...p,...w].filter(x=>(!q||Object.values(x).join(" ").toLowerCase().includes(q))&&(!t||x.__type===t));document.getElementById("monitorRows").innerHTML=historyTable(rows.map(x=>({...x,"Type":x.__type})),["Timestamp","Type","Item Name","Quantity","Unit","Reason","Logged By","Status"]).replace(/<td>(Logged|Reviewed|Flagged)<\/td>/g,(_,s)=>`<td>${badge(s)}</td>`);};document.getElementById("mSearch").oninput=render;document.getElementById("mType").onchange=render;render();}
  function countsAdminView(){return `<div class="grid grid-2"><div class="card"><h3>Module Switcher</h3><p class="note">Activate or deactivate Inventory Count on the staff portal.</p><label class="switch"><input id="countToggle" type="checkbox" ${String(state.data.settings.InventoryCountEnabled).toUpperCase()==="TRUE"?"checked":""}><span class="slider"></span></label></div><div class="card"><h3>Audit History</h3>${historyTable(state.data.inventory_counts.slice(-50).reverse(),["Count Date / Month","Section","Item Name","SKU","Storage Quantity","Ingredient Quantity","Submitted By"])}</div></div>`}
  function setupCountsAdmin(){document.getElementById("countToggle").onchange=async e=>{try{await api("saveSettings",{settings:{InventoryCountEnabled:e.target.checked?"TRUE":"FALSE"}});state.data.settings.InventoryCountEnabled=e.target.checked?"TRUE":"FALSE";toast("Inventory Count setting saved.");}catch(err){toast(err.message)}}}
  function exportView(){return `<div class="grid grid-2">${["Orders","Production","Wastage","Master Items","Staff","Inventory Counts"].map(x=>`<div class="card"><h3>${x}</h3><p class="note">Download a CSV snapshot for ${x}.</p><button class="btn primary export-btn" data-export="${esc(x)}">Download CSV</button></div>`).join("")}</div><div class="card" style="margin-top:16px"><h3>Foodics CSV</h3><p class="note">Operational exports use the same source records and can be adapted to your exact Foodics import template.</p><div class="toolbar"><button class="btn primary export-btn" data-export="purchase_order.csv">purchase_order.csv</button><button class="btn primary export-btn" data-export="production.csv">production.csv</button><button class="btn primary export-btn" data-export="wastage.csv">wastage.csv</button><button class="btn primary export-btn" data-export="inventory_count.csv">inventory_count.csv</button></div></div>`}
  function setupExport(){document.querySelectorAll(".export-btn").forEach(b=>b.onclick=()=>{const name=b.dataset.export;let rows=[];if(name==="Orders"||name==="purchase_order.csv")rows=state.data.orders;if(name==="Production"||name==="production.csv")rows=state.data.production;if(name==="Wastage"||name==="wastage.csv")rows=state.data.wastage;if(name==="Master Items")rows=state.data.master_items;if(name==="Staff")rows=state.data.staff;if(name==="Inventory Counts"||name==="inventory_count.csv")rows=state.data.inventory_counts;downloadCsv(name.endsWith(".csv")?name:name.toLowerCase().replaceAll(" ","_")+".csv",rows);});}
  function settingsView(){return `<div class="card"><div class="form-grid"><div class="field"><label>Google Apps Script Web App URL</label><input id="setUrl" class="input" value="${esc(state.apiUrl)}" placeholder="https://script.google.com/macros/s/.../exec"></div><div class="field"><label>Owner Email</label><input id="setEmail" class="input" value="${esc(state.data.settings.OwnerEmail||"")}"></div><div class="field"><label>Admin Master PIN</label><input id="setPin" class="input" maxlength="4" value="${esc(state.data.settings.MasterPin||C.DEFAULT_ADMIN_PIN||"9988")}"></div></div><button class="btn primary" id="saveSettings" style="margin-top:14px">Save Settings</button><p class="note" style="margin-top:14px">For GitHub Pages, the Apps Script backend is deployed separately. This frontend supports JSONP-style requests to avoid common browser CORS/redirect issues.</p></div>`}
  function setupSettings(){document.getElementById("saveSettings").onclick=async()=>{const url=document.getElementById("setUrl").value.trim(),email=document.getElementById("setEmail").value.trim(),pin=document.getElementById("setPin").value.trim();try{if(url){state.apiUrl=url;localStorage.setItem("goya_api_url",url);}await api("saveSettings",{settings:{OwnerEmail:email,MasterPin:pin,InventoryCountEnabled:state.data.settings.InventoryCountEnabled}});state.data.settings.OwnerEmail=email;state.data.settings.MasterPin=pin;toast("Settings saved.");}catch(e){toast(e.message)}}}
  function modal(title,body,footer,type){document.getElementById("modal-root").innerHTML=`<div class="modal-backdrop"><div class="modal"><h2>${esc(title)}</h2>${body}<div style="display:flex;justify-content:flex-end;gap:8px;margin-top:18px"><button class="btn" id="mClose">Cancel</button>${footer}</div></div></div>`;document.getElementById("mClose").onclick=()=>document.getElementById("modal-root").innerHTML="";document.getElementById("mSave").onclick=async()=>{try{if(type==="supplier")await api("saveSupplier",{supplier:{Name:document.getElementById("mName").value,Phone:document.getElementById("mPhone").value}});if(type==="staff")await api("saveStaff",{staff:{"PIN Code":document.getElementById("sPin").value,"Staff Full Name":document.getElementById("sName").value,"Allowed Sections":document.getElementById("sSections").value}});if(type==="item")await api("saveItem",{item:{Name:document.getElementById("iName").value,SKU:document.getElementById("iSku").value,"Storage Unit":document.getElementById("iStorage").value,"Ingredient Unit":document.getElementById("iIngredient").value,Supplier:document.getElementById("iSupplier").value,"Items Type":document.getElementById("iType").value}});document.getElementById("modal-root").innerHTML="";await loadData();render();toast("Saved.");}catch(e){toast(e.message)}}}
  function downloadCsv(filename,rows){if(!rows.length){toast("No data to export.");return;}const headers=[...new Set(rows.flatMap(r=>Object.keys(r).filter(k=>!k.startsWith("__"))))];const csv=[headers.join(","),...rows.map(r=>headers.map(h=>`"${String(r[h]??"").replaceAll('"','""')}"`).join(","))].join("\n");const a=document.createElement("a");a.href=URL.createObjectURL(new Blob([csv],{type:"text/csv"}));a.download=filename;a.click();URL.revokeObjectURL(a.href);}
  const savedUrl=localStorage.getItem("goya_api_url"); if(savedUrl) state.apiUrl=savedUrl;
  render();
})();
