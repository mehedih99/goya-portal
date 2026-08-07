/* ============================================================
   GOYA PORTAL v3 FINAL — goya-common.js
   Shared module for staff.html & admin.html
   Core: API, helpers, PIN keypad, toast, email
   ============================================================ */

const OWNER_EMAIL = 'mehedi.src@gmail.com';
const WASTE_REASONS = ['Expired','Spillage','Damaged','Over-prepared','Staff Mistake'];
const STATUSES = ['PENDING','ORDERED','RECEIVED','NOT_RECEIVED','REJECTED'];
const STATUS_LABEL = {PENDING:'Pending',ORDERED:'Ordered',RECEIVED:'Received',NOT_RECEIVED:'Not Received',REJECTED:'Rejected'};
const SECTIONS = ['kitchen','pastry','bar','packaging'];
const SECTION_LABEL = {kitchen:'Kitchen',pastry:'Pastry',bar:'Bar',packaging:'Packaging'};

let SHEET_URL = '';
let LOCAL_DB = null;

/* ================= INITIALIZATION ================= */
async function initBackend(){
  SHEET_URL = await getLocalSetting('goya-sheet-url');
}

async function connectSheet(url){
  if(url){
    await setLocalSetting('goya-sheet-url', url);
    SHEET_URL = url;
  } else {
    await setLocalSetting('goya-sheet-url', '');
    SHEET_URL = '';
  }
}

async function disconnectSheet(){
  await setLocalSetting('goya-sheet-url', '');
  SHEET_URL = '';
}

function isSheetConnected(){ return SHEET_URL && SHEET_URL.trim().length > 0; }

async function getLocalSetting(key){ try{ return JSON.parse(localStorage.getItem(key)||'null'); }catch(e){ return null; } }
async function setLocalSetting(key, val){ localStorage.setItem(key, JSON.stringify(val)); }

/* ================= API LAYER ================= */
async function sheetPost(action, body){
  if(!SHEET_URL) throw new Error('Sheet not connected');
  const resp = await fetch(SHEET_URL, {method:'POST', body:JSON.stringify({action,...body})});
  if(!resp.ok) throw new Error('Sheet API failed: '+resp.status);
  return resp.json();
}

