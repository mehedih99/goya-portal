(() => {
  const cfg=window.GOYA_CONFIG||{};
  let sb=null;
  let liveState={dashboard:null,history:[],rules:{},settingsLocations:[],serverOffset:0,timer:null};
  let dashboardFilter='',controlFilter='',historyQuickFilter='',controlTarget=null,editTarget=null;
  const $=id=>document.getElementById(id);
  const pad=n=>String(n).padStart(2,'0');
  const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
  const ctx=()=>window.GoyaAttendance?._liveContext?.()||{};

  async function client(){
    if(!cfg.SUPABASE_URL||!cfg.SUPABASE_ANON_KEY)throw new Error('Supabase config missing');
    if(!sb)sb=window.supabase.createClient(cfg.SUPABASE_URL,cfg.SUPABASE_ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
    return sb;
  }
  async function rpc(name,args={}){
    const c=ctx(); if(!c.token)throw new Error('Admin session expired. Please login again.');
    await client(); const {data,error}=await sb.rpc(name,args); if(error)throw new Error(error.message); return data;
  }
  async function publicRpc(name,args={}){await client();const {data,error}=await sb.rpc(name,args);if(error)throw new Error(error.message);return data}
  function toast(msg,err=false){const host=$('toastHost')||document.body,d=document.createElement('div');d.className='toast'+(err?' err':'');d.textContent=msg;host.appendChild(d);setTimeout(()=>d.remove(),3800)}

  const fmtTime=v=>{if(!v)return '—';const d=new Date(v);return Number.isNaN(d.getTime())?'—':d.toLocaleTimeString('en-AE',{hour:'numeric',minute:'2-digit'})};
  const mins=m=>{m=Math.max(0,Math.floor(Number(m)||0));return `${Math.floor(m/60)}h ${pad(m%60)}m`};
  const otText=m=>{m=Math.floor(Math.max(0,Number(m)||0)/30)*30;if(!m)return '0';if(m===30)return '30 min';const h=m/60;return `${Number.isInteger(h)?h:h.toFixed(1)} ${h===1?'hour':'hours'}`};
  const safeName=v=>String(v||'All_Staff').replace(/[^a-z0-9]+/gi,'_').replace(/^_|_$/g,'')||'All_Staff';
  const activeSessions=row=>(Array.isArray(row?.sessions)?row.sessions:[]).filter(s=>!s.is_deleted).slice().sort((a,b)=>new Date(a.check_in_at)-new Date(b.check_in_at));
  const rules=()=>liveState.rules||{};
  const timezone=()=>rules().timezone||'Asia/Dubai';

  function minutesAtZone(ts){
    const d=new Date(ts); if(Number.isNaN(d.getTime()))return null;
    const parts=new Intl.DateTimeFormat('en-GB',{timeZone:timezone(),hour:'2-digit',minute:'2-digit',hour12:false}).formatToParts(d);
    const h=Number(parts.find(x=>x.type==='hour')?.value),m=Number(parts.find(x=>x.type==='minute')?.value);
    return Number.isFinite(h)&&Number.isFinite(m)?h*60+m:null;
  }
  function zonedLocalToUtcMs(dateStr,minuteOfDay,tz=timezone()){const [y,mo,d]=String(dateStr||'').split('-').map(Number),h=Math.floor(minuteOfDay/60),mi=minuteOfDay%60;if(!y||!mo||!d)return NaN;let guess=Date.UTC(y,mo-1,d,h,mi,0);for(let i=0;i<2;i++){const parts=new Intl.DateTimeFormat('en-CA',{timeZone:tz,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false}).formatToParts(new Date(guess));const get=t=>Number(parts.find(x=>x.type===t)?.value);const shown=Date.UTC(get('year'),get('month')-1,get('day'),get('hour'),get('minute'),get('second'));const target=Date.UTC(y,mo-1,d,h,mi,0);guess+=target-shown}return guess}
  function matchedShift(row){
    const ss=activeSessions(row); if(!ss.length)return null;
    const punch=minutesAtZone(ss[0].check_in_at); if(punch==null)return null;
    const shifts=Array.isArray(rules().shift_start_times)?rules().shift_start_times:['08:00','09:00','10:00','11:00','12:00','13:00','14:00','15:00','16:00','17:00'];
    const minsList=shifts.map(v=>{const [h,m]=String(v).split(':').map(Number);return h*60+m}).filter(Number.isFinite).sort((a,b)=>a-b);if(!minsList.length)return null;
    const last=minsList[minsList.length-1];if(punch>last+60)return null;
    let best=null,bestDist=null;minsList.forEach(sm=>{const dist=Math.abs(punch-sm);if(bestDist==null||dist<bestDist||(dist===bestDist&&sm>best)){best=sm;bestDist=dist}});return best;
  }
  function derivedLate(row){
    const ss=activeSessions(row); if(!ss.length)return 0;
    const punch=minutesAtZone(ss[0].check_in_at),sh=matchedShift(row),grace=Number(rules().late_grace_minutes)||15;
    if(punch==null||sh==null)return 0;
    return punch-sh>grace?punch-sh:0;
  }
  function effectiveStartMs(row,session,index){
    let st=new Date(session.check_in_at).getTime();
    if(index===0){const sm=matchedShift(row);if(sm!=null&&row.operational_date){const sch=zonedLocalToUtcMs(row.operational_date,sm);if(Number.isFinite(sch)&&st<sch)st=sch}}
    return st;
  }
  function calc(row,serverNow=null){
    const ss=activeSessions(row),now=serverNow?new Date(serverNow).getTime():Date.now()+liveState.serverOffset;let sec=0;
    ss.forEach((s,i)=>{const st=effectiveStartMs(row,s,i),en=s.check_out_at?new Date(s.check_out_at).getTime():now;if(Number.isFinite(st)&&Number.isFinite(en)&&en>st)sec+=(en-st)/1000});
    const breakTaken=row.break_taken!==false,breakMin=breakTaken?(Number(rules().break_minutes)||60):0,regular=Number(rules().regular_net_minutes)||480,target=breakTaken?(Number(rules().duty_presence_minutes)||540):regular;
    const net=Math.max(0,sec/60-breakMin),ot=Math.floor(Math.max(0,net-regular)/30)*30;
    return {sec,net,ot,target,remaining:Math.max(0,target-sec/60),liveOt:Math.max(0,net-regular)};
  }
  function groupDashboard(d){
    const dayMap=new Map((d.days||[]).map(x=>[x.staff_id,x])),sessMap=new Map();
    for(const s of d.sessions||[]){if(s.is_deleted)continue;if(!sessMap.has(s.staff_id))sessMap.set(s.staff_id,[]);sessMap.get(s.staff_id).push(s)}
    return (d.staff||[]).map(st=>{const day=dayMap.get(st.id)||{operational_date:d.operational_date,break_taken:true,classification:'Day Off - Pending Review',late_minutes:0};return {...day,staff_id:st.id,staff_name:st.name,sessions:(sessMap.get(st.id)||[]).sort((a,b)=>new Date(a.check_in_at)-new Date(b.check_in_at))}})
  }
  function isCompleted(r){const ss=activeSessions(r);return ss.length>0&&!ss.some(x=>!x.check_out_at)}
  function status(r){const ss=activeSessions(r);if(ss.some(s=>!s.check_out_at))return 'On Duty';if(ss.length)return 'Shift Done';return r.classification||'Day Off - Pending Review'}
  function rowMatches(r,filter){
    if(!filter)return true;
    if(filter==='Late')return derivedLate(r)>0;
    if(filter==='Completed'||filter==='Shift Done')return isCompleted(r);
    if(filter==='Pending Review'||filter==='Day Off - Pending Review'||filter==='Review')return status(r)==='Day Off - Pending Review';
    if(filter==='On Duty')return status(r)==='On Duty';
    return status(r)===filter||r.classification===filter;
  }
  function firstIn(r){return activeSessions(r)[0]?.check_in_at||null}
  function lastOut(r){const ss=activeSessions(r);if(!ss.length)return null;return ss.some(s=>!s.check_out_at)?null:ss[ss.length-1]?.check_out_at||null}

  function renderDashboard(){
    const d=liveState.dashboard;if(!d)return;const all=groupDashboard(d);
    let on=0,completed=0,late=0,pending=0;
    all.forEach(r=>{if(status(r)==='On Duty')on++;if(isCompleted(r))completed++;if(derivedLate(r)>0)late++;if(status(r)==='Day Off - Pending Review')pending++});
    if($('liveDOn'))$('liveDOn').textContent=on;if($('liveDCompleted'))$('liveDCompleted').textContent=completed;if($('liveDLate'))$('liveDLate').textContent=late;if($('liveDPending'))$('liveDPending').textContent=pending;
    const rows=all.filter(r=>rowMatches(r,dashboardFilter));
    const html=rows.map(r=>{const c=calc(r),ss=activeSessions(r),open=status(r)==='On Duty',lateMin=derivedLate(r),act=ss.length?`<button class="btn secondary tiny" onclick="GoyaLiveAdmin.editDay('${r.staff_id}','${r.operational_date}')">${open?'Fix / Edit':'Edit'}</button>`:'—';return `<tr><td><strong>${esc(r.staff_name)}</strong>${open?'<span class="live-inline-live"><i class="live-dot"></i> LIVE</span>':''}</td><td><span class="live-status-pill ${open?'on':''}">${esc(status(r))}</span></td><td>${fmtTime(firstIn(r))}</td><td>${open?'<span class="live-text">Live</span>':fmtTime(lastOut(r))}</td><td>${mins(c.sec/60)}</td><td>${c.ot?otText(c.ot):'0'}</td><td>${lateMin?`${lateMin} min`:'—'}</td><td>${ss.length}</td><td>${act}</td></tr>`}).join('');
    if($('liveDashboardRows'))$('liveDashboardRows').innerHTML=html||'<tr><td colspan="9" class="empty">No staff match this filter.</td></tr>';
    const cards=$('liveDashboardCards');if(cards)cards.innerHTML='';
    const label=$('liveDashboardFilterLabel');if(label)label.textContent=dashboardFilter?`Filtered: ${dashboardFilter==='Day Off - Pending Review'?'Pending Review':dashboardFilter}`:'Showing all staff';
    document.querySelectorAll('.live-stat-btn').forEach(x=>x.classList.toggle('active-filter',!!dashboardFilter&&x.dataset.filter===dashboardFilter));
  }
  async function loadDashboard(){try{const date=$('liveDashDate')?.value||new Date().toISOString().slice(0,10),d=await rpc('attendance_live_admin_dashboard',{p_token:ctx().token,p_date:date});liveState.dashboard=d;liveState.rules=d.rules||{};liveState.serverOffset=new Date(d.server_now).getTime()-Date.now();renderDashboard();clearInterval(liveState.timer);liveState.timer=setInterval(renderDashboard,1000)}catch(e){toast(e.message,true)}}
  function setDashboardFilter(filter){dashboardFilter=filter||'';renderDashboard()}
  function applyDashboardFilter(){renderDashboard()}

  function classificationOptions(cur){return ['Day Off - Pending Review','Weekly Off','Leave','Sick Leave','Unpaid Leave','Absent','Public Holiday','Other Approved','Duty'].map(x=>`<option${x===cur?' selected':''}>${x}</option>`).join('')}
  function applyMonth(){const m=$('liveHistMonth')?.value;if(!m)return;const [y,mo]=m.split('-').map(Number),end=new Date(y,mo,0).getDate();$('liveHistFrom').value=`${m}-01`;$('liveHistTo').value=`${m}-${pad(end)}`}
  async function loadHistory(){try{const from=$('liveHistFrom').value,to=$('liveHistTo').value,staff=$('liveHistStaff').value||null;if(!from||!to)return toast('Select From and To dates.',true);const d=await rpc('attendance_live_admin_history',{p_token:ctx().token,p_start:from,p_end:to,p_staff_id:staff});liveState.rules=d.rules||liveState.rules;liveState.serverOffset=new Date(d.server_now).getTime()-Date.now();liveState.history=d.rows||[];renderHistory()}catch(e){toast(e.message,true)}}
  function quickMatch(r){
    if(!historyQuickFilter)return true;
    const c=calc(r),ss=activeSessions(r),st=status(r);
    if(historyQuickFilter==='Ready')return ss.length>0&&!ss.some(s=>!s.check_out_at);
    if(historyQuickFilter==='Pending')return st==='Day Off - Pending Review';
    if(historyQuickFilter==='Late')return derivedLate(r)>0;
    if(historyQuickFilter==='OT')return c.ot>0;
    if(historyQuickFilter==='Missing Checkout')return ss.some(s=>!s.check_out_at);
    return true;
  }
  function filteredRows(){const filter=$('liveHistStatus')?.value||'';return (liveState.history||[]).filter(r=>{let ok=true;if(filter==='Completed')ok=isCompleted(r);else if(filter==='On Duty')ok=status(r)==='On Duty';else if(filter)ok=status(r)===filter||r.classification===filter;return ok&&quickMatch(r)})}
  function setHistoryQuickFilter(v){historyQuickFilter=v||'';renderHistory()}
  function summaryFor(rows){const o={duty:0,weekly:0,leave:0,sick:0,unpaid:0,absent:0,holiday:0,other:0,pending:0,work:0,net:0,ot:0,lateDays:0,lateMin:0,noBreak:0,split:0,missing:0};rows.forEach(r=>{const c=calc(r),ss=activeSessions(r),st=status(r);if(ss.length){o.duty++;o.work+=c.sec/60;o.net+=c.net;o.ot+=c.ot;if(r.break_taken===false)o.noBreak++;if(ss.length>1)o.split++;if(ss.some(s=>!s.check_out_at))o.missing++}const lm=derivedLate(r);if(lm){o.lateDays++;o.lateMin+=lm}if(st==='Weekly Off')o.weekly++;else if(st==='Leave')o.leave++;else if(st==='Sick Leave')o.sick++;else if(st==='Unpaid Leave')o.unpaid++;else if(st==='Absent')o.absent++;else if(st==='Public Holiday')o.holiday++;else if(st==='Other Approved')o.other++;else if(st==='Day Off - Pending Review')o.pending++});return o}
  function renderSummary(rows){
    const s=summaryFor(rows),offLeave=s.weekly+s.leave+s.sick+s.unpaid+s.holiday+s.other;
    const host=$('liveReportSummary');if(host)host.innerHTML=[['Duty Days',s.duty],['Off / Leave',offLeave],['Net Hours',mins(s.net)],['OT',otText(s.ot)],['Late Days',s.lateDays],['Pending Review',s.pending]].map(([k,v])=>`<div><span>${k}</span><strong>${v}</strong></div>`).join('');
    const ph=$('livePersonSummary'),staffSelected=$('liveHistStaff')?.value;
    if(ph){if(!staffSelected){ph.innerHTML='';ph.classList.add('hidden')}else{ph.classList.remove('hidden');ph.innerHTML=`<article class="live-single-person-summary"><div><span>Working <b>${mins(s.work)}</b></span><span>Net <b>${mins(s.net)}</b></span><span>OT <b>${otText(s.ot)}</b></span><span>Split Shift <b>${s.split}</b></span><span>Missing Checkout <b>${s.missing}</b></span></div></article>`}}
    document.querySelectorAll('[data-history-quick]').forEach(b=>b.classList.toggle('active-filter',b.dataset.historyQuick===historyQuickFilter));
  }
  function renderHistory(){
    const rows=filteredRows();renderSummary(rows);const tbody=$('liveHistoryAdminRows');if(!tbody)return;
    tbody.innerHTML=rows.length?rows.map(r=>{const c=calc(r),ss=activeSessions(r),st=status(r),isNo=!ss.length,lm=derivedLate(r),primary=isNo?`<button class="btn secondary tiny" onclick="GoyaLiveAdmin.saveClassification('${r.staff_id}','${r.operational_date}',this)">Save</button>`:`<button class="btn secondary tiny" onclick="GoyaLiveAdmin.editDay('${r.staff_id}','${r.operational_date}')">Edit</button>`;return `<tr><td>${esc(r.operational_date)}</td><td><strong>${esc(r.staff_name)}</strong></td><td>${ss.length?ss.map((s,i)=>`Shift ${i+1}: ${fmtTime(s.check_in_at)} → ${fmtTime(s.check_out_at)}`).join('<br>'):'—'}</td><td>${ss.length}</td><td>${ss.length?mins(c.sec/60):'—'}</td><td>${ss.length?mins(c.net):'—'}</td><td>${c.ot?otText(c.ot):'—'}</td><td>${lm?`${lm} min`:'—'}</td><td>${ss.length?(r.break_taken!==false?'Yes':'No'):'—'}</td><td>${isNo?`<select class="live-classify" data-staff="${r.staff_id}" data-date="${r.operational_date}">${classificationOptions(r.classification||'Day Off - Pending Review')}</select>`:esc(st)}</td><td><div class="live-row-actions">${primary}<button class="btn danger tiny" onclick="GoyaLiveAdmin.deleteHistoryDay('${r.staff_id}','${r.operational_date}','${esc(r.staff_name)}')">Delete</button></div></td></tr>`}).join(''):'<tr><td colspan="11" class="empty">No records for selected filters.</td></tr>';
  }
  async function deleteHistoryDay(staffId,date,staffName){if(!confirm(`Archive ${staffName} attendance for ${date}?\n\nIt will disappear from active history/reports but remain in the permanent audit trail.`))return;try{await rpc('attendance_live_admin_delete_day',{p_token:ctx().token,p_staff_id:staffId,p_date:date,p_reason:null});toast('Attendance archived.');await refreshVisible()}catch(e){toast(e.message,true)}}
  async function saveClassification(staffId,date,btn){const sel=btn.closest('tr').querySelector('.live-classify'),val=sel.value;try{await rpc('attendance_live_admin_classify_day',{p_token:ctx().token,p_staff_id:staffId,p_date:date,p_classification:val,p_note:null});toast('Day classification saved.');await loadHistory()}catch(e){toast(e.message,true)}}

  function toLocalInput(v){if(!v)return '';const d=new Date(v),z=n=>String(n).padStart(2,'0');return `${d.getFullYear()}-${z(d.getMonth()+1)}-${z(d.getDate())}T${z(d.getHours())}:${z(d.getMinutes())}`}
  function localInputToIso(v){if(!v)return null;const d=new Date(v);return d.toISOString()}
  async function fetchDay(staffId,date){try{const d=await rpc('attendance_live_admin_history',{p_token:ctx().token,p_start:date,p_end:date,p_staff_id:staffId});liveState.rules=d.rules||liveState.rules;return (d.rows||[]).find(r=>r.staff_id===staffId&&r.operational_date===date)||(d.rows||[])[0]||null}catch{return null}}
  async function editDay(staffId,date){
    const r=await fetchDay(staffId,date);if(!r)return toast('Attendance day could not be loaded.',true);editTarget={staffId,date,staffName:r.staff_name};
    $('liveEditTitle').textContent=`${r.staff_name} · ${date}`;
    const dayBox=$('liveEditDayControls');if(dayBox)dayBox.innerHTML=`<div class="live-edit-day-grid v26-day-grid"><label>Break Taken<select id="liveEditBreak"><option value="true"${r.break_taken!==false?' selected':''}>Yes</option><option value="false"${r.break_taken===false?' selected':''}>No</option></select></label><label>Split Shift<select id="liveEditSplit"><option value="false"${r.split_shift_allowed!==true?' selected':''}>No</option><option value="true"${r.split_shift_allowed===true?' selected':''}>Yes</option></select></label><label>Status<select id="liveEditClassification">${classificationOptions(r.classification||'Duty')}</select></label><label class="live-edit-note">Note (optional)<input id="liveEditNote" value="${esc(r.classification_note||'')}" placeholder="Optional admin note"></label><button class="btn success" onclick="GoyaLiveAdmin.saveDayEdit()">Save Changes</button></div>`;
    const ss=activeSessions(r),list=$('liveEditSessions');list.innerHTML=ss.length?ss.map((s,i)=>`<div class="live-edit-session"><strong>Shift ${i+1}</strong><label>Check In<input type="datetime-local" data-id="${s.id}" data-field="in" value="${toLocalInput(s.check_in_at)}"></label><label>Check Out<input type="datetime-local" data-id="${s.id}" data-field="out" value="${toLocalInput(s.check_out_at)}"></label><div class="live-edit-actions"><button class="btn secondary tiny" onclick="GoyaLiveAdmin.saveSessionEdit('${s.id}',this)">Save</button><button class="btn danger tiny" onclick="GoyaLiveAdmin.deleteSession('${s.id}',this)">Remove</button></div></div>`).join(''):'<div class="live-empty">No session exists for this day.</div>';
    const add=$('liveEditAddSession');if(add)add.onclick=()=>{closeEdit();openManualControl(staffId,r.staff_name,ss.length?'REJOIN':'CHECK_IN')};
    $('liveEditModal').classList.remove('hidden');
  }
  async function saveDayEdit(){if(!editTarget)return;try{await rpc('attendance_live_admin_update_day_v26',{p_token:ctx().token,p_staff_id:editTarget.staffId,p_date:editTarget.date,p_break_taken:$('liveEditBreak').value==='true',p_split_shift:$('liveEditSplit').value==='true',p_classification:$('liveEditClassification').value,p_note:$('liveEditNote').value.trim()||null});toast('Attendance settings saved and recalculated.');await refreshVisible();await editDay(editTarget.staffId,editTarget.date)}catch(e){toast(e.message,true)}}
  async function saveSessionEdit(id,btn){const box=btn.closest('.live-edit-session'),pin=box.querySelector('[data-field="in"]').value,pout=box.querySelector('[data-field="out"]').value;if(!pin)return toast('Check In is required.',true);if(!pout&&!confirm('Check Out is blank. Keep this shift On Duty?'))return;try{await rpc('attendance_live_admin_update_session',{p_token:ctx().token,p_session_id:id,p_check_in:localInputToIso(pin),p_check_out:localInputToIso(pout)});toast('Shift updated and totals recalculated.');const t={...editTarget};await refreshVisible();if(t)await editDay(t.staffId,t.date)}catch(e){toast(e.message,true)}}
  async function deleteSession(id){if(!confirm('Remove this shift from active attendance? It will remain in the audit trail.'))return;try{await rpc('attendance_live_admin_delete_session',{p_token:ctx().token,p_session_id:id,p_reason:null});toast('Shift archived.');const t={...editTarget};await refreshVisible();if(t)await editDay(t.staffId,t.date)}catch(e){toast(e.message,true)}}
  function closeEdit(){$('liveEditModal')?.classList.add('hidden');editTarget=null}

  function detailRows(rows=filteredRows()){return rows.map(r=>{const c=calc(r),ss=activeSessions(r),lm=derivedLate(r);return {'Date':r.operational_date,'Staff':r.staff_name,'Shift Sessions':ss.length,'Session Details':ss.map((s,i)=>`Shift ${i+1}: ${fmtTime(s.check_in_at)} - ${fmtTime(s.check_out_at)}`).join(' | '),'Worked':ss.length?mins(c.sec/60):'','Net':ss.length?mins(c.net):'','OT':c.ot?otText(c.ot):'','Late Minutes':lm,'Break Taken':ss.length?(r.break_taken!==false?'Yes':'No'):'','Status':status(r),'Note':r.classification_note||''}})}
  function reportFileBase(ext){const staffSel=$('liveHistStaff'),staff=staffSel?.value?staffSel.options[staffSel.selectedIndex]?.text:'All_Staff',from=$('liveHistFrom').value,to=$('liveHistTo').value;return `Goya_Live_Attendance_${safeName(staff)}_${from}_to_${to}.${ext}`}
  function summarySheetRows(rows){const by=new Map();rows.forEach(r=>{if(!by.has(r.staff_id))by.set(r.staff_id,[]);by.get(r.staff_id).push(r)});return [...by.values()].map(rs=>{const s=summaryFor(rs),r=rs[0];return {'Staff':r.staff_name,'Duty Days':s.duty,'Weekly Off':s.weekly,'Leave':s.leave,'Sick Leave':s.sick,'Unpaid Leave':s.unpaid,'Absent':s.absent,'Public Holiday':s.holiday,'Other Approved':s.other,'Pending Review':s.pending,'Working Hours':mins(s.work),'Net Hours':mins(s.net),'OT':otText(s.ot),'Late Days':s.lateDays,'Late Minutes':s.lateMin,'No Break Days':s.noBreak,'Split Shift Days':s.split,'Missing Checkout':s.missing}})}
  function exportExcel(){const rows=filteredRows();if(!rows.length)return toast('Load history first.',true);if(!window.XLSX)return toast('Excel library is still loading.',true);const wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,XLSX.utils.json_to_sheet(summarySheetRows(rows)),'Summary');XLSX.utils.book_append_sheet(wb,XLSX.utils.json_to_sheet(detailRows(rows)),'Daily Details');const by=new Map();rows.forEach(r=>{if(!by.has(r.staff_id))by.set(r.staff_id,[]);by.get(r.staff_id).push(r)});for(const rs of by.values()){let nm=safeName(rs[0].staff_name).slice(0,31)||'Staff';if(wb.SheetNames.includes(nm))nm=(nm.slice(0,27)+'_'+Math.random().toString(36).slice(2,5)).slice(0,31);XLSX.utils.book_append_sheet(wb,XLSX.utils.json_to_sheet(detailRows(rs)),nm)}XLSX.writeFile(wb,reportFileBase('xlsx'))}
  function drawPdfSummary(doc,s,startY=34){const offLeave=s.weekly+s.leave+s.sick+s.unpaid+s.holiday+s.other,cards=[['Duty Days',s.duty],['Off / Leave',offLeave],['Net Hours',mins(s.net)],['OT',otText(s.ot)],['Late Days',s.lateDays],['Pending',s.pending]];let x=14;cards.forEach(([k,v])=>{doc.setFillColor(246,249,247);doc.setDrawColor(216,227,221);doc.roundedRect(x,startY,41,17,3,3,'FD');doc.setFontSize(7.5);doc.setTextColor(92,108,100);doc.text(String(k),x+3,startY+6);doc.setFontSize(11);doc.setTextColor(28,54,45);doc.text(String(v),x+3,startY+13);x+=44});doc.setTextColor(0);return startY+22}
  function exportPDF(){
    const rows=filteredRows();if(!rows.length)return toast('Load history first.',true);if(!window.jspdf?.jsPDF)return toast('PDF library is still loading.',true);
    const {jsPDF}=window.jspdf,doc=new jsPDF({orientation:'landscape'}),from=$('liveHistFrom').value,to=$('liveHistTo').value,by=new Map();rows.forEach(r=>{if(!by.has(r.staff_id))by.set(r.staff_id,[]);by.get(r.staff_id).push(r)});
    const allSummary=summaryFor(rows),multi=by.size>1;
    if(multi){doc.setFontSize(19);doc.text('GOYA - Attendance Summary',14,15);doc.setFontSize(9);doc.setTextColor(90);doc.text(`Period: ${from} to ${to} · Staff: ${by.size}`,14,23);doc.setTextColor(0);let y=drawPdfSummary(doc,allSummary,29);doc.autoTable({startY:y,head:[['Staff','Duty','Off/Leave','Net','OT','Late Days','Pending','Missing Checkout']],body:summarySheetRows(rows).map(x=>[x.Staff,x['Duty Days'],x['Weekly Off']+x.Leave+x['Sick Leave']+x['Unpaid Leave']+x['Public Holiday']+x['Other Approved'],x['Net Hours'],x.OT,x['Late Days'],x['Pending Review'],x['Missing Checkout']]),styles:{fontSize:8,cellPadding:2.2},headStyles:{fillColor:[44,92,72]},alternateRowStyles:{fillColor:[248,250,249]}})}
    let first=!multi;for(const rs of by.values()){if(!first||multi)doc.addPage();first=false;const r0=rs[0],s=summaryFor(rs);doc.setFontSize(18);doc.text('GOYA - Live Attendance Report',14,15);doc.setFontSize(12);doc.text(`${r0.staff_name}`,14,23);doc.setFontSize(9);doc.setTextColor(90);doc.text(`Period: ${from} to ${to}`,14,29);doc.setTextColor(0);const y=drawPdfSummary(doc,s,34);doc.autoTable({startY:y,head:[['Date','Sessions','Working Time','Worked','Net','OT','Late','Break','Status']],body:rs.map(r=>{const c=calc(r),ss=activeSessions(r),lm=derivedLate(r);return [r.operational_date,ss.length,ss.length?ss.map((x,i)=>`S${i+1} ${fmtTime(x.check_in_at)}-${fmtTime(x.check_out_at)}`).join(' | '):'—',ss.length?mins(c.sec/60):'—',ss.length?mins(c.net):'—',c.ot?otText(c.ot):'—',lm?`${lm} min`:'—',ss.length?(r.break_taken!==false?'Yes':'No'):'—',status(r)]}),styles:{fontSize:7.5,cellPadding:2.2,textColor:[42,56,49]},headStyles:{fillColor:[44,92,72],textColor:[255,255,255]},alternateRowStyles:{fillColor:[248,250,249]}})}doc.save(reportFileBase('pdf'))}
  function overtimeSummaryRows(){const rows=filteredRows(),by=new Map();rows.forEach(r=>{const c=calc(r);if(c.ot<=0)return;if(!by.has(r.staff_id))by.set(r.staff_id,{staff:r.staff_name,ot:0,days:0});const x=by.get(r.staff_id);x.ot+=c.ot;x.days+=1});return [...by.values()].sort((a,b)=>b.ot-a.ot)}
  function overtimeFileBase(ext){const staffSel=$('liveHistStaff'),staff=staffSel?.value?staffSel.options[staffSel.selectedIndex]?.text:'All_Staff',from=$('liveHistFrom').value,to=$('liveHistTo').value;return `Goya_Overtime_Only_${safeName(staff)}_${from}_to_${to}.${ext}`}
  function exportOvertimeExcel(){const data=overtimeSummaryRows();if(!data.length)return toast('No overtime found for the selected period.',true);if(!window.XLSX)return toast('Excel library is still loading.',true);const rows=data.map(x=>({'Staff':x.staff,'OT Days':x.days,'Total OT':otText(x.ot),'OT Minutes':x.ot}));const wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,XLSX.utils.json_to_sheet(rows),'Overtime Summary');XLSX.writeFile(wb,overtimeFileBase('xlsx'))}
  function exportOvertimePDF(){const data=overtimeSummaryRows();if(!data.length)return toast('No overtime found for the selected period.',true);if(!window.jspdf?.jsPDF)return toast('PDF library is still loading.',true);const {jsPDF}=window.jspdf,doc=new jsPDF({orientation:'portrait'}),from=$('liveHistFrom').value,to=$('liveHistTo').value,total=data.reduce((a,x)=>a+x.ot,0);doc.setFontSize(18);doc.text('GOYA - Overtime Summary',14,16);doc.setFontSize(10);doc.text(`Period: ${from} to ${to}`,14,24);doc.text(`Staff with OT: ${data.length}   Total OT: ${otText(total)}`,14,30);doc.autoTable({startY:36,head:[['Staff','OT Days','Total OT']],body:data.map(x=>[x.staff,x.days,otText(x.ot)]),styles:{fontSize:9,cellPadding:2.5},headStyles:{fillColor:[48,81,70]},margin:{left:14,right:14}});doc.save(overtimeFileBase('pdf'))}

  async function getPublicIp(){for(const url of ['https://api.ipify.org?format=json','https://api64.ipify.org?format=json']){try{const r=await fetch(url,{cache:'no-store'});if(r.ok){const j=await r.json();if(j.ip)return j.ip}}catch{}}throw new Error('Could not detect public IP.')}
  function getGps(){return new Promise((resolve,reject)=>navigator.geolocation?navigator.geolocation.getCurrentPosition(p=>resolve({lat:p.coords.latitude,lon:p.coords.longitude,accuracy:p.coords.accuracy,timestamp:p.timestamp}),e=>reject(new Error(e.code===1?'Allow precise location permission first.':'Could not get fresh GPS.')),{enableHighAccuracy:true,timeout:20000,maximumAge:0}):reject(new Error('GPS unsupported.')))}
  async function testVerification(){const box=$('liveVerificationTest');if(box)box.innerHTML='<span class="live-verify wait">Testing fresh GPS + office network…</span>';try{const [g,ip]=await Promise.all([getGps(),getPublicIp()]);const v=await publicRpc('attendance_live_verify_workplace',{p_lat:g.lat,p_lon:g.lon,p_public_ip:ip});const distance=Number(v?.distance_m);if(box)box.innerHTML=`<div class="verify-test-grid"><span>GPS <b>${v?.location_ok!==false?'Captured':'Failed'} · ±${Math.round(g.accuracy||0)}m</b></span><span>Distance <b>${Number.isFinite(distance)?Math.round(distance)+'m':'—'}</b></span><span>Network <b>${v?.network_ok!==false&&v?.ok?'Passed':(v?.network_ok===false?'Failed':'Checked')}</b></span><span>Public IP <b>${esc(ip)}</b></span><span>Overall <b class="${v?.ok?'ok-text':'bad-text'}">${v?.ok?'Verified':'Not Verified'}</b></span></div>`;toast(v?.ok?'Workplace verification passed.':'Workplace verification did not pass.',!v?.ok)}catch(e){if(box)box.innerHTML=`<span class="live-verify bad">${esc(e.message)}</span>`;toast(e.message,true)}}
  function renderLocations(){const host=$('liveLocationList');if(!host)return;host.innerHTML=liveState.settingsLocations.length?liveState.settingsLocations.map((l,i)=>`<div class="live-location-row"><div><strong>${esc(l.name||'Workplace')}</strong><span>${Number(l.lat).toFixed(6)}, ${Number(l.lon).toFixed(6)} · ${l.radius_m||150}m</span></div><button class="btn danger tiny" onclick="GoyaLiveAdmin.removeLocation(${i})">Remove</button></div>`).join(''):'<div class="live-empty">No workplace location configured yet.</div>'}
  async function loadSettings(){try{const r=await rpc('attendance_live_admin_settings',{p_token:ctx().token});liveState.rules=r||{};liveState.settingsLocations=Array.isArray(r.locations)?r.locations:[];$('liveRequireLocation').checked=r.require_location!==false;$('liveRequireNetwork').checked=r.require_network!==false;$('liveDutyHours').value=(Number(r.duty_presence_minutes)||540)/60;$('liveBreakMinutes').value=Number(r.break_minutes)||60;$('liveApprovedIps').value=(Array.isArray(r.approved_public_ips)?r.approved_public_ips:[]).join('\n');renderLocations()}catch(e){toast(e.message,true)}}
  async function detectLocation(){try{const g=await getGps();$('liveLocLat').value=g.lat.toFixed(7);$('liveLocLon').value=g.lon.toFixed(7);toast(`GPS captured ±${Math.round(g.accuracy||0)}m`)}catch(e){toast(e.message,true)}}
  async function detectIp(){try{const ip=await getPublicIp(),box=$('liveApprovedIps'),ips=box.value.split(/\s+/).filter(Boolean);if(!ips.includes(ip))ips.push(ip);box.value=ips.join('\n');toast(`Current public IP added: ${ip}`)}catch(e){toast(e.message,true)}}
  function addLocation(){const name=$('liveLocName').value.trim()||'Workplace',lat=+$('liveLocLat').value,lon=+$('liveLocLon').value,radius=+$('liveLocRadius').value||150;if(!Number.isFinite(lat)||!Number.isFinite(lon))return toast('Capture or enter valid GPS coordinates.',true);liveState.settingsLocations.push({name,lat,lon,radius_m:radius,active:true});$('liveLocName').value='';renderLocations()}
  function removeLocation(i){liveState.settingsLocations.splice(i,1);renderLocations()}
  async function saveSettings(){const ips=[...new Set($('liveApprovedIps').value.split(/\s+/).map(x=>x.trim()).filter(Boolean))],value={require_location:$('liveRequireLocation').checked,require_network:$('liveRequireNetwork').checked,duty_presence_minutes:Math.round((+$('liveDutyHours').value||9)*60),regular_net_minutes:480,break_minutes:+$('liveBreakMinutes').value||60,late_grace_minutes:15,operational_cutoff:'02:00',shift_start_times:['08:00','09:00','10:00','11:00','12:00','13:00','14:00','15:00','16:00','17:00'],locations:liveState.settingsLocations,approved_public_ips:ips};try{liveState.rules=await rpc('attendance_live_admin_save_settings',{p_token:ctx().token,p_value:value});toast('Live Attendance settings saved.')}catch(e){toast(e.message,true)}}
  function fillStaffFilter(){const sel=$('liveHistStaff'),staff=ctx().staff||[];if(sel&&!sel.dataset.ready){sel.innerHTML='<option value="">All Staff</option>'+staff.map(s=>`<option value="${s.portal_staff_id||s.id}">${esc(s.name)}</option>`).join('');sel.dataset.ready='1'}}

  function setControlFilter(filter){controlFilter=filter||'';renderControl()}
  function renderControl(){
    const d=liveState.dashboard;if(!d)return;const all=groupDashboard(d),host=$('liveControlCards');let on=0,done=0,pending=0;
    all.forEach(r=>{if(status(r)==='On Duty')on++;else if(isCompleted(r))done++;if(status(r)==='Day Off - Pending Review')pending++});
    const sum=$('liveControlSummary');if(sum)sum.innerHTML=`<button class="live-control-stat ${controlFilter==='On Duty'?'active-filter':''}" onclick="GoyaLiveAdmin.setControlFilter('On Duty')"><span>On Duty</span><strong>${on}</strong></button><button class="live-control-stat ${controlFilter==='Completed'?'active-filter':''}" onclick="GoyaLiveAdmin.setControlFilter('Completed')"><span>Shift Done</span><strong>${done}</strong></button><button class="live-control-stat ${controlFilter==='Pending Review'?'active-filter':''}" onclick="GoyaLiveAdmin.setControlFilter('Pending Review')"><span>Review</span><strong>${pending}</strong></button><button class="live-control-clear ${!controlFilter?'active-filter':''}" onclick="GoyaLiveAdmin.setControlFilter('')">All Staff</button>`;
    const rows=all.filter(r=>rowMatches(r,controlFilter));
    if(host)host.innerHTML=`<div class="live-control-list"><div class="live-control-head"><span>Staff</span><span>Status</span><span>Check In</span><span>Check Out</span><span>Working</span><span>OT</span><span>Sessions</span><span>Late</span><span>Actions</span></div>${rows.map(r=>{const c=calc(r),ss=activeSessions(r),open=status(r)==='On Duty',lm=derivedLate(r);return `<div class="live-control-row ${open?'is-live':''}"><div class="live-control-name"><strong>${open?'<i class="live-dot"></i>':''}${esc(r.staff_name)}</strong>${open?'<small>LIVE</small>':''}</div><span class="live-status-pill ${open?'on':''}">${esc(status(r))}</span><span>${fmtTime(firstIn(r))}</span><span>${open?'<span class="live-text">Live</span>':fmtTime(lastOut(r))}</span><b>${mins(c.sec/60)}</b><b>${c.ot?otText(c.ot):'0'}</b><span>${ss.length}</span><span>${lm?`${lm}m`:'—'}</span><div class="live-control-actions"><button class="btn success tiny" ${open?'disabled':''} onclick="GoyaLiveAdmin.openManualControl('${r.staff_id}','${esc(r.staff_name)}','${ss.length?'REJOIN':'CHECK_IN'}')">${ss.length?'Rejoin':'Check In'}</button><button class="btn danger tiny" ${open?'':'disabled'} onclick="GoyaLiveAdmin.openManualControl('${r.staff_id}','${esc(r.staff_name)}','CHECK_OUT')">Check Out</button>${ss.length?`<button class="btn secondary tiny" onclick="GoyaLiveAdmin.editDay('${r.staff_id}','${r.operational_date}')">Edit</button>`:''}</div></div>`}).join('')||'<div class="live-empty">No staff match this filter.</div>'}</div>`;
  }
  async function loadControl(){try{const date=$('liveControlDate')?.value||new Date().toISOString().slice(0,10),d=await rpc('attendance_live_admin_dashboard',{p_token:ctx().token,p_date:date});liveState.dashboard=d;liveState.rules=d.rules||{};liveState.serverOffset=new Date(d.server_now).getTime()-Date.now();renderControl();clearInterval(liveState.timer);liveState.timer=setInterval(renderControl,1000)}catch(e){toast(e.message,true)}}
  function openControl(){if(!$('liveControlDate').value)$('liveControlDate').value=new Date().toISOString().slice(0,10);loadControl()}
  function localClock(){const d=new Date(Date.now()+liveState.serverOffset);return `${pad(d.getHours())}:${pad(d.getMinutes())}`}
  function openManualControl(staffId,staffName,action){
    controlTarget={staffId,staffName};$('liveControlModalTitle').textContent=`${staffName} · Attendance`;$('liveControlAction').value=action||'CHECK_IN';
    const selected=$('liveControlDate')?.value||new Date().toISOString().slice(0,10);$('liveControlDateField').value=selected;$('liveControlClockField').value=localClock();$('liveControlBreak').value='true';$('liveControlNote').value='';$('liveControlModal').classList.remove('hidden');
  }
  function closeControlModal(){$('liveControlModal')?.classList.add('hidden');controlTarget=null}
  async function saveManualControl(){if(!controlTarget)return;const action=$('liveControlAction').value,date=$('liveControlDateField').value,time=$('liveControlClockField').value,note=$('liveControlNote').value.trim();if(!date||!time)return toast('Select attendance date and time.',true);if(!confirm(`Save ${action.replace('_',' ')} for ${controlTarget.staffName} on ${date} at ${time}?`))return;try{const d=new Date(`${date}T${time}`);if(Number.isNaN(d.getTime()))throw new Error('Invalid date/time.');await rpc('attendance_live_admin_manual_action',{p_token:ctx().token,p_staff_id:controlTarget.staffId,p_action:action,p_at:d.toISOString(),p_break_taken:$('liveControlBreak').value==='true',p_note:note||null});toast('Attendance saved and recalculated.');closeControlModal();await loadControl();if(!$('attLiveHistory')?.classList.contains('hidden'))await loadHistory()}catch(e){toast(e.message,true)}}

  async function refreshVisible(){if(!$('attLiveControl')?.classList.contains('hidden'))await loadControl();if(!$('attLiveDashboard')?.classList.contains('hidden'))await loadDashboard();if(!$('attLiveHistory')?.classList.contains('hidden'))await loadHistory()}
  function openDashboard(){fillStaffFilter();if(!$('liveDashDate').value)$('liveDashDate').value=new Date().toISOString().slice(0,10);loadDashboard()}
  function openHistory(){fillStaffFilter();const d=new Date(),end=d.toISOString().slice(0,10),month=end.slice(0,7),start=`${month}-01`;if(!$('liveHistMonth').value)$('liveHistMonth').value=month;if(!$('liveHistFrom').value)$('liveHistFrom').value=start;if(!$('liveHistTo').value)$('liveHistTo').value=end;loadHistory()}
  function openSettings(){loadSettings()}

  window.GoyaLiveAdmin={openDashboard,loadDashboard,setDashboardFilter,applyDashboardFilter,openControl,loadControl,setControlFilter,openManualControl,closeControlModal,saveManualControl,openHistory,loadHistory,renderHistory,setHistoryQuickFilter,applyMonth,saveClassification,deleteHistoryDay,editDay,saveDayEdit,saveSessionEdit,deleteSession,closeEdit,exportExcel,exportPDF,exportOvertimeExcel,exportOvertimePDF,openSettings,loadSettings,detectLocation,detectIp,testVerification,addLocation,removeLocation,saveSettings};
  if(window.GoyaAttendance){window.GoyaAttendance.openLiveDashboard=openDashboard;window.GoyaAttendance.openLiveHistory=openHistory;window.GoyaAttendance.openLiveSettings=openSettings;}
})();
