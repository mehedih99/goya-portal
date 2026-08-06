const SECTIONS = ['kitchen','pastry','bar','packaging'];
const SECTION_LABEL = { kitchen:'Kitchen', pastry:'Pastry', bar:'Bar', packaging:'Packaging' };
const STATUSES = ["PENDING","ORDERED","RECEIVED","NOT_RECEIVED","REJECTED"];
const WASTE_REASONS = ["Expired","Spillage / Damaged","Over-prepared","Staff Mistake"];

function escHtml(s){ return (s===undefined||s===null) ? "" : String(s).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c])); }
function todayISO(){ return new Date().toISOString().slice(0,10); }
function monthLabel(d){ d = d || new Date(); return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0'); }
function fmtDate(iso){ if(!iso) return '—'; const d=new Date(iso); if(isNaN(d)) return String(iso); return d.toLocaleDateString('en-GB',{day:'2-digit',month:'short',year:'numeric'}); }
function fmtDateTime(iso){ if(!iso) return '—'; const d=new Date(iso); if(isNaN(d)) return String(iso); return d.toLocaleDateString('en-GB',{day:'2-digit',month:'short'})+' · '+d.toLocaleTimeString('en-GB',{hour:'2-digit',minute:'2-digit'}); }
function parseSections(str){ return (str||'').split(',').map(s=>s.trim().toLowerCase()).filter(Boolean); }

async function getLocalSetting(key){ try{ return localStorage.getItem(key); }catch(e){ return null; } }
async function setLocalSetting(key,val){ try{ localStorage.setItem(key,val); }catch(e){} }

let SHEET_URL = "";
async function initBackend(){ SHEET_URL = (await getLocalSetting('goya-sheet-url')) || ""; }
async function connectSheet(url){ SHEET_URL = url.trim(); await setLocalSetting('goya-sheet-url', SHEET_URL); }
function isSheetConnected(){ return !!SHEET_URL; }

async function sheetPost(action, payload){
  if(!SHEET_URL) return;
  const body = Object.assign({action}, payload);
  fetch(SHEET_URL, { method:'POST', headers:{'Content-Type':'text/plain;charset=utf-8'}, body: JSON.stringify(body) }).catch(e => console.error(e));
}

let LOCAL_DB = null;
async function loadLocalDB(){
  try{ const raw = localStorage.getItem('goya-local-db'); if(raw){ LOCAL_DB = JSON.parse(raw); return; } }catch(e){}
  LOCAL_DB = { items:[], staff:[], orders:[], production:[], wastage:[], inventoryCounts:[], inventoryDrafts:[], suppliers:[], settings:{ MasterPin:'9988', ConnectionPin:'9988', InventoryCountEnabled:'true' } };
  await saveLocalDB();
}
async function saveLocalDB(){ try{ localStorage.setItem('goya-local-db', JSON.stringify(LOCAL_DB)); }catch(e){} }

const api = {
  async getAll(){
    if(SHEET_URL){
      try { const res = await fetch(SHEET_URL + '?action=getAll'); const data = await res.json(); LOCAL_DB = data; await saveLocalDB(); return data; } 
      catch(e) { if(!LOCAL_DB) await loadLocalDB(); return LOCAL_DB; }
    }
    if(!LOCAL_DB) await loadLocalDB(); return LOCAL_DB;
  },
  async addOrders(rows){
    if(LOCAL_DB) LOCAL_DB.orders.unshift(...rows.slice().reverse());
    if(SHEET_URL) sheetPost('addOrders',{rows}); else await saveLocalDB();
  },
  async updateOrderStatus(timestamp,status,receivedDate){
    if(LOCAL_DB) { const o = LOCAL_DB.orders.find(o=>o['Timestamp']===timestamp); if(o){ o['Status']=status; o['Received Date']=receivedDate||''; } }
    if(SHEET_URL) sheetPost('updateOrderStatus',{timestamp,status,receivedDate}); else await saveLocalDB();
  },
  async bulkUpdateOrderStatus(timestamps,status){
    if(LOCAL_DB) LOCAL_DB.orders.forEach(o=>{ if(timestamps.includes(o['Timestamp'])) o['Status']=status; });
    if(SHEET_URL) sheetPost('bulkUpdateOrderStatus',{timestamps,status}); else await saveLocalDB();
  },
  async addProduction(rows){
    if(LOCAL_DB) LOCAL_DB.production.unshift(...rows.slice().reverse());
    if(SHEET_URL) sheetPost('addProduction',{rows}); else await saveLocalDB();
  },
  async addWastage(rows){
    if(LOCAL_DB) LOCAL_DB.wastage.unshift(...rows.slice().reverse());
    if(SHEET_URL) sheetPost('addWastage',{rows}); else await saveLocalDB();
  },
  async updateLogStatus(sheet,timestamp,status){
    if(LOCAL_DB) { const arr = sheet==='Production' ? LOCAL_DB.production : LOCAL_DB.wastage; const o = arr.find(o=>o['Timestamp']===timestamp); if(o) o['Status']=status; }
    if(SHEET_URL) sheetPost('updateLogStatus',{sheet,timestamp,status}); else await saveLocalDB();
  },
  async upsertItem(item){
    if(SHEET_URL) sheetPost('upsertItem',{item});
    await saveLocalDB(); return item.rowId || '1';
  },
  async deleteItem(rowId){
    if(LOCAL_DB) LOCAL_DB.items = LOCAL_DB.items.filter(i=>i['Row ID']!==rowId);
    if(SHEET_URL) sheetPost('deleteItem',{rowId}); else await saveLocalDB();
  },
  async upsertStaff(staff, oldPin){
    if(SHEET_URL) sheetPost('upsertStaff',{staff,oldPin}); else await saveLocalDB();
  },
  async deleteStaff(pin){
    if(SHEET_URL) sheetPost('deleteStaff',{pin}); else await saveLocalDB();
  },
  async upsertSupplier(supplier, oldName){
    if(SHEET_URL) sheetPost('upsertSupplier',{supplier,oldName}); else await saveLocalDB();
  },
  async deleteSupplier(name){
    if(SHEET_URL) sheetPost('deleteSupplier',{name}); else await saveLocalDB();
  },
  async addInventoryCounts(rows){
    if(LOCAL_DB) LOCAL_DB.inventoryCounts.unshift(...rows.slice().reverse());
    if(SHEET_URL) sheetPost('addInventoryCounts',{rows}); else await saveLocalDB();
  },
  async saveDraft(pin, month, section, data){
    if(SHEET_URL) sheetPost('saveDraft',{draft:{pin,month,section,data}}); else await saveLocalDB();
  },
  async deleteDraft(pin, month, section){
    if(SHEET_URL) sheetPost('deleteDraft',{pin,month,section}); else await saveLocalDB();
  },
  async setSetting(key,value){
    if(LOCAL_DB) LOCAL_DB.settings[key]=value;
    if(SHEET_URL) sheetPost('setSetting',{key,value}); else await saveLocalDB();
  }
};

function waLink(text){ return `https://api.whatsapp.com/send?text=${encodeURIComponent(text)}`; }

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

async function copyToClipboard(text){ try{ await navigator.clipboard.writeText(text); return true; }catch(e){ return false; } }

let toastTimer=null;
function showToast(msg){
  let el=document.getElementById('toast'); if(el) el.remove();
  el=document.createElement('div'); el.id='toast'; el.className='toast'; el.textContent=msg; document.body.appendChild(el);
  clearTimeout(toastTimer); toastTimer=setTimeout(()=>{ el.remove(); },2600);
}

let _pinState = null;
function openPinPad(title, onSubmit, onCancel){ _pinState = { title, buffer:'', onSubmit, onCancel }; renderPinPad(); }
function closePinPad(){ const el = document.getElementById('pin-modal-holder'); if(el) el.remove(); _pinState = null; }
function pinPadPress(d){
  if(!_pinState || _pinState.buffer.length>=4) return;
  _pinState.buffer += d; renderPinPad();
  if(_pinState.buffer.length===4) setTimeout(pinPadSubmit,150);
}
function pinPadBackspace(){ if(_pinState){ _pinState.buffer = _pinState.buffer.slice(0,-1); renderPinPad(); } }
async function pinPadSubmit(){
  if(!_pinState) return;
  const ok = await _pinState.onSubmit(_pinState.buffer);
  if(ok){ closePinPad(); } else if(_pinState){ _pinState.buffer=''; renderPinPad(); showToast('Incorrect PIN'); }
}
function renderPinPad(){
  let el = document.getElementById('pin-modal-holder');
  if(!el){ el = document.createElement('div'); el.id='pin-modal-holder'; document.body.appendChild(el); }
  if(!_pinState){ el.remove(); return; }
  const dots = [0,1,2,3].map(i=>`<div class="pin-dot ${i<_pinState.buffer.length?'filled':''}"></div>`).join('');
  const keys = [1,2,3,4,5,6,7,8,9];
  const keyBtns = keys.map(k=>`<button onclick="pinPadPress('${k}')">${k}</button>`).join('') + `<button onclick="${_pinState.onCancel?'_pinState.onCancel();':''}closePinPad()" style="color:var(--rust);font-size:13px;">Cancel</button>` + `<button onclick="pinPadPress('0')">0</button><button onclick="pinPadBackspace()">⌫</button>`;
  el.className='overlay';
  el.innerHTML = `<div class="modal"><h3>${escHtml(_pinState.title)}</h3><div class="pin-dots">${dots}</div><div class="keypad">${keyBtns}</div></div>`;
}