const api = {
  async getAll(){
    if(!SHEET_URL) return seedData();
    try{
      const resp = await fetch(SHEET_URL+'?action=getAll');
      if(!resp.ok) throw new Error(resp.status);
      return resp.json();
    }catch(e){ return seedData(); }
  },
  async addOrders(rows){
    if(SHEET_URL) await sheetPost('addOrders',{rows});
    else{ LOCAL_DB.orders.unshift(...rows.slice().reverse()); await saveLocalDB(); }
    // Send email to owner on order submit
    try{ await sendOrderEmail(rows); }catch(e){ console.warn('Email failed:', e); }
  },
  async updateOrderStatus(timestamp, status, receivedDate){
    if(SHEET_URL) await sheetPost('updateOrderStatus',{timestamp,status,receivedDate});
    else{ const o=LOCAL_DB.orders.find(x=>x['Timestamp']===timestamp); if(o){ o['Status']=status; o['Received Date']=receivedDate; } await saveLocalDB(); }
  },
  async bulkUpdateOrderStatus(timestamps, status){
    if(SHEET_URL) await sheetPost('bulkUpdateOrderStatus',{timestamps,status});
    else{ LOCAL_DB.orders.forEach(o=>{ if(timestamps.includes(o['Timestamp'])) o['Status']=status; }); await saveLocalDB(); }
  },
  async addProduction(rows){
    if(SHEET_URL) return sheetPost('addProduction',{rows});
    else{ LOCAL_DB.production.unshift(...rows.slice().reverse()); await saveLocalDB(); }
  },
  async addWastage(rows){
    if(SHEET_URL) return sheetPost('addWastage',{rows});
    else{ LOCAL_DB.wastage.unshift(...rows.slice().reverse()); await saveLocalDB(); }
  },
  async updateLogStatus(sheet, timestamp, status){
    if(SHEET_URL) await sheetPost('updateLogStatus',{sheet,timestamp,status});
    else{
      const arr = sheet==='Production' ? LOCAL_DB.production : LOCAL_DB.wastage;
      const row = arr.find(x=>x['Timestamp']===timestamp);
      if(row) row['Status']=status;
      await saveLocalDB();
    }
  },
  async upsertItem(item){
    if(SHEET_URL) return sheetPost('upsertItem',{item});
    else{
      const i = LOCAL_DB.items.find(x=>x['Row ID']===item.rowId);
      const row = {'Row ID':item.rowId,'Name':item.name,'SKU':item.sku||'','Storage Unit':item.storageUnit||'','Ingredient Unit':item.ingredientUnit||'','Supplier':item.supplier||'','Items Type':item.itemsType||'kitchen'};
      if(i) Object.assign(i,row); else LOCAL_DB.items.push(row);
      await saveLocalDB();
    }
  },
  async deleteItem(rowId){
    if(SHEET_URL) await sheetPost('deleteItem',{rowId});
    else{ LOCAL_DB.items = LOCAL_DB.items.filter(x=>x['Row ID']!==rowId); await saveLocalDB(); }
  },
  async upsertStaff(staff, oldPin){
    if(SHEET_URL) return sheetPost('upsertStaff',{staff,oldPin});
    else{
      const matchPin = oldPin || staff.pin;
      const s = LOCAL_DB.staff.find(x=>x['PIN Code']===matchPin);
      const row = {'PIN Code':staff.pin,'Staff Full Name':staff.name,'Allowed Sections':(staff.allowedSections||[]).join(',')};
      if(s) Object.assign(s,row); else LOCAL_DB.staff.push(row);
      await saveLocalDB();
    }
  },
  async deleteStaff(pin){
    if(SHEET_URL) await sheetPost('deleteStaff',{pin});
    else{ LOCAL_DB.staff = LOCAL_DB.staff.filter(x=>x['PIN Code']!==pin); await saveLocalDB(); }
  },
  async upsertSupplier(supplier, oldName){
    if(SHEET_URL) return sheetPost('upsertSupplier',{supplier,oldName});
    else{
      const matchName = oldName || supplier.name;
      const s = LOCAL_DB.suppliers.find(s=>s['Name']===matchName);
      const row = {'Name':supplier.name,'Phone':supplier.phone||'','Group Link':supplier.groupLink||''};
      if(s) Object.assign(s,row); else LOCAL_DB.suppliers.push(row);
      await saveLocalDB();
    }
  },
  async deleteSupplier(name){
    if(SHEET_URL) await sheetPost('deleteSupplier',{name});
    else{ LOCAL_DB.suppliers = LOCAL_DB.suppliers.filter(s=>s['Name']!==name); await saveLocalDB(); }
  },
  async addInventoryCounts(rows){
    if(SHEET_URL) return sheetPost('addInventoryCounts',{rows});
    else{ LOCAL_DB.inventoryCounts.unshift(...rows.slice().reverse()); await saveLocalDB(); }
  },
  async saveDraft(pin, month, section, data){
    if(SHEET_URL) return sheetPost('saveDraft',{draft:{pin,month,section,data}});
    else{
      const d = LOCAL_DB.inventoryDrafts.find(x=>x['PIN Code']===pin && x['Month']===month && x['Section']===section);
      const row = {'PIN Code':pin,'Month':month,'Section':section,'Data':JSON.stringify(data||{}),'Updated At':new Date().toISOString()};
      if(d) Object.assign(d,row); else LOCAL_DB.inventoryDrafts.push(row);
      await saveLocalDB();
    }
  },
  async deleteDraft(pin, month, section){
    if(SHEET_URL) await sheetPost('deleteDraft',{pin,month,section});
    else{ LOCAL_DB.inventoryDrafts = LOCAL_DB.inventoryDrafts.filter(x=>!(x['PIN Code']===pin && x['Month']===month && x['Section']===section)); await saveLocalDB(); }
  },
  async setSetting(key, value){
    if(SHEET_URL) return sheetPost('setSetting',{key,value});
    else{ LOCAL_DB.settings[key]=value; await saveLocalDB(); }
  }
};

