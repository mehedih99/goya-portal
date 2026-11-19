(() => {
 'use strict';
 const $=id=>document.getElementById(id),esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const context=()=>window.GoyaAdmin?._context?.()||window.GoyaAttendance?._liveContext?.()||window.GoyaStaff?._liveContext?.();
 let db,directory=[],generation=0;
 async function rpc(name,args={}) {
  const token=context()?.token;if(!token)throw Error('Sign in again.');
  db ||= supabase.createClient(GOYA_CONFIG.SUPABASE_URL,GOYA_CONFIG.SUPABASE_ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data,error}=await db.rpc(name,{p_token:token,...args});
  if(context()?.token!==token)throw Error('Session changed. Reopen this page.');if(error)throw Error(error.message);return data;
 }
 function modal(title,body,save,label='Save') {
  const node=document.createElement('dialog');node.className='card management-dialog';
  node.innerHTML='<form><h2>'+esc(title)+'</h2>'+body+'<p role="status"></p><div class="toolbar"><button class="btn" type="submit">'+esc(label)+'</button><button class="btn secondary" type="button" data-cancel>Cancel</button></div></form>';
  document.body.append(node);node.querySelector('[data-cancel]').onclick=()=>node.close();node.onclose=()=>node.remove();
  let busy=false;node.addEventListener('cancel',e=>{if(busy)e.preventDefault();});
  node.querySelector('form').onsubmit=async e=>{e.preventDefault();if(busy)return;const form=e.currentTarget,input=Object.fromEntries(new FormData(form));busy=true;
   const controls=[...form.elements].filter(el=>!el.disabled);controls.forEach(el=>el.disabled=true);
   try{await save(input,node);node.close();}catch(error){node.querySelector('[role=status]').textContent=error.message;}
   finally{busy=false;controls.forEach(el=>el.disabled=false);}};
  node.showModal();return node;
 }
 const identity=()=>'<label>Management name<input name="actor" maxlength="100" required autocomplete="name"></label><p class="small muted">Recorded with this admin session. Shared PIN access does not verify an individual identity.</p>';
 function dropZone(input) {
  if(!input||input.closest('.management-drop'))return;
  const zone=document.createElement('div');zone.className='management-drop';input.before(zone);
  const text=document.createElement('span');text.textContent='⇧ Drag & drop a PDF, JPG or PNG here, or choose a file';zone.append(text,input);
  const feedback=document.createElement('small');zone.append(feedback);
  const refresh=()=>{feedback.textContent=input.files?.[0]?.name||'Up to 5 MB · Uploaded files stay in Google Drive';};input.addEventListener('change',refresh);refresh();
  for(const event of ['dragenter','dragover'])zone.addEventListener(event,e=>{if(input.disabled)return;e.preventDefault();zone.classList.add('drag-over');});
  zone.addEventListener('dragleave',()=>zone.classList.remove('drag-over'));
  zone.addEventListener('drop',e=>{e.preventDefault();zone.classList.remove('drag-over');if(input.disabled)return;
   const files=[...e.dataTransfer.files];if(files.length!==1||!['application/pdf','image/jpeg','image/png'].includes(files[0].type)||files[0].size>5000000||!files[0].size){feedback.textContent='Choose one PDF, JPG or PNG up to 5 MB.';return;}
   const transfer=new DataTransfer();transfer.items.add(files[0]);input.files=transfer.files;input.dispatchEvent(new Event('change',{bubbles:true}));input.dispatchEvent(new Event('input',{bubbles:true}));});
 }
 function editBalance(member,refresh) {
  const row=member.off_balance||{balance:0,revision:0};
  modal('Off Balance · '+member.name,'<p>Positive = pending off. Negative = advance off taken. This balance also appears in My Journey.</p><label>Balance<input name="balance" type="number" step="1" min="-36500" max="36500" value="'+esc(row.balance)+'" required></label>'+identity()+'<label>Reason<textarea name="reason" required maxlength="2000"></textarea></label>',async input=>{
   await rpc('goya_management_save_balance',{p_staff:member.id,p_value:Number(input.balance),p_expected:row.revision,p_reason:input.reason,p_actor:input.actor});await refresh();
  });
 }
 async function resign(member,refresh=()=>window.GoyaAdmin?.refreshStaff()) {
  const plan=member.resignation;
  const node=modal('Resignation · '+member.name,'<p>Access closes after the last working day ends (UAE time). Past records and documents remain available.</p><label>Last Working Day<input name="day" type="date" required value="'+esc(plan?.last_working_day||member.profile?.last_day||'')+'" min="'+esc(member.profile?.joining_date||'')+'"></label>'+identity()+'<label>Private resignation notes<textarea name="note" maxlength="4000">'+esc(plan?.note||'')+'</textarea></label><div class="management-resign-check small" role="status">Checking pending requests and future roster…</div><label><input name="confirmed" type="checkbox" required> I have checked the last working day. Existing roster entries will be retained.</label>',async input=>{
   await rpc('goya_management_resignation',{p_staff:member.id,p_day:input.day,p_actor:input.actor,p_note:input.note,p_expected:plan?.updated_at||null});await refresh();
  },'Confirm resignation');
  try {
   const [report,requests]=await Promise.all([rpc('goya_management_report',{p_staff:member.id}),rpc('goya_management_requests',{p_month:null})]);
   if(!node.isConnected)return;
   const field=node.querySelector('[name=day]'),box=node.querySelector('.management-resign-check');
   const update=()=>{
    const latest=new Map();for(const row of report.rosters||[])if(!latest.has(row.week))latest.set(row.week,row);
    const shifts=[];for(const row of latest.values())(row.days||[]).forEach((day,i)=>{const d=new Date(row.week+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+i);const date=d.toISOString().slice(0,10);if(date>field.value&&day?.kind==='Shift')shifts.push(date);});
    const pending=requests.filter(r=>r.staff_id===member.id&&r.state==='Pending').length;
    box.textContent=field.value?'Last working day: '+field.value+' · '+shifts.length+' later published duty entries · '+pending+' pending requests. Review these separately; nothing is deleted.':'Choose the last working day to check future duty entries.';
   };field.addEventListener('input',update);update();
  }catch(e){if(node.isConnected)node.querySelector('.management-resign-check').textContent='Could not check future roster: '+e.message;}
 }
 function cancelResignation(member,refresh) {
  modal('Cancel scheduled resignation',identity()+'<label>Reason<textarea name="note" maxlength="2000" required></textarea></label>',async input=>{
   await rpc('goya_management_cancel_resignation',{p_staff:member.id,p_expected:member.resignation.updated_at,p_actor:input.actor,p_note:input.note});await refresh();
  });
 }
 function fullProfile(id) {
  sessionStorage.setItem('goya-attendance-handoff',context().token);sessionStorage.setItem('goya-open-staff-profile',id);location.href='attendance.html';
 }
 async function renderDirectory(staff) {
  if(!$('staffDirectory'))return;
  const turn=++generation;directory=staff;renderDirectoryRows();
  try{const profiles=await rpc('goya_management_profiles');if(turn!==generation)return;
   directory=staff.map(s=>({...s,...profiles.find(p=>p.id===s.id)}));renderDirectoryRows();
  }catch(e){if(turn===generation)$('staffDirectoryStatus').textContent=e.message;}
 }
 function renderDirectoryRows() {
  const search=$('staffDirectorySearch')?.value.trim().toLowerCase()||'',filter=$('staffDirectoryFilter')?.value||'Active';
  const state=s=>s.profile?.last_day?'Resigned':s.active?'Active':'Inactive';
  const items=directory.filter(s=>(filter==='All'||state(s)===filter)&&[s.name,s.profile?.employee_code].join(' ').toLowerCase().includes(search));
  const box=$('staffDirectory');box.innerHTML=items.map((s,i)=>'<details class="hr-staff-card"><summary><strong>👤 '+esc(s.name)+'</strong><span>'+esc([s.profile?.employee_code,state(s)].filter(Boolean).join(' · '))+'</span></summary><div class="hr-staff-card-body"><p>'+esc([s.profile?.position,(s.sections||[]).join(', '),'GOYA'].filter(Boolean).join(' · '))+'</p><div class="toolbar"><button class="btn" data-edit="'+i+'">✎ Edit</button><button class="btn secondary" data-profile="'+i+'">View Full Profile →</button><button class="btn secondary" data-resign="'+i+'">'+(s.profile?.last_day?'Resignation details':s.resignation&&!s.resignation.cancelled_at?'Edit resignation':'Mark as Resigned')+'</button>'+(s.profile?.last_day?'<button class="btn secondary" data-rejoin="'+i+'">Rejoin</button>':'')+(s.resignation&&!s.resignation.cancelled_at&&!s.resignation.applied_at?'<button class="btn secondary" data-cancel-plan="'+i+'">Cancel scheduled resignation</button>':'')+'<button class="btn secondary" data-doc="'+i+'">＋ Resignation document</button><button class="btn danger" data-delete="'+i+'">Delete</button></div>'+(s.resignation&&!s.resignation.cancelled_at?'<p>Last working day: '+esc(s.resignation.last_working_day)+'</p>':'')+'<div data-documents><p role="status"></p><div class="hr-document-list"></div></div></div></details>').join('')||'<div class="card">No staff match this filter.</div>';
  const refresh=()=>window.GoyaAdmin.refreshStaff();
  box.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>window.GoyaAdmin.editStaff(items[b.dataset.edit].id));
  box.querySelectorAll('[data-profile]').forEach(b=>b.onclick=()=>fullProfile(items[b.dataset.profile].id));
  box.querySelectorAll('[data-resign]').forEach(b=>b.onclick=()=>resign(items[b.dataset.resign],refresh));
  box.querySelectorAll('[data-cancel-plan]').forEach(b=>b.onclick=()=>cancelResignation(items[b.dataset.cancelPlan],refresh));
  box.querySelectorAll('[data-rejoin]').forEach(b=>b.onclick=()=>GoyaHR.openRejoin(items[b.dataset.rejoin],refresh));
  box.querySelectorAll('[data-delete]').forEach(b=>b.onclick=()=>GoyaAdmin.deleteStaff(items[b.dataset.delete].id));
  box.querySelectorAll('[data-doc]').forEach(b=>b.onclick=()=>GoyaHR.documentEditor(b.closest('details').querySelector('[data-documents]'),items[b.dataset.doc].id,null,'Resignation Letter'));
 }
 function openNewStaff(){GoyaAdmin.resetStaffForm();$('staffEditor').hidden=false;$('staffName').focus();}
 async function renderRecordActivity(pane,member) {
  const feedback=pane.querySelector('[role=status]'),box=pane.querySelector('[data-record-activity-content]');
  feedback.textContent='Loading records…';
  try {
   const [report,requests]=await Promise.all([rpc('goya_management_report',{p_staff:member.id}),rpc('goya_management_requests',{p_month:null})]);
   if(!pane.isConnected)return;
   const table=(title,head,rows)=>'<h4>'+title+'</h4><div class="table-wrap"><table class="table"><thead><tr>'+head.map(v=>'<th>'+esc(v)+'</th>').join('')+'</tr></thead><tbody>'+rows.map(row=>'<tr>'+row.map(v=>'<td>'+esc(v)+'</td>').join('')+'</tr>').join('')+'</tbody></table></div>';
   box.innerHTML=table('Live attendance',['Date','Classification','Check In / Out','Note'],(report.attendance||[]).map(r=>[r.operational_date,r.classification,(r.sessions||[]).map(s=>s.check_in_at+' / '+(s.check_out_at||'On Duty')).join('; '),r.classification_note]))+
    table('Earlier attendance',['Date','Check In','Check Out'],(report.legacy_attendance||[]).map(r=>[r.operational_date,r.punch_in,r.punch_out]))+
    table('Leave & requests',['Type','Requested dates','Approved dates','Status'],requests.filter(r=>r.staff_id===member.id).map(r=>[r.kind,r.requested_from+' to '+r.requested_to,(r.approved_from||'—')+' to '+(r.approved_to||'—'),requestStatus(r)]))+
    table('Published roster history',['Week','Revision','Days'],(report.rosters||[]).map(r=>[r.week,r.revision,(r.days||[]).map((d,i)=>(i+1)+': '+(!d?'Not scheduled':d.kind==='Shift'?(d.segments||[]).map(s=>s.start+'–'+s.end).join(' / '):d.kind)).join(' · ')]));
   feedback.textContent='';
  }catch(e){if(pane.isConnected)feedback.textContent=e.message;}
 }
 function requestStatus(row){const today=new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Dubai'}).format(new Date());return row.state!=='Approved'?row.state:row.approved_to<today?'Done':row.kind!=='Resignation'&&row.approved_from<=today?'In progress':'Approved';}
 async function staffPDF(member) {
  if(!window.jspdf)throw Error('PDF library unavailable. Reload and try again.');
  const [report,requests]=await Promise.all([rpc('goya_management_report',{p_staff:member.id}),rpc('goya_management_requests',{p_month:null})]);
  const pdf=new jspdf.jsPDF(),clean=v=>String(v??'').replace(/[^\x20-\x7e\n]/g,' ');let y=20;
  const line=(text,size=10)=>{pdf.setFontSize(size);for(const row of pdf.splitTextToSize(clean(text),174)){if(y>278){pdf.addPage();y=18;}pdf.text(row,18,y);y+=size*0.48;}y+=3;};
  const table=(title,head,body)=>{if(!body.length)return;line(title,13);pdf.autoTable({startY:y,head:[head],body:body.map(r=>r.map(clean)),margin:{left:18,right:18},styles:{fontSize:8},theme:'striped'});y=pdf.lastAutoTable.finalY+9;};
  line('GOYA | Confidential Staff Record',17);line(member.name,14);line('Generated: '+new Date().toLocaleString('en-AE',{timeZone:'Asia/Dubai'})+' UAE');
  table('Employment',['Field','Details'],Object.entries(member.profile||{}).filter(([k])=>!['staff_id','updated_at'].includes(k)));
  line('Off Balance: '+(member.off_balance?.balance??'N/A'));if(member.resignation)line('Resignation: '+JSON.stringify(member.resignation));
  table('Leave and requests',['Type','Requested','Approved','State','Payroll'],requests.filter(r=>r.staff_id===member.id).map(r=>[r.kind,r.requested_from+' to '+r.requested_to,(r.approved_from||'')+' to '+(r.approved_to||''),requestStatus(r),r.kind==='Resignation'?'':r.payroll]));
  table('Management decision history',['When','By','Decision','Private note'],requests.filter(r=>r.staff_id===member.id).flatMap(r=>(r.management_history||[]).map(h=>[h.created_at,h.actor,h.after_data.state,h.note])));
  table('Live attendance',['Date','Classification','Sessions','Note'],(report.attendance||[]).map(r=>[r.operational_date,r.classification,(r.sessions||[]).map(s=>s.check_in_at+' / '+(s.check_out_at||'Open')).join('; '),r.classification_note]));
  table('Earlier attendance',['Date','In','Out','Note'],(report.legacy_attendance||[]).map(r=>[r.operational_date,r.punch_in,r.punch_out,r.note]));
  table('Published roster history',['Week','Revision','Days'],(report.rosters||[]).map(r=>[r.week,r.revision,JSON.stringify(r.days)]));
  table('Annual leave history',['Service year','From','To','Note'],(report.annual_history||[]).map(r=>[r.service_year,r.leave_from||'N/A',r.leave_to||'N/A',r.note]));
  table('Excel archive',['Week','Shifts','Pending off','Private remarks'],(report.archive||[]).map(r=>[r.source_week,JSON.stringify(r.shifts),r.pending_off,r.private_remarks]));
  table('Management activity',['When','Event','Details'],(member.history||[]).map(r=>[r.created_at,r.event,JSON.stringify(r.details)]));
  line('Documents (private Google Drive links)',13);line('Links require existing Google Drive permission. No public access has been added.');
  const files=[...(report.documents||[]),...requests.filter(r=>r.staff_id===member.id&&r.drive_file_id).map(r=>({title:r.kind+' attachment',file_name:r.id,uploaded_at:r.created_at,drive_file_id:r.drive_file_id}))];
  for(const d of files){line((d.title||d.category)+' | '+d.file_name+' | '+d.uploaded_at);if(/^[\w-]+$/.test(d.drive_file_id||'')){if(y>275){pdf.addPage();y=20;}pdf.setTextColor(30,70,150);pdf.textWithLink('Open document in Google Drive',18,y,{url:'https://drive.google.com/open?id='+d.drive_file_id});pdf.setTextColor(0);y+=10;}}
  pdf.save('GOYA-'+(member.profile?.employee_code||'Staff')+'-Record.pdf');
 }
 function init(){
  $('staffDirectorySearch')?.addEventListener('input',renderDirectoryRows);$('staffDirectoryFilter')?.addEventListener('change',renderDirectoryRows);
  document.querySelectorAll('input[type=file][name=file]').forEach(dropZone);
  const observer=new MutationObserver(records=>{for(const record of records)for(const node of record.addedNodes)if(node.nodeType===1){if(node.matches?.('input[type=file][name=file]'))dropZone(node);node.querySelectorAll?.('input[type=file][name=file]').forEach(dropZone);}});observer.observe(document.body,{childList:true,subtree:true});
  const id=sessionStorage.getItem('goya-open-staff-profile');if(id&&window.GoyaAttendance){let tries=0;const timer=setInterval(async()=>{if(++tries>60){clearInterval(timer);return;}if(!context()?.token)return;clearInterval(timer);sessionStorage.removeItem('goya-open-staff-profile');GoyaAttendance.nav(null,'hr-records');await GoyaHR.openRecords();const record=document.querySelector('[data-staff-id="'+CSS.escape(id)+'"]');if(record){record.open=true;record.scrollIntoView({block:'start'});}},500);}
 }
 window.GoyaManagement={rpc,modal,identity,dropZone,editBalance,resign,cancelResignation,renderDirectory,openNewStaff,staffPDF,renderRecordActivity,esc};
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
