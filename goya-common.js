const SECTIONS = ['kitchen','pastry','bar','packaging'];
const SECTION_LABEL = { kitchen:'Kitchen', pastry:'Pastry', bar:'Bar', packaging:'Packaging' };
const STATUSES = ["PENDING","ORDERED","RECEIVED","NOT_RECEIVED","REJECTED"];
const STATUS_LABEL = {PENDING:"Pending",ORDERED:"Ordered",RECEIVED:"Received",NOT_RECEIVED:"Not received",REJECTED:"Rejected"};
const WASTE_REASONS = ["Expired","Spillage / Damaged","Over-prepared","Staff Mistake"];

function escHtml(s){ return (s===undefined||s===null) ? "" : String(s).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c])); }
function newId(){ return Date.now().toString(36)+Math.random().toString(36).slice(2,7); }
function todayISO(){ return new Date().toISOString().slice(0,10); }
function monthLabel(d){ d = d || new Date(); return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0'); }
function fmtDate(iso){ if(!iso) return '—'; const d=new Date(iso); if(isNaN(d)) return String(iso); return d.toLocaleDateString('en-GB',{day:'2-digit',month:'short',year:'numeric'}); }
function fmtDateTime(iso){ if(!iso) return '—'; const d=new Date(iso); if(isNaN(d)) return String(iso); return d.toLocaleDateString('en-GB',{day:'2-digit',month:'short'})+' · '+d.toLocaleTimeString('en-GB',{hour:'2-digit',minute:'2-digit'}); }
function inCurrentMonth(iso){ if(!iso) return false; const d=new Date(iso), now=new Date(); return d.getFullYear()===now.getFullYear() && d.getMonth()===now.getMonth(); }
function parseSections(str){ return (str||'').split(',').map(s=>s.trim().toLowerCase()).filter(Boolean); }

async function getLocalSetting(key){
  try{ if(window.storage){ const r = await window.storage.get(key,false); return r?r.value:null; } }catch(e){}
  try{ return localStorage.getItem(key); }catch(e){ return null; }
}
async function setLocalSetting(key,val){
  try{ if(window.storage){ await window.storage.set(key,val,false); return; } }catch(e){}
  try{ localStorage.setItem(key,val); }catch(e){}
}

let SHEET_URL = "";
async function initBackend(){
  SHEET_URL = (await getLocalSetting('goya-sheet-url')) || "";
}
async function connectSheet(url){ SHEET_URL = url.trim(); await setLocalSetting('goya-sheet-url', SHEET_URL); }
async function disconnectSheet(){ SHEET_URL = ""; await setLocalSetting('goya-sheet-url',""); }
function isSheetConnected(){ return !!SHEET_URL; }

async function sheetPost(action, payload){
  const body = Object.assign({action}, payload);
  fetch(SHEET_URL, {
    method:'POST',
    headers:{'Content-Type':'text/plain;charset=utf-8'},
    body: JSON.stringify(body)
  }).catch(e => console.error(e));
}

const LOCAL_DB_KEY = 'goya-local-db';
let LOCAL_DB = null;
async function loadLocalDB(){
  try{
    if(window.storage){
      const r = await window.storage.get(LOCAL_DB_KEY, true);
      if(r && r.value){ LOCAL_DB = JSON.parse(r.value); return; }
    } else {
      const raw = localStorage.getItem(LOCAL_DB_KEY);
      if(raw){ LOCAL_DB = JSON.parse(raw); return; }
    }
  }catch(e){}
  LOCAL_DB = seedLocalDB();
  await saveLocalDB();
}
async function saveLocalDB(){
  const raw = JSON.stringify(LOCAL_DB);
  try{ if(window.storage){ await window.storage.set(LOCAL_DB_KEY, raw, true); return; } }catch(e){}
  try{ localStorage.setItem(LOCAL_DB_KEY, raw); }catch(e){}
}
function seedLocalDB(){
  return {
    items:[
      {'Row ID':'1','Name':'Ethiopian Green Beans','SKU':'BEAN-ETH-01','Storage Unit':'KG','Ingredient Unit':'GRAM','Supplier':'Sunrise Bean Co.','Items Type':'kitchen'},
      {'Row ID':'2','Name':'Colombian Green Beans','SKU':'BEAN-COL-01','Storage Unit':'KG','Ingredient Unit':'GRAM','Supplier':'Sunrise Bean Co.','Items Type':'kitchen'},
      {'Row ID':'3','Name':'Full Cream Milk','SKU':'MILK-FC-01','Storage Unit':'Box (12x1L)','Ingredient Unit':'ML','Supplier':'Dairy Fresh Ltd.','Items Type':'bar'},
      {'Row ID':'4','Name':'Oat Milk','SKU':'MILK-OAT-01','Storage Unit':'Box (12x1L)','Ingredient Unit':'ML','Supplier':'Dairy Fresh Ltd.','Items Type':'bar'},
      {'Row ID':'5','Name':'12oz Paper Cups','SKU':'CUP-12OZ','Storage Unit':'Sleeve (50pcs)','Ingredient Unit':'PCS','Supplier':'Pack & Print Supplies','Items Type':'packaging'},
      {'Row ID':'6','Name':'Cup Lids','SKU':'LID-12OZ','Storage Unit':'Sleeve (50pcs)','Ingredient Unit':'PCS','Supplier':'Pack & Print Supplies','Items Type':'packaging'},
      {'Row ID':'7','Name':'House Cold Brew Batch','SKU':'PREP-CB-01','Storage Unit':'L','Ingredient Unit':'ML','Supplier':'','Items Type':'bar'},
      {'Row ID':'8','Name':'Vanilla Syrup Batch','SKU':'PREP-VS-01','Storage Unit':'L','Ingredient Unit':'ML','Supplier':'','Items Type':'pastry'},
    ],
    staff:[
      {'PIN Code':'1111','Staff Full Name':'Aisha Rahman','Allowed Sections':'bar'},
      {'PIN Code':'2222','Staff Full Name':'Rahim Uddin','Allowed Sections':'kitchen,pastry'},
    ],
    orders:[], production:[], wastage:[], inventoryCounts:[], inventoryDrafts:[],
    suppliers:[
      {'Name':'Sunrise Bean Co.','Phone':'','Group Link':''},
      {'Name':'Dairy Fresh Ltd.','Phone':'','Group Link':''},
    ],
    settings:{ MasterPin:'9988', ConnectionPin:'9988', InventoryCountEnabled:'true', OwnerEmail:'mehedi.src@gmail.com' }
  };
}

const api = {
  async getAll(){
    if(SHEET_URL){
      try {
        const res = await fetch(SHEET_URL + '?action=getAll');
        return await res.json();
      } catch(e) {
        if(!LOCAL_DB) await loadLocalDB();
        return LOCAL_DB;
      }
    }
    if(!LOCAL_DB) await loadLocalDB();
    return LOCAL_DB;
  },
  async addOrders(rows){
    if(LOCAL_DB) LOCAL_DB.orders.unshift(...rows.slice().reverse());
    if(SHEET_URL) sheetPost('addOrders',{rows});
    else await saveLocalDB();
  },
  async updateOrderStatus(timestamp,status,receivedDate){
    if(LOCAL_DB) {
      const o = LOCAL_DB.orders.find(o=>o['Timestamp']===timestamp);
      if(o){ o['Status']=status; o['Received Date']=receivedDate||''; }
    }
    if(SHEET_URL) sheetPost('updateOrderStatus',{timestamp,status,receivedDate});
    else await saveLocalDB();
  },
  async bulkUpdateOrderStatus(timestamps,status){
    if(LOCAL_DB) LOCAL_DB.orders.forEach(o=>{ if(timestamps.includes(o['Timestamp'])) o['Status']=status; });
    if(SHEET_URL) sheetPost('bulkUpdateOrderStatus',{timestamps,status});
    else await saveLocalDB();
  },
  async addProduction(rows){
    if(LOCAL_DB) LOCAL_DB.production.unshift(...rows.slice().reverse());
    if(SHEET_URL) sheetPost('addProduction',{rows});
    else await saveLocalDB();
  },
  async addWastage(rows){
    if(LOCAL_DB) LOCAL_DB.wastage.unshift(...rows.slice().reverse());
    if(SHEET_URL) sheetPost('addWastage',{rows});
    else await saveLocalDB();
  },
  async updateLogStatus(sheet,timestamp,status){
    if(LOCAL_DB) {
      const arr = sheet==='Production' ? LOCAL_DB.production : LOCAL_DB.wastage;
      const o = arr.find(o=>o['Timestamp']===timestamp);
      if(o) o['Status']=status;
    }
    if(SHEET_URL) sheetPost('updateLogStatus',{sheet,timestamp,status});
    else await saveLocalDB();
  },
  async upsertItem(item){
    if(SHEET_URL) return sheetPost('upsertItem',{item});
    await saveLocalDB();
    return item.rowId || '1';
  },
  async deleteItem(rowId){
    if(LOCAL_DB) LOCAL_DB.items = LOCAL_DB.items.filter(i=>i['Row ID']!==rowId);
    if(SHEET_URL) sheetPost('deleteItem',{rowId});
    else await saveLocalDB();
  },
  async upsertStaff(staff, oldPin){
    if(SHEET_URL) sheetPost('upsertStaff',{staff,oldPin});
    else await saveLocalDB();
  },
  async deleteStaff(pin){
    if(SHEET_URL) sheetPost('deleteStaff',{pin});
    else await saveLocalDB();
  },
  async upsertSupplier(supplier, oldName){
    if(SHEET_URL) sheetPost('upsertSupplier',{supplier,oldName});
    else await saveLocalDB();
  },
  async deleteSupplier(name){
    if(SHEET_URL) sheetPost('deleteSupplier',{name});
    else await saveLocalDB();
  },
  async addInventoryCounts(rows){
    if(LOCAL_DB) LOCAL_DB.inventoryCounts.unshift(...rows.slice().reverse());
    if(SHEET_URL) sheetPost('addInventoryCounts',{rows});
    else await saveLocalDB();
  },
  async saveDraft(pin, month, section, data){
    if(SHEET_URL) sheetPost('saveDraft',{draft:{pin,month,section,data}});
    else await saveLocalDB();
  },
  async deleteDraft(pin, month, section){
    if(SHEET_URL) sheetPost('deleteDraft',{pin,month,section});
    else await saveLocalDB();
  },
  async setSetting(key,value){
    if(LOCAL_DB) LOCAL_DB.settings[key]=value;
    if(SHEET_URL) sheetPost('setSetting',{key,value});
    else await saveLocalDB();
  }
};

function waLink(phone, text){
  const encoded = encodeURIComponent(text);
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

function buildSupplierOrderMessage(supplierName, items){
  let msg = `*Purchase Order — ${supplierName}*\n\n`;
  items.forEach(it=>{ msg += `• ${it.name} — ${it.qty} ${it.unit}${it.note? ' ('+it.note+')':''}\n`; });
  msg += `\n${fmtDateTime(new Date().toISOString())}`;
  return msg;
}

async function copyToClipboard(text){
  try{ await navigator.clipboard.writeText(text); return true; }catch(e){ return false; }
}

let toastTimer=null;
function showToast(msg){
  let el=document.getElementById('toast');
  if(el) el.remove();
  el=document.createElement('div');
  el.id='toast'; el.className='toast'; el.textContent=msg;
  document.body.appendChild(el);
  clearTimeout(toastTimer);
  toastTimer=setTimeout(()=>{ el.remove(); },2600);
}

let _pinState = null;
function openPinPad(title, onSubmit, onCancel){
  _pinState = { title, buffer:'', onSubmit, onCancel };
  renderPinPad();
}
function closePinPad(){
  const el = document.getElementById('pin-modal-holder');
  if(el) el.remove();
  _pinState = null;
}
function pinPadPress(d){
  if(!_pinState || _pinState.buffer.length>=4) return;
  _pinState.buffer += d;
  renderPinPad();
  if(_pinState.buffer.length===4) setTimeout(pinPadSubmit,150);
}
function pinPadBackspace(){ if(_pinState){ _pinState.buffer = _pinState.buffer.slice(0,-1); renderPinPad(); } }
async function pinPadSubmit(){
  if(!_pinState) return;
  const ok = await _pinState.onSubmit(_pinState.buffer);
  if(ok){ closePinPad(); }
  else if(_pinState){ _pinState.buffer=''; renderPinPad(); showToast('Incorrect PIN — try again'); }
}
function renderPinPad(){
  let el = document.getElementById('pin-modal-holder');
  if(!el){ el = document.createElement('div'); el.id='pin-modal-holder'; document.body.appendChild(el); }
  if(!_pinState){ el.remove(); return; }
  const dots = [0,1,2,3].map(i=>`<div class="pin-dot ${i<_pinState.buffer.length?'filled':''}"></div>`).join('');
  const keys = [1,2,3,4,5,6,7,8,9];
  const keyBtns = keys.map(k=>`<button onclick="pinPadPress('${k}')">${k}</button>`).join('')
    + `<button onclick="${_pinState.onCancel?'_pinState.onCancel();':''}closePinPad()" style="color:var(--rust);font-size:13px;">Cancel</button>`
    + `<button onclick="pinPadPress('0')">0</button>`
    + `<button onclick="pinPadBackspace()">⌫</button>`;
  el.className='overlay';
  el.innerHTML = `<div class="modal">
    <h3>${escHtml(_pinState.title)}</h3>
    <div class="pin-dots">${dots}</div>
    <div class="keypad">${keyBtns}</div>
  </div>`;
}