/* ================= LOCAL STORAGE EMULATOR ================= */
function seedData(){
  return {
    items:[
      {'Row ID':'1','Name':'Ethiopian Green Beans','SKU':'BEAN-ETH-01','Storage Unit':'KG','Ingredient Unit':'GRAM','Supplier':'Sunrise Bean Co.','Items Type':'kitchen'},
      {'Row ID':'2','Name':'Colombian Green Beans','SKU':'BEAN-COL-01','Storage Unit':'KG','Ingredient Unit':'GRAM','Supplier':'Sunrise Bean Co.','Items Type':'kitchen'},
      {'Row ID':'3','Name':'Full Cream Milk','SKU':'MILK-FC-01','Storage Unit':'Liter','Ingredient Unit':'ML','Supplier':'Dairy Fresh Ltd.','Items Type':'bar'},
      {'Row ID':'4','Name':'Oat Milk','SKU':'MILK-OAT-01','Storage Unit':'Liter','Ingredient Unit':'ML','Supplier':'Dairy Fresh Ltd.','Items Type':'bar'},
      {'Row ID':'5','Name':'12oz Paper Cups','SKU':'CUP-12OZ-01','Storage Unit':'Box (1000pcs)','Ingredient Unit':'PCS','Supplier':'Pack & Print Supplies','Items Type':'packaging'},
      {'Row ID':'6','Name':'Cup Lids','SKU':'LID-CLEAR-01','Storage Unit':'Box (1000pcs)','Ingredient Unit':'PCS','Supplier':'Pack & Print Supplies','Items Type':'packaging'},
      {'Row ID':'7','Name':'House Cold Brew Batch','SKU':'PREP-CB-01','Storage Unit':'Liter','Ingredient Unit':'ML','Supplier':'','Items Type':'bar'},
      {'Row ID':'8','Name':'Vanilla Syrup Batch','SKU':'PREP-VS-01','Storage Unit':'Liter','Ingredient Unit':'ML','Supplier':'','Items Type':'pastry'},
      {'Row ID':'9','Name':'All-Purpose Flour','SKU':'FLOUR-AP-01','Storage Unit':'KG','Ingredient Unit':'GRAM','Supplier':'','Items Type':'pastry'},
      {'Row ID':'10','Name':'Chicken Breast','SKU':'MEAT-CHK-01','Storage Unit':'KG','Ingredient Unit':'GRAM','Supplier':'','Items Type':'kitchen'},
    ],
    staff:[
      {'PIN Code':'1111','Staff Full Name':'Aisha Rahman','Allowed Sections':'bar'},
      {'PIN Code':'2222','Staff Full Name':'Rahim Uddin','Allowed Sections':'kitchen,pastry'},
      {'PIN Code':'3333','Staff Full Name':'Karim Hossain','Allowed Sections':'packaging,bar'},
    ],
    orders:[], production:[], wastage:[], inventoryCounts:[], inventoryDrafts:[],
    suppliers:[
      {'Name':'Sunrise Bean Co.','Phone':'8801700000001','Group Link':''},
      {'Name':'Dairy Fresh Ltd.','Phone':'8801700000002','Group Link':''},
      {'Name':'Pack & Print Supplies','Phone':'','Group Link':''},
    ],
    settings:{ MasterPin:'9988', ConnectionPin:'9988', InventoryCountEnabled:'true', OwnerWhatsApp:'', OwnerEmail:OWNER_EMAIL }
  };
}

async function saveLocalDB(){
  if(LOCAL_DB) localStorage.setItem('goya-local-db', JSON.stringify(LOCAL_DB));
}

async function loadLocalDB(){
  try{
    LOCAL_DB = JSON.parse(localStorage.getItem('goya-local-db')||'null');
    if(!LOCAL_DB) LOCAL_DB = seedData();
  }catch(e){ LOCAL_DB = seedData(); }
}

/* ================= EMAIL HELPER ================= */
async function sendOrderEmail(rows){
  if(!rows || rows.length===0) return;
  const staffName = rows[0]['Logged By'] || 'Unknown';
  const bySupplier = {};
  rows.forEach(r=>{
    const sup = r['Supplier'] || 'Unspecified';
    (bySupplier[sup] = bySupplier[sup] || []).push(r);
  });
  let body = `NEW PURCHASE ORDER\n\n`;
  Object.keys(bySupplier).forEach(sup=>{
    body += `${sup}\n`;
    bySupplier[sup].forEach(r=>{ body += `• ${r['Item Name']} — ${r['Quantity']} ${r['Unit']}${r['Note/Remarks']?` (${r['Note/Remarks']})`:''}
`; });
    body += `\n`;
  });
  body += `Submitted by: ${staffName}\n${fmtDateTime(new Date().toISOString())}`;
  const subject = `New Purchase Order by ${staffName}`;
  const mailtoLink = `mailto:${OWNER_EMAIL}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  // Auto-trigger email by simulating click (or send via Apps Script if available)
  try{
    if(isSheetConnected()){
      await fetch(SHEET_URL, {method:'POST', body:JSON.stringify({action:'sendEmail',to:OWNER_EMAIL,subject,body})});
    }
  }catch(e){ console.warn('Auto-email failed, user can click mailto:', e); }
}

/* ================= WHATSAPP HELPERS ================= */
function waLink(phone, text){
  const encoded = encodeURIComponent(text);
  if(phone && phone.trim()) return `https://wa.me/${phone.replace(/[^0-9]/g,'')}?text=${encoded}`;
  return `https://api.whatsapp.com/send?text=${encoded}`;
}

function buildPurchaseOrderMessage(bySupplier, staffName){
  let msg = `*NEW PURCHASE ORDER*\n\n`;
  Object.keys(bySupplier).forEach(sup=>{
    msg += `*${sup}*\n`;
    bySupplier[sup].forEach(it=>{ msg += `• ${it.name} — ${it.qty} ${it.unit}${it.note? ' ('+it.note+')':''}\n`; });
    msg += `\n`;
  });
  msg += `Submitted by: ${staffName}\n${fmtDateTime(new Date().toISOString())}`;
  return msg;
}

async function copyToClipboard(text){
  try{ await navigator.clipboard.writeText(text); return true; }catch(e){ return false; }
}

/* ================= UI HELPERS ================= */
function escHtml(s){ return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#x27;'); }

function fmtDate(iso){ return iso? iso.slice(0,10) : ''; }
function fmtDateTime(iso){ return iso? iso.slice(0,16).replace('T',' ') : ''; }
function todayISO(){ return new Date().toISOString().slice(0,10); }
function monthLabel(){ return new Date().toISOString().slice(0,7); }
function inCurrentMonth(ts){ return (ts||'').slice(0,7) === monthLabel(); }
function parseSections(str){ return (str||'').split(',').map(s=>s.trim()).filter(Boolean); }

function showToast(msg){
  const t = document.createElement('div');
  t.style.cssText = 'position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:#222;color:#fff;padding:12px 20px;border-radius:6px;font-size:14px;z-index:9999;animation:slideUp .3s ease';
  t.textContent = msg;
  document.body.appendChild(t);
  setTimeout(()=>t.remove(), 3000);
}

function openPinPad(title, onSubmit){
  const holder = document.createElement('div');
  holder.className='overlay';
  holder.id='pin-keypad';
  let input = '';
  const pad = `<div class="pin-pad">
    <h3 style="text-align:center;margin-bottom:16px;">${escHtml(title)}</h3>
    <input type="password" id="pin-input" placeholder="••••" style="text-align:center;font-size:20px;letter-spacing:8px;width:140px;height:50px;border:2px solid var(--line);border-radius:8px;margin:0 auto 20px;display:block;">
    <div class="pin-grid">${[1,2,3,4,5,6,7,8,9,0].map(n=>`<button onclick="insertPin(${n})">${n}</button>`).join('')}
    <button onclick="deletePin()" style="grid-column:2;background:#e8d4c4;">⌫</button></div>
    <div class="row" style="margin-top:16px;gap:8px;">
      <button class="btn btn-ghost" onclick="closePinPad()">Cancel</button>
      <button class="btn btn-primary" onclick="submitPin()">OK</button>
    </div>
  </div>`;
  holder.innerHTML = `<div class="modal">${pad}</div>`;
  document.body.appendChild(holder);
  window.pinInput = () => document.getElementById('pin-input');
  window.insertPin = (n) => { input+= n; window.pinInput().value = '•'.repeat(input.length); };
  window.deletePin = () => { input = input.slice(0,-1); window.pinInput().value = '•'.repeat(input.length); };
  window.closePinPad = () => holder.remove();
  window.submitPin = async () => {
    if(await onSubmit(input)){
      holder.remove();
      showToast('Unlocked');
    } else {
      showToast('Wrong PIN');
      input = '';
      window.pinInput().value = '';
    }
  };
}

/* ================= CONSTANTS ================= */
const PIN_PAD_STYLE = `
.pin-pad { text-align:center; }
.pin-grid { display:grid; grid-template-columns:repeat(3,60px); gap:8px; justify-content:center; }
.pin-grid button { width:60px; height:60px; font-size:18px; font-weight:600; border:2px solid var(--line); background:#fff; border-radius:8px; cursor:pointer; }
.pin-grid button:hover { background:var(--parchment); }
.overlay { position:fixed; top:0; left:0; right:0; bottom:0; background:rgba(0,0,0,.5); display:flex; align-items:center; justify-content:center; z-index:9999; }
.modal { background:#fff; padding:32px; border-radius:12px; box-shadow:0 10px 40px rgba(0,0,0,.2); max-width:500px; width:90%; }
`;

await loadLocalDB();
