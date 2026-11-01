(() => {
  const cfg=window.GOYA_CONFIG||{};
  let sb=null,liveState={dashboard:null,history:[],legacyHistory:[],controlReviews:[],rules:{},settingsLocations:[],serverOffset:0,timer:null},dashboardFilter='',controlFilter='',controlTarget=null,editTarget=null,previousSaveBusy=false;
  const $=id=>document.getElementById(id),pad=n=>String(n).padStart(2,'0'),esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
  const ctx=()=>window.GoyaAttendance?._liveContext?.()||{};
  async function client(){if(!cfg.SUPABASE_URL||!cfg.SUPABASE_ANON_KEY)throw new Error('Supabase config missing');if(!sb)sb=window.supabase.createClient(cfg.SUPABASE_URL,cfg.SUPABASE_ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});return sb}
  async function rpc(name,args={}){const c=ctx();if(!c.token)throw new Error('Admin session expired. Please login again.');await client();const {data,error}=await (window.GoyaUI?.task?window.GoyaUI.task(()=>sb.rpc(name,args)):sb.rpc(name,args));if(error)throw new Error(error.message);return data}
  function toast(msg,err=false){const host=$('toastHost')||document.body,d=document.createElement('div');d.className='toast'+(err?' err':'');d.textContent=msg;host.appendChild(d);setTimeout(()=>d.remove(),3800)}
  const lastCheckout=ss=>(ss||[]).reduce((last,s)=>{const t=Date.parse(s.check_out_at);return Number.isFinite(t)&&(!last||t>Date.parse(last))?s.check_out_at:last;},null);
  const fmtTime=v=>{if(!v)return '—';const d=new Date(v);return Number.isNaN(d.getTime())?'—':d.toLocaleTimeString('en-AE',{hour:'numeric',minute:'2-digit',timeZone:'Asia/Dubai'})};
  const fmtDate=v=>{const d=new Date(v+'T12:00:00');return d.toLocaleDateString('en-AE',{day:'2-digit',month:'short',year:'numeric'})};
  const mins=m=>{m=Math.max(0,Math.floor(Number(m)||0));return `${Math.floor(m/60)}h ${pad(m%60)}m`};
  const otText=m=>{m=Math.max(0,Math.floor(Number(m)||0));if(!m)return '0';const h=Math.floor(m/60),min=m%60;return h&&min?`${h}h ${min}m`:h?`${h}h`:`${min} min`};
  function calc(row,serverNow=null){if(row?.legacy_precalc){const x=row.legacy_precalc;return {sec:Number(x.sec)||0,net:Number(x.net)||0,ot:Number(x.ot)||0,target:Number(x.target)||0,remaining:0,liveOt:Number(x.ot)||0}}if(window.GoyaOT)return GoyaOT.totals(row,liveState.rules||{},serverNow||row.report_now?Date.parse(serverNow||row.report_now):Date.now()+liveState.serverOffset);const rules=liveState.rules||{},sessions=Array.isArray(row.sessions)?row.sessions:[];let sec=0;const snapshot=serverNow||row.report_now,now=snapshot?new Date(snapshot).getTime():Date.now()+liveState.serverOffset;sessions.forEach((session,index)=>{if(!session?.check_in_at)return;let start=new Date(session.check_in_at).getTime();const end=session.check_out_at?new Date(session.check_out_at).getTime():now;if(Number.isFinite(start)&&Number.isFinite(end)&&end>start)sec+=(end-start)/1000});const regular=Math.max(1,Number(rules.regular_net_minutes)||480),breakMinutes=Math.max(0,Number(rules.break_minutes??60)),breakTaken=rules.force_no_break&&sessions.some(s=>!s.check_out_at)?false:row.break_taken!==false,target=breakTaken?regular+breakMinutes:regular,presenceMinutes=sec/60,net=Math.max(0,presenceMinutes-(breakTaken?breakMinutes:0)),rawOt=Math.max(0,net-regular),ot=Math.floor(rawOt),remainingSeconds=Math.max(0,target*60-sec),liveOtSeconds=Math.max(0,sec-target*60);return {sec,net,ot,target,remaining:remainingSeconds/60,remainingSeconds,liveOt:liveOtSeconds/60,liveOtSeconds}}
  function groupDashboard(d){const dayMap=new Map((d.days||[]).map(x=>[x.staff_id,x])),sessMap=new Map();for(const s of d.sessions||[]){if(!sessMap.has(s.staff_id))sessMap.set(s.staff_id,[]);sessMap.get(s.staff_id).push(s)}return (d.staff||[]).map(st=>{const day=dayMap.get(st.id)||{operational_date:d.operational_date,break_taken:true,classification:'Day Off - Pending Review',late_minutes:0},sessions=sessMap.get(st.id)||[];return {...day,staff_id:st.id,staff_name:st.name,sections:st.sections||[],sessions}})}
  function status(row){const ss=row.sessions||[],open=ss.some(s=>!s.check_out_at);if(open)return 'On Duty';if(ss.length){const c=row.classification||'';return c&&c!=='Duty'&&c!=='Day Off - Pending Review'?c:'Completed'}return row.classification||'Day Off - Pending Review'}
  function verification(row){if(isReviewRow(row))return 'Review';if(row?.legacy)return 'Previous Record';const ss=row.sessions||[];if(!ss.length)return '—';const okIn=ss.every(x=>x.check_in_verified!==false),completed=ss.filter(x=>x.check_out_at),okOut=completed.every(x=>x.check_out_verified!==false);return okIn&&okOut?'Verified':'Review'}
  function verificationBadge(r){const v=verification(r);if(v==='Verified')return '<span class="live-verify ok">✓ Verified</span>';if(v==='Previous Record')return '<span class="live-verify neutral">Previous Record</span>';if(v==='—')return '—';return '<span class="live-verify bad">! Review</span>'}
  function renderDashboard(){const d=liveState.dashboard;if(!d)return;const rows=groupDashboard(d);let on=0,done=0,late=0,review=0;for(const r of rows){const st=status(r);if(st==='On Duty')on++;if((r.sessions||[]).length&&!r.sessions.some(x=>!x.check_out_at))done++;if(Number(r.late_minutes||0)>0)late++;if(isReviewRow(r))review++}if($('liveDOn'))$('liveDOn').textContent=on;if($('liveDCompleted'))$('liveDCompleted').textContent=done;if($('liveDLate'))$('liveDLate').textContent=late;if($('liveDPending'))$('liveDPending').textContent=review;
    const host=$('liveDashboardRows'),mobile=$('liveDashboardMobileList');const meta=[];const desktop=rows.map(r=>{const c=calc(r),ss=r.sessions||[],first=ss[0],open=ss.some(x=>!x.check_out_at),st=status(r),displaySt=open?'On Duty':(ss.length?'Completed':st),reviewFlag=isReviewRow(r);meta.push({r,c,ss,first,open,displaySt,reviewFlag});return `<tr data-status="${esc(displaySt)}" data-late="${Number(r.late_minutes)||0}" data-review="${reviewFlag?'1':'0'}"><td><strong>${esc(r.staff_name)}</strong>${open?'<span class="live-dot-label"><i></i> LIVE</span>':''}</td><td>${esc(displaySt)}</td><td>${fmtTime(first?.check_in_at)}</td><td>${mins(c.sec/60)}</td><td>${open?(c.remaining>0?mins(c.remaining):`OT ${mins(c.liveOt)}`):'—'}</td><td>${r.late_minutes?`${r.late_minutes} min`:'—'}</td><td>${ss.length}</td><td>${verificationBadge(r)}</td><td>${ss.length?`<button class="btn secondary tiny" onclick="GoyaLiveAdmin.openHistoryForRecord('${r.staff_id}','${r.operational_date}')">${open?'Fix Checkout':'Edit'}</button>`:'—'}</td></tr>`}).join('');if(host)host.innerHTML=desktop;if(mobile)mobile.innerHTML=meta.map(x=>`<article class="live-dashboard-mobile-row" data-status="${esc(x.displaySt)}" data-late="${Number(x.r.late_minutes)||0}" data-review="${x.reviewFlag?'1':'0'}"><header><strong>${x.open?'<i class="live-pulse-dot"></i>':''}${esc(x.r.staff_name)}</strong><em>${esc(x.displaySt)}</em></header><div><span>Check In<b>${fmtTime(x.first?.check_in_at)}</b></span><span>Working<b>${mins(x.c.sec/60)}</b></span><span>${x.open?(x.c.remaining>0?'Remaining':'OT'):'Sessions'}<b>${x.open?(x.c.remaining>0?mins(x.c.remaining):mins(x.c.liveOt)):x.ss.length}</b></span><span>Late<b>${x.r.late_minutes?`${x.r.late_minutes}m`:'—'}</b></span></div>${x.ss.length?`<footer>${verificationBadge(x.r)}<button class="btn secondary tiny" onclick="GoyaLiveAdmin.openHistoryForRecord('${x.r.staff_id}','${x.r.operational_date}')">${x.open?'Fix Checkout':'Edit'}</button></footer>`:''}</article>`).join('');applyDashboardFilter()}
  async function loadDashboard(){try{const date=$('liveDashDate')?.value||new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Dubai'}),d=await rpc('attendance_live_admin_dashboard',{p_token:ctx().token,p_date:date});liveState.dashboard=d;liveState.rules=d.rules||{};liveState.serverOffset=new Date(d.server_now).getTime()-Date.now();renderDashboard();applyDashboardFilter();clearInterval(liveState.timer);liveState.timer=setInterval(renderDashboard,1000)}catch(e){toast(e.message,true)}}
  function classificationOptions(cur){return ['Day Off - Pending Review','Weekly Off','Leave','Sick Leave','Unpaid Leave','Absent','Public Holiday','Other Approved','Duty'].map(x=>`<option${x===cur?' selected':''}>${x}</option>`).join('')}
  function applyMonth(){const m=$('liveHistMonth')?.value;if(!m)return;const [y,mo]=m.split('-').map(Number),end=new Date(y,mo,0).getDate();$('liveHistFrom').value=`${m}-01`;$('liveHistTo').value=`${m}-${pad(end)}`;invalidateHistory()}
  function legacyMinutes(a,b){if(!a||!b)return 0;const x=new Date(a).getTime(),y=new Date(b).getTime();return Number.isFinite(x)&&Number.isFinite(y)&&y>x?(y-x)/60000:0}
  function normalizeLegacyAdmin(payload){return (payload?.rows||[]).map(x=>{const f=x.record||null,r=f||x.submission;if(!r)return null;const off=!!r.day_off,sessions=[];if(!off&&r.punch_in){sessions.push({session_no:1,check_in_at:r.punch_in,check_out_at:r.punch_out||null,check_in_verified:true,check_out_verified:!!r.punch_out,legacy:true});if(r.split_shift&&r.shift2_in)sessions.push({session_no:2,check_in_at:r.shift2_in,check_out_at:r.shift2_out||null,check_in_verified:true,check_out_verified:!!r.shift2_out,legacy:true})}const worked=sessions.reduce((a,s)=>a+legacyMinutes(s.check_in_at,s.check_out_at),0),net=f?.net_work_minutes!=null?Number(f.net_work_minutes):Math.max(0,worked-(r.break_taken===false?0:60)),ot=Math.max(0,Math.floor(net-480));return {operational_date:x.operational_date,staff_id:x.staff_id,staff_name:x.staff_name,break_taken:r.break_taken!==false,classification:off?'Day Off':'Duty',classification_note:r.note||null,late_minutes:Number(f?.late_minutes||r.late_minutes||0),sessions,legacy:true,legacy_precalc:{sec:worked*60,net,ot,target:r.break_taken===false?480:540}}}).filter(Boolean)}
  function mergeAdminHistory(live,legacy){const key=r=>`${r.staff_id}|${r.operational_date}`,lm=new Map(legacy.map(r=>[key(r),r])),out=[];for(const r of live){const k=key(r),has=(r.sessions||[]).length>0||(r.classification&&r.classification!=='Day Off - Pending Review');if(has){out.push(r);lm.delete(k)}else if(lm.has(k)){out.push(lm.get(k));lm.delete(k)}else out.push(r)}for(const r of lm.values())out.push(r);return out.sort((a,b)=>String(b.operational_date).localeCompare(String(a.operational_date))||String(a.staff_name).localeCompare(String(b.staff_name)))}
  let historyRequest=0,historyReady=false;
  async function readRange(from,to,staff){
    if(!from||!to||from>to)throw new Error('Select a valid date range (From must be before To).');
    const args={p_token:ctx().token,p_start:from,p_end:to,p_staff_id:staff||null};
    const [d,l]=await Promise.all([rpc('attendance_live_admin_history',args),rpc('attendance_legacy_admin_history',args)]);
    return {rows:mergeAdminHistory(d.rows||[],normalizeLegacyAdmin(l)),rules:d.rules,server_now:d.server_now};
  }
  function invalidateHistory(){++historyRequest;historyReady=false;liveState.history=[];renderHistory();}
  function historyRangeChanged(){$('liveHistMonth').value='';invalidateHistory();}
  async function loadHistory(){
    invalidateHistory();const request=historyRequest;
    try{const d=await readRange($('liveHistFrom').value,$('liveHistTo').value,$('liveHistStaff').value);
      if(request!==historyRequest)return false;
      liveState.rules=d.rules||liveState.rules;liveState.serverOffset=new Date(d.server_now).getTime()-Date.now();
      liveState.history=d.rows.map(r=>({...r,report_now:d.server_now}));historyReady=true;renderHistory();return true;
    }catch(e){if(request===historyRequest)toast('Report could not be loaded completely: '+e.message,true);return false;}
  }
  function filteredRows(){const filter=$('liveHistStatus')?.value||'',v=$('liveHistVerification')?.value||'';return (liveState.history||[]).filter(r=>(!filter||status(r)===filter||r.classification===filter)&&(!v||verification(r)===v))}
  function summaryFor(rows){const o={days:rows.length,duty:0,weekly:0,leave:0,sick:0,unpaid:0,absent:0,holiday:0,other:0,dayOff:0,pending:0,work:0,net:0,ot:0,lateDays:0,lateMin:0,noBreak:0,split:0,review:0};rows.forEach(r=>{const c=calc(r),ss=r.sessions||[],st=status(r);if(ss.length){o.duty++;o.work+=c.sec/60;o.net+=c.net;o.ot+=c.ot;if(r.break_taken===false)o.noBreak++;if(ss.length>1)o.split++;if(isReviewRow(r))o.review++}if(r.late_minutes){o.lateDays++;o.lateMin+=Number(r.late_minutes)||0}if(st==='Day Off')o.dayOff++;if(st==='Weekly Off')o.weekly++;else if(st==='Leave')o.leave++;else if(st==='Sick Leave')o.sick++;else if(st==='Unpaid Leave')o.unpaid++;else if(st==='Absent')o.absent++;else if(st==='Public Holiday')o.holiday++;else if(st==='Other Approved')o.other++;else if(st==='Day Off - Pending Review')o.pending++});return o}
  function renderSummary(rows){const s=summaryFor(rows),host=$('liveReportSummary');if(host)host.innerHTML=[['Duty',s.duty],['Off',s.weekly+s.dayOff],['Leave',s.leave+s.sick+s.unpaid],['Working',mins(s.work)],['Net',mins(s.net)],['OT',otText(s.ot)],['Late',s.lateDays],['Review',s.review+s.pending]].map(([k,v])=>`<div><span>${k}</span><strong>${v}</strong></div>`).join('');const by=new Map();rows.forEach(r=>{if(!by.has(r.staff_id))by.set(r.staff_id,[]);by.get(r.staff_id).push(r)});const ph=$('livePersonSummary');if(ph)ph.innerHTML=[...by.values()].map(rs=>{const x=summaryFor(rs),r=rs[0];return `<article><strong>${esc(r.staff_name)}</strong><span>Duty <b>${x.duty}</b></span><span>Net <b>${mins(x.net)}</b></span><span>OT <b>${otText(x.ot)}</b></span><span>Late <b>${x.lateDays}</b></span></article>`}).join('')}
  function rowKey(r){return `${r.staff_id}|${r.operational_date}`}
  function reviewReasons(r){
    const reasons=[],ss=r.sessions||[],today=new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Dubai'});
    if(!ss.length&&status(r)==='Day Off - Pending Review')reasons.push('Day Off classification has not been reviewed.');
    ss.forEach((x,i)=>{const label=`Session ${x.session_no||i+1}: `;
      if(!x.check_in_at)reasons.push(label+'Check In time is missing.');
      if(!x.check_out_at&&(r.legacy||r.operational_date<today))reasons.push(label+'Check Out time is missing for an earlier day.');
      if(!r.legacy&&x.check_in_verified===false)reasons.push(label+'Check In is marked unverified in the database.');
      if(!r.legacy&&x.check_out_at&&x.check_out_verified===false)reasons.push(label+'Check Out is marked unverified in the database.');
      if(x.check_in_at&&x.check_out_at&&Date.parse(x.check_out_at)<=Date.parse(x.check_in_at))reasons.push(label+'Check Out is not after Check In. Check both dates and times.');
    });
    return reasons;
  }
  function isReviewRow(r){return reviewReasons(r).length>0;}
  function reviewReasonHtml(r){const reasons=reviewReasons(r);return reasons.length?`<div class="attendance-review-reasons"><strong>Review required</strong><ul>${reasons.map(x=>`<li>${esc(x)}</li>`).join('')}</ul></div>`:'';}
  function renderHistory(){
    const rows=filteredRows();renderSummary(rows);
    const details=r=>`<details><summary>Details</summary><p>${esc(r.classification_note||'No note')}</p>${(r.sessions||[]).map((x,i)=>`<p>Session ${i+1}: ${esc(fmtTime(x.check_in_at))} → ${esc(fmtTime(x.check_out_at))}<br>Check In: ${x.check_in_verified===false?'Review':'Verified'} · Check Out: ${!x.check_out_at?'Pending':x.check_out_verified===false?'Review':'Verified'}</p>`).join('')}</details>`;
    $('liveHistoryAdminRows').innerHTML=rows.map(r=>{const c=calc(r),ss=r.sessions||[];return `<tr><td>${esc(r.operational_date)}</td><td><strong>${esc(r.staff_name)}</strong>${r.legacy?' · Previous':''}</td><td>${ss.map(x=>`${fmtTime(x.check_in_at)} → ${fmtTime(x.check_out_at)}`).join('<br>')||'—'}</td><td>${ss.length}</td><td>${ss.length?mins(c.sec/60):'—'}</td><td>${ss.length?mins(c.net):'—'}</td><td>${otText(c.ot)}</td><td>${Number(r.late_minutes)||0}</td><td>${ss.length?(r.break_taken!==false?'Yes':'No'):'—'}</td><td>${esc(status(r))}</td><td>${verificationBadge(r)}</td><td>${details(r)}</td></tr>`}).join('')||'<tr><td colspan="12">No records. Select filters and Generate.</td></tr>';
    $('liveHistoryMobileCards').innerHTML=rows.map(r=>{const c=calc(r);return `<article class="live-history-admin-card"><header><div><b>${esc(r.staff_name)}</b><span>${esc(r.operational_date)}</span></div><em>${esc(status(r))}</em></header><div class="mobile-metric-grid"><span>Worked<b>${mins(c.sec/60)}</b></span><span>Net<b>${mins(c.net)}</b></span><span>OT<b>${otText(c.ot)}</b></span><span>Late<b>${Number(r.late_minutes)||0}m</b></span></div>${verificationBadge(r)}${details(r)}</article>`}).join('');
  }
  function toLocalInput(v){if(!v)return '';const d=new Date(new Date(v).getTime()+4*3600000);return Number.isNaN(d.getTime())?'':d.toISOString().slice(0,16);}
  function localInputToIso(v){if(!v)return null;const d=new Date(v+'+04:00');if(Number.isNaN(d.getTime()))throw new Error('Invalid UAE date/time.');return d.toISOString();}
  function legacyOutInput(checkIn,checkOut){
    if(!checkOut)return '';
    let i=checkIn?new Date(checkIn):null,o=new Date(checkOut);
    if(i && !Number.isNaN(i.getTime()) && !Number.isNaN(o.getTime()) && o<=i){
      let guard=0;
      while(o<=i && guard<2){o=new Date(o.getTime()+86400000);guard++}
      const dur=(o-i)/3600000;
      if(dur>0 && dur<=24)return toLocalInput(o);
    }
    return toLocalInput(checkOut);
  }
  async function ensureDayInHistory(staffId,date){const d=await readRange(date,date,staffId);return d.rows.find(r=>r.staff_id===staffId&&r.operational_date===date);}

  async function editDay(staffId,date){let r;try{r=await ensureDayInHistory(staffId,date)}catch(e){return toast(e.message,true)};if(!r)return toast('Attendance record not found.',true);editTarget=r;$('liveEditReviewReasons').innerHTML=reviewReasonHtml(r);$('liveEditReviewResult').textContent='';const modal=$('liveEditModal'),list=$('liveEditSessions');$('liveEditBreak').value=r.break_taken===false?'false':'true';$('liveEditBreakSave').classList.toggle('hidden',!!r.legacy);$('liveEditLegacyActions').classList.toggle('hidden',!r.legacy);const ss=r.sessions||[];if(r.legacy){list.innerHTML=[0,1].map((idx)=>{const s=ss[idx],show=idx===0||s;return show?`<div class="live-edit-session legacy-edit-session"><strong>Session ${idx+1}</strong><label>Check In<input type="datetime-local" data-legacy-field="in${idx+1}" value="${toLocalInput(s?.check_in_at)}"></label><label>Check Out<input type="datetime-local" data-legacy-field="out${idx+1}" value="${legacyOutInput(s?.check_in_at,s?.check_out_at)}"></label></div>`:''}).join('')+(!ss[1]?'<button class="btn secondary tiny" onclick="GoyaLiveAdmin.addLegacySecondSession(this)">+ Add Session 2</button>':'')}else{if(!ss.length)return toast('No live session exists for this day.',true);list.innerHTML=ss.map(s=>`<div class="live-edit-session"><strong>Session ${s.session_no}</strong><label>Check In<input type="datetime-local" data-id="${s.id}" data-field="in" value="${toLocalInput(s.check_in_at)}"></label><label>Check Out<input type="datetime-local" data-id="${s.id}" data-field="out" value="${toLocalInput(s.check_out_at)}"></label><button class="btn secondary tiny" onclick="GoyaLiveAdmin.saveSessionEdit('${s.id}',this)">${s.check_out_at?'Save & Recheck':'Set Checkout & Recheck'}</button></div>`).join('')}$('liveEditTitle').textContent=`${r.staff_name} · ${date}${r.legacy?' · Previous Record':''}`;modal.classList.remove('hidden')}
  function addLegacySecondSession(btn){if(!editTarget?.legacy)return;btn.remove();$('liveEditSessions').insertAdjacentHTML('beforeend',`<div class="live-edit-session legacy-edit-session"><strong>Session 2</strong><label>Check In<input type="datetime-local" data-legacy-field="in2"></label><label>Check Out<input type="datetime-local" data-legacy-field="out2"></label></div>`)}
  async function saveEditBreak(){if(!editTarget||controlBusy)return;controlBusy=true;const value=$('liveEditBreak').value==='true';try{await rpc('attendance_live_admin_set_break',{p_token:ctx().token,p_staff_id:editTarget.staff_id,p_date:editTarget.operational_date,p_break_taken:value});toast('Break updated and attendance recalculated.');editTarget.break_taken=value;closeEdit();controlBusy=false;await loadHistory();if(!$('attLiveControl')?.classList.contains('hidden'))await loadControl()}catch(e){toast(e.message,true)}finally{controlBusy=false}}
  async function savePreviousRecordEdit(){
    if(!editTarget?.legacy || previousSaveBusy)return;

    const root=$('liveEditModal')||document;
    const readField=(name)=>{
      const el=root.querySelector(`[data-legacy-field="${name}"]`);
      return el?.value||null;
    };
    const toLocalSafe=(v)=>v?toLocalInput(v):null;
    const ss=Array.isArray(editTarget.sessions)?editTarget.sessions:[];

    let pin=readField('in1')||toLocalSafe(ss[0]?.check_in_at);
    let pout=readField('out1')||legacyOutInput(ss[0]?.check_in_at,ss[0]?.check_out_at)||null;
    let s2in=readField('in2')||toLocalSafe(ss[1]?.check_in_at);
    let s2out=readField('out2')||legacyOutInput(ss[1]?.check_in_at,ss[1]?.check_out_at)||null;
    const br=$('liveEditBreak').value==='true';

    if(!pin)return toast('Session 1 Check In is required.',true);

    const normalizePair=(inVal,outVal,label)=>{
      if(!outVal)return {inVal,outVal:null};
      const i=new Date(inVal);
      let o=new Date(outVal);
      if(Number.isNaN(i.getTime())||Number.isNaN(o.getTime()))throw new Error(`${label}: invalid date/time.`);
      let guard=0;
      while(o<=i && guard<2){o=new Date(o.getTime()+86400000);guard++}
      const hours=(o-i)/3600000;
      if(o<=i || hours<=0 || hours>24)throw new Error(`${label}: Check Out must be after Check In and within 24 hours.`);
      const z=n=>String(n).padStart(2,'0');
      const local=`${o.getFullYear()}-${z(o.getMonth()+1)}-${z(o.getDate())}T${z(o.getHours())}:${z(o.getMinutes())}`;
      return {inVal,outVal:local};
    };

    const btn=document.querySelector('#liveEditLegacyActions .btn.success');
    try{
      previousSaveBusy=true;
      if(btn){btn.disabled=true;btn.textContent='Saving...';}

      ({inVal:pin,outVal:pout}=normalizePair(pin,pout,'Session 1'));
      if((s2in&&!s2out)||(!s2in&&s2out))throw new Error('Session 2 requires both Check In and Check Out.');
      if(s2in)({inVal:s2in,outVal:s2out}=normalizePair(s2in,s2out,'Session 2'));

      await rpc('attendance_live_admin_update_previous_record',{
        p_token:ctx().token,
        p_staff_id:editTarget.staff_id,
        p_date:editTarget.operational_date,
        p_punch_in:localInputToIso(pin),
        p_punch_out:pout?localInputToIso(pout):null,
        p_break_taken:br,
        p_split_shift:!!s2in,
        p_shift2_in:s2in?localInputToIso(s2in):null,
        p_shift2_out:s2out?localInputToIso(s2out):null,
        p_note:editTarget.classification_note||null
      });

      toast('Previous record saved and recalculated.');
      closeEdit();
      await loadHistory();
      if(!$('attLiveControl')?.classList.contains('hidden'))await loadControl();
    }catch(e){
      toast(e.message||'Could not save previous record.',true);
    }finally{
      previousSaveBusy=false;
      if(btn){btn.disabled=false;btn.textContent='Save Previous Record';}
    }
  }
  async function saveSessionEdit(id,btn){
    if(btn.disabled||controlBusy||!editTarget)return;
    const target={staff_id:editTarget.staff_id,operational_date:editTarget.operational_date},box=btn.closest('.live-edit-session'),pin=box.querySelector('[data-field="in"]').value,pout=box.querySelector('[data-field="out"]').value;
    if(!pout&&!confirm('Check Out is blank. Save this session as incomplete?'))return;
    let saved=false;
    try{
      if(!pin)throw new Error('Check In is required.');
      if(pout&&localInputToIso(pout)<=localInputToIso(pin))throw new Error('Check Out must be after Check In.');
      btn.disabled=true;controlBusy=true;
      await rpc('attendance_live_admin_update_session',{p_token:ctx().token,p_session_id:id,p_check_in:localInputToIso(pin),p_check_out:localInputToIso(pout)});
      saved=true;invalidateHistory();
      const fresh=await ensureDayInHistory(target.staff_id,target.operational_date);
      if(!fresh)throw new Error('The saved record could not be reloaded.');
      const reasons=reviewReasons(fresh);editTarget=fresh;
      $('liveEditReviewReasons').innerHTML=reviewReasonHtml(fresh);
      $('liveEditReviewResult').textContent=reasons.length?'Saved. Review is still required for the reasons above. If times are correct but verification remains unverified, database-side admin approval support needs to be checked.':'Saved. No outstanding review reasons remain.';
      toast(reasons.length?'Saved; review is still required.':'Saved; review resolved.');
      controlBusy=false;
      if(!$('attLiveControl')?.classList.contains('hidden'))await loadControl();
      if(!$('attLiveDashboard')?.classList.contains('hidden'))await loadDashboard();
    }catch(e){const message=saved?'Saved, but review status could not be checked. Refresh before taking another action. '+e.message:e.message;$('liveEditReviewResult').textContent=message;toast(message,true);}
    finally{btn.disabled=false;controlBusy=false;}
  }
  function closeEdit(){$('liveEditModal')?.classList.add('hidden');editTarget=null}
  function reportGroups(rows){const by=new Map();rows.forEach(r=>{const id=r.staff_id||r.staff_name;if(!by.has(id))by.set(id,[]);by.get(id).push(r)});return [...by.values()]}
  function reportSorted(rows){return [...rows].sort((a,b)=>String(a.operational_date).localeCompare(String(b.operational_date))||String(a.staff_name).localeCompare(String(b.staff_name)))}
  function reportReview(r){return isReviewRow(r)?'Pending review':(r.legacy?'Previous record':(r.sessions||[]).length?verification(r):'Classified')}
  function detailRows(rows=filteredRows()){return reportSorted(rows).map(r=>{const c=calc(r),ss=r.sessions||[];return {'Date':r.operational_date,'Staff':r.staff_name,'Shift Sessions':ss.length,'Session Details':ss.map((s,i)=>`Shift ${s.session_no||i+1}: ${fmtTime(s.check_in_at)} - ${fmtTime(s.check_out_at)}`).join(' | '),'Worked':ss.length?mins(c.sec/60):'','Net':ss.length?mins(c.net):'','OT':c.ot?otText(c.ot):'','Late Minutes':r.late_minutes||0,'Break Taken':ss.length?(r.break_taken!==false?'Yes':'No'):'','Status':status(r),'Verification':verification(r),'Review Status':reportReview(r),'Review Reasons':reviewReasons(r).join('\n'),'Note':r.classification_note||''}})}
  function safeName(v){return String(v||'All_Staff').replace(/[^a-z0-9]+/gi,'_').replace(/^_|_$/g,'')||'All_Staff'}
  function reportFileBase(ext){const staffSel=$('liveHistStaff'),staff=staffSel?.value?staffSel.options[staffSel.selectedIndex]?.text:'All_Staff',from=$('liveHistFrom').value,to=$('liveHistTo').value;return `Goya_Live_Attendance_${safeName(staff)}_${from}_to_${to}_${safeName($('liveHistStatus')?.value||'All_Status')}_${safeName($('liveHistVerification')?.value||'All_Verification')}.${ext}`}
  function reportFilterText(otOnly=false){return `Status: ${$('liveHistStatus')?.value||'All'} | Verification: ${$('liveHistVerification')?.value||'All'}${otOnly?' | OT-matching staff; full selected-period timetable included.':''}`}
  function summarySheetRows(rows){return reportGroups(rows).map(rs=>{const x=summaryFor(rs),r=rs[0];return {'Staff':r.staff_name,'From':$('liveHistFrom').value,'To':$('liveHistTo').value,'Duty Days':x.duty,'Weekly Off':x.weekly,'Previous Day Off':x.dayOff,'Leave':x.leave,'Sick Leave':x.sick,'Unpaid Leave':x.unpaid,'Total Leave':x.leave+x.sick+x.unpaid,'Absent':x.absent,'Public Holiday':x.holiday,'Other Approved':x.other,'Pending Day Off Review':x.pending,'Working Hours':mins(x.work),'Net Hours':mins(x.net),'OT':otText(x.ot),'OT Minutes':x.ot,'OT Days':rs.filter(r=>calc(r).ot>0).length,'Late Days':x.lateDays,'Late Minutes':x.lateMin,'Break Days':rs.filter(r=>(r.sessions||[]).length&&r.break_taken!==false).length,'No Break Days':x.noBreak,'Split Shift Days':x.split,'Attendance Review Required':rs.filter(isReviewRow).length,'Weekly Off with Notes':rs.filter(r=>status(r)==='Weekly Off'&&String(r.classification_note||'').trim()).length,'Records Shown':rs.length}})}
  function reportSummaryPairs(rs){const s=summarySheetRows(rs)[0],pairs=[['Duty Days','Weekly Off'],['Leave','Sick Leave'],['Unpaid Leave','Total Leave'],['Absent','Public Holiday'],['Other Approved','Previous Day Off'],['Pending Day Off Review','Attendance Review Required'],['Working Hours','Net Hours'],['OT','OT Days'],['Late Days','Late Minutes'],['Break Days','No Break Days'],['Split Shift Days','Records Shown'],['Weekly Off with Notes','OT Minutes']];return pairs.map(([a,b])=>[a,s[a],b,s[b]])}
  function reportReviewRows(rows){return reportSorted(rows).filter(r=>!(r.sessions||[]).length||isReviewRow(r)).map(r=>({'Date':r.operational_date,'Staff':r.staff_name,'Classification':status(r),'Review Status':reportReview(r),'Review Reasons':reviewReasons(r).join('\n'),'Review Note':r.classification_note||''}))}
  function reportSheetFormat(ws,widths,headers=[0],sections=[]){ws['!cols']=widths.map(wch=>({wch}));if(!ws['!ref'])return ws;const end=XLSX.utils.decode_range(ws['!ref']).e,border={style:'thin',color:{rgb:'D5DFDA'}};ws['!rows']=ws['!rows']||[];for(let r=0;r<=end.r;r++){let lines=1;for(let c=0;c<=end.c;c++){const addr=XLSX.utils.encode_cell({r,c}),cell=ws[addr]||(ws[addr]={t:'s',v:''}),heading=headers.includes(r)||sections.includes(r);cell.s={font:{name:'Calibri',sz:r===0&&sections.includes(0)?16:11,bold:heading,color:{rgb:heading?'FFFFFF':'24392F'}},fill:{fgColor:{rgb:heading?'24392F':r%2?'F2F7F4':'FFFFFF'}},border:{top:border,bottom:border,left:border,right:border},alignment:{vertical:'center',horizontal:cell.t==='n'?'right':'left',wrapText:true}};lines=Math.max(lines,...String(cell.v??'').split('\n').map(t=>Math.ceil(t.length/Math.max(10,(widths[c]||20)-2))));}if(!ws['!rows'][r])ws['!rows'][r]={hpt:Math.min(409,Math.max(headers.includes(r)||sections.includes(r)?30:23,lines*14+6))};}return ws}
  function reportJsonSheet(rows){const ws=XLSX.utils.json_to_sheet(rows),keys=Object.keys(rows[0]||{});reportSheetFormat(ws,keys.map(k=>/Note|Reasons|Details/.test(k)?55:/Staff|Classification|Status/.test(k)?24:18));if(rows.length)ws['!autofilter']={ref:ws['!ref']};return ws}
  function reportStaffSheet(rs,otOnly){const name=rs[0].staff_name,period=`${$('liveHistFrom').value} to ${$('liveHistTo').value}`,aoa=[],merges=[],rowHeights=[],headers=[],sections=[];
    const merge=(row,a,b)=>merges.push({s:{r:row,c:a},e:{r:row,c:b}});
    const full=(text)=>{const row=aoa.length;sections.push(row);aoa.push([text]);merge(row,0,13);rowHeights[row]={hpt:30}};
    const meta=(label,value)=>{const row=aoa.length,a=Array(14).fill('');a[0]=label;a[3]=value;aoa.push(a);merge(row,0,2);merge(row,3,13);rowHeights[row]={hpt:22}};
    full(otOnly?'GOYA - Overtime Staff Attendance':'GOYA - Staff Attendance');meta('Staff',name);meta('Period',period);meta('Filters / scope',reportFilterText(otOnly));
    full('Staff Summary');for(const pair of reportSummaryPairs(rs)){const row=aoa.length,a=Array(14).fill('');[a[0],a[3],a[7],a[10]]=pair;aoa.push(a);for(const [lo,hi]of [[0,2],[3,6],[7,9],[10,13]])merge(row,lo,hi);rowHeights[row]={hpt:22}}
    const reviews=reportReviewRows(rs);if(reviews.length){aoa.push([]);full('Day Off / Leave / Review Details');const row=aoa.length,a=Array(14).fill('');headers.push(row);[a[0],a[3],a[7],a[10]]=['Date','Classification','Review','Note / reason'];aoa.push(a);for(const [lo,hi]of [[0,2],[3,6],[7,9],[10,13]])merge(row,lo,hi);for(const r of reviews){const row=aoa.length,a=Array(14).fill('');[a[0],a[3],a[7],a[10]]=[r.Date,r.Classification,r['Review Status'],[r['Review Note'],r['Review Reasons']].filter(Boolean).join('\n')];aoa.push(a);for(const [lo,hi]of [[0,2],[3,6],[7,9],[10,13]])merge(row,lo,hi);rowHeights[row]={hpt:Math.min(180,Math.max(24,Math.ceil(String(a[10]).length/90)*15))}}}
    aoa.push([]);full('Daily Timetable - Selected Period');const detail=detailRows(rs);headers.push(aoa.length);aoa.push(Object.keys(detail[0]||{}));detail.forEach(r=>aoa.push(Object.values(r)));
    const ws=XLSX.utils.aoa_to_sheet(aoa);ws['!merges']=merges;ws['!rows']=rowHeights;reportSheetFormat(ws,[13,23,12,42,16,16,13,14,14,25,24,24,55,55],headers,sections);if(ws['!ref'])for(let r=5;r<17;r++)for(let c=0;c<14;c++){const cell=ws[XLSX.utils.encode_cell({r,c})];if(!cell?.s)continue;cell.s.alignment.horizontal='left';cell.s.font.bold=c>=3&&c<=6||c>=10;cell.s.fill.fgColor.rgb=c<3||c>=7&&c<10?'E6EFE9':'FFFFFF';}return ws;
  }
  function appendReportSheets(wb,rows,otOnly){XLSX.utils.book_append_sheet(wb,reportJsonSheet(summarySheetRows(rows)),otOnly?'Staff Summary':'Summary');XLSX.utils.book_append_sheet(wb,reportJsonSheet(detailRows(rows)),'Daily Details');const reviews=reportReviewRows(rows);if(reviews.length)XLSX.utils.book_append_sheet(wb,reportJsonSheet(reviews),'Leave and Review Details');for(const rs of reportGroups(rows)){const base=safeName(rs[0].staff_name).slice(0,31)||'Staff';let nm=base,i=2;while(wb.SheetNames.some(x=>x.toLowerCase()===nm.toLowerCase())){const suffix='_'+i++;nm=base.slice(0,31-suffix.length)+suffix}XLSX.utils.book_append_sheet(wb,reportStaffSheet(rs,otOnly),nm)}}
  function exportExcel(){if(!historyReady)return toast('Generate the report for the selected filters first.',true);const rows=filteredRows();if(!rows.length)return toast('Load history first.',true);if(!window.XLSX)return toast('Excel library is still loading.',true);const wb=XLSX.utils.book_new();appendReportSheets(wb,rows,false);(window.GoyaReportXLSX||XLSX).writeFile(wb,reportFileBase('xlsx'))}
  function reportPdfHeader(doc,name,otOnly){doc.setFont?.('helvetica','bold');doc.setFontSize(16);doc.text(otOnly?'GOYA - Overtime Staff Attendance':'GOYA - Live Attendance Report',14,14);doc.setFontSize(11);doc.text('Staff: '+String(name),14,22);doc.setFont?.('helvetica','normal');doc.setFontSize(9);doc.text(`Period: ${$('liveHistFrom').value} to ${$('liveHistTo').value} (UAE)`,14,29);doc.setFontSize(7.5);doc.text(reportFilterText(otOnly),14,35)}
  function reportPdfTable(doc,opts,name,otOnly){doc.autoTable({theme:'grid',rowPageBreak:'avoid',margin:{top:42,bottom:15,left:14,right:14},styles:{font:'helvetica',fontSize:7.5,cellPadding:2,overflow:'linebreak',valign:'middle'},headStyles:{fillColor:[36,57,49],textColor:255,fontStyle:'bold'},alternateRowStyles:{fillColor:[247,249,248]},didDrawPage:()=>reportPdfHeader(doc,name,otOnly),...opts});return doc.lastAutoTable?.finalY||opts.startY+8+(opts.body?.length||0)*6}
  function reportPdfSection(doc,y,title,name,otOnly){const height=doc.internal?.pageSize?.getHeight?.()||210;if(y>height-45){doc.addPage?.();y=44}doc.setFont?.('helvetica','bold');doc.setFontSize(10);doc.text(title,14,y);doc.setFont?.('helvetica','normal');return y+4}
  function reportStaffPDF(doc,rs,otOnly){const name=rs[0].staff_name;reportPdfHeader(doc,name,otOnly);let y=reportPdfTable(doc,{startY:42,head:[['Summary','Value','Summary','Value']],body:[['Staff',name,'Period',`${$('liveHistFrom').value} to ${$('liveHistTo').value}`],...reportSummaryPairs(rs)],styles:{fontSize:8.5,cellPadding:2.2,overflow:'linebreak'},columnStyles:{0:{cellWidth:70},1:{cellWidth:63},2:{cellWidth:70},3:{cellWidth:66}}},name,otOnly);
    const reviews=reportReviewRows(rs);if(reviews.length){y=reportPdfSection(doc,y+8,'Day Off / Leave / Review Details',name,otOnly);y=reportPdfTable(doc,{startY:y,head:[['Date','Classification','Review','Note / reason']],body:reviews.map(r=>[r.Date,r.Classification,r['Review Status'],[r['Review Note'],r['Review Reasons']].filter(Boolean).join('\n')||'-']),columnStyles:{0:{cellWidth:23},1:{cellWidth:36},2:{cellWidth:32},3:{cellWidth:178}}},name,otOnly)}
    y=reportPdfSection(doc,y+8,'Daily Timetable - Selected Period',name,otOnly);reportPdfTable(doc,{startY:y,head:[['Date','Sessions','Working Time','Worked','Net','OT','Late','Break','Status','Review / Verification','Note']],body:reportSorted(rs).map(r=>{const c=calc(r),ss=r.sessions||[];return[r.operational_date,ss.length,ss.length?ss.map((x,i)=>`${ss.length>1?'S'+(x.session_no||i+1)+': ':''}${fmtTime(x.check_in_at)} - ${fmtTime(x.check_out_at)}`).join('\n'):'-',ss.length?mins(c.sec/60):'-',ss.length?mins(c.net):'-',c.ot?otText(c.ot):'-',r.late_minutes?`${r.late_minutes} min`:'-',ss.length?(r.break_taken!==false?'Yes':'No'):'-',status(r),[reportReview(r),...reviewReasons(r)].join('\n'),r.classification_note||'-']}),columnStyles:{0:{cellWidth:20},1:{cellWidth:16,halign:'center'},2:{cellWidth:39},3:{cellWidth:16},4:{cellWidth:16},5:{cellWidth:14},6:{cellWidth:12},7:{cellWidth:12},8:{cellWidth:27},9:{cellWidth:39},10:{cellWidth:58}}},name,otOnly);
  }
  function reportPdfPages(doc){const n=doc.getNumberOfPages?.()||1;for(let i=1;i<=n;i++){doc.setPage?.(i);doc.setFont?.('helvetica','normal');doc.setFontSize(8);doc.text(`Page ${i} of ${n}`,14,(doc.internal?.pageSize?.getHeight?.()||210)-7)}}
  function exportPDF(){if(!historyReady)return toast('Generate the report for the selected filters first.',true);const rows=filteredRows();if(!rows.length)return toast('Load history first.',true);if(!window.jspdf?.jsPDF)return toast('PDF library is still loading.',true);const doc=new window.jspdf.jsPDF({orientation:'landscape'});let first=true;for(const rs of reportGroups(rows)){if(!first)doc.addPage();first=false;reportStaffPDF(doc,rs,false)}reportPdfPages(doc);doc.save(reportFileBase('pdf'))}
  function overtimeReportRows(){const ids=new Set(filteredRows().filter(r=>calc(r).ot>0).map(r=>r.staff_id||r.staff_name));return liveState.history.filter(r=>ids.has(r.staff_id||r.staff_name))}
  function overtimeSummaryRows(rows=filteredRows()){const by=new Map();for(const r of rows){const c=calc(r);if(c.ot<=0)continue;const id=r.staff_id||r.staff_name;if(!by.has(id))by.set(id,{staff:r.staff_name,ot:0,days:0});const x=by.get(id);x.ot+=c.ot;x.days++}return [...by.values()].sort((a,b)=>b.ot-a.ot)}
  function overtimeFileBase(ext){const staffSel=$('liveHistStaff'),staff=staffSel?.value?staffSel.options[staffSel.selectedIndex]?.text:'All_Staff',from=$('liveHistFrom').value,to=$('liveHistTo').value;return `Goya_Overtime_Only_${safeName(staff)}_${from}_to_${to}_${safeName($('liveHistStatus')?.value||'All_Status')}_${safeName($('liveHistVerification')?.value||'All_Verification')}.${ext}`}
  function exportOvertimeExcel(){if(!historyReady)return toast('Generate the report for the selected filters first.',true);const rows=overtimeReportRows(),data=overtimeSummaryRows(rows);if(!data.length)return toast('No overtime found for the selected period.',true);if(!window.XLSX)return toast('Excel library is still loading.',true);const overview=data.map(x=>({'Staff':x.staff,'OT Days':x.days,'Total OT':otText(x.ot),'OT Minutes':x.ot})),wb=XLSX.utils.book_new();XLSX.utils.book_append_sheet(wb,reportJsonSheet(overview),'Overtime Summary');appendReportSheets(wb,rows,true);(window.GoyaReportXLSX||XLSX).writeFile(wb,overtimeFileBase('xlsx'))}
  function exportOvertimePDF(){if(!historyReady)return toast('Generate the report for the selected filters first.',true);const rows=overtimeReportRows(),data=overtimeSummaryRows(rows);if(!data.length)return toast('No overtime found for the selected period.',true);if(!window.jspdf?.jsPDF)return toast('PDF library is still loading.',true);const doc=new window.jspdf.jsPDF({orientation:'landscape'}),from=$('liveHistFrom').value,to=$('liveHistTo').value,total=data.reduce((a,x)=>a+x.ot,0);doc.setFontSize(18);doc.text('GOYA - Overtime Summary',14,16);doc.autoTable({startY:24,theme:'grid',head:[['Report details','Value']],body:[['Period',`${from} to ${to}`],['Staff with OT',data.length],['Total OT',otText(total)],['Scope',reportFilterText(true)]],styles:{fontSize:9,cellPadding:2.5},headStyles:{fillColor:[36,57,49]},margin:{left:14,right:14}});doc.autoTable({startY:(doc.lastAutoTable?.finalY||62)+8,theme:'grid',head:[['Staff','OT Days','Total OT']],body:data.map(x=>[x.staff,x.days,otText(x.ot)]),styles:{fontSize:9,cellPadding:2.5},headStyles:{fillColor:[36,57,49]},margin:{left:14,right:14}});for(const rs of reportGroups(rows)){doc.addPage?.();reportStaffPDF(doc,rs,true)}reportPdfPages(doc);doc.save(overtimeFileBase('pdf'))}
  async function getPublicIp(){for(const url of ['https://api.ipify.org?format=json','https://api64.ipify.org?format=json']){try{const r=await fetch(url,{cache:'no-store'});if(r.ok){const j=await r.json();if(j.ip)return j.ip}}catch{}}throw new Error('Could not detect public IP.')}
  function getGps(){return new Promise((resolve,reject)=>navigator.geolocation?navigator.geolocation.getCurrentPosition(p=>resolve({lat:p.coords.latitude,lon:p.coords.longitude,accuracy:p.coords.accuracy}),e=>reject(new Error(e.code===1?'Allow location permission first.':'Could not get GPS.')),{enableHighAccuracy:true,timeout:15000}):reject(new Error('GPS unsupported.')))}
  function renderLocations(){const host=$('liveLocationList');if(!host)return;host.innerHTML=liveState.settingsLocations.length?liveState.settingsLocations.map((l,i)=>`<div class="live-location-row"><div><strong>${esc(l.name||'Workplace')}</strong><span>${Number(l.lat).toFixed(6)}, ${Number(l.lon).toFixed(6)} · ${l.radius_m||150}m</span></div><button class="btn danger tiny" onclick="GoyaLiveAdmin.removeLocation(${i})">Remove</button></div>`).join(''):'<div class="live-empty">No workplace location configured yet.</div>'}
  function updateLiveRuleState(){const split=$('liveSplitShiftEnabled')?.checked!==false,br=$('liveAllowBreakSelection')?.checked!==false;if($('liveSplitRuleState'))$('liveSplitRuleState').textContent=`Split Shift: ${split?'Enabled':'Disabled'}`;if($('liveBreakRuleState'))$('liveBreakRuleState').textContent=`Break Selection: ${br?'Enabled':'Disabled'}`}
  async function loadSettings(){try{const r=await rpc('attendance_live_admin_settings',{p_token:ctx().token})||{};liveState.rules=r;liveState.settingsLocations=Array.isArray(r.locations)?r.locations:[];if($('liveOvertimeEnabled'))$('liveOvertimeEnabled').checked=r.overtime_enabled!==false;if($('liveForceNoBreak'))$('liveForceNoBreak').checked=r.force_no_break===true;if($('liveRequireLocation'))$('liveRequireLocation').checked=r.require_location!==false;if($('liveRequireNetwork'))$('liveRequireNetwork').checked=r.require_network!==false;if($('liveSplitShiftEnabled'))$('liveSplitShiftEnabled').checked=r.split_shift_enabled!==false;if($('liveAllowBreakSelection'))$('liveAllowBreakSelection').checked=r.allow_break_selection!==false;if($('liveDefaultBreakTaken'))$('liveDefaultBreakTaken').value=r.default_break_taken===false?'false':'true';if($('liveDutyHours'))$('liveDutyHours').value=(Number(r.duty_presence_minutes)||540)/60;if($('liveBreakMinutes'))$('liveBreakMinutes').value=Number(r.break_minutes??60);if($('liveApprovedIps'))$('liveApprovedIps').value=(Array.isArray(r.approved_public_ips)?r.approved_public_ips:[]).join('\n');renderLocations();updateLiveRuleState();$('liveSplitShiftEnabled')?.addEventListener('change',updateLiveRuleState,{once:false});$('liveAllowBreakSelection')?.addEventListener('change',updateLiveRuleState,{once:false})}catch(e){toast(e.message,true)}}
  async function setOvertime(input){const previous=liveState.rules.overtime_enabled!==false;input.disabled=true;try{liveState.rules=await rpc('attendance_live_admin_save_settings',{p_token:ctx().token,p_value:{overtime_enabled:input.checked}});input.checked=liveState.rules.overtime_enabled!==false;toast(input.checked?'Overtime enabled for ongoing and new duty.':'Overtime disabled for ongoing and new duty. Check Out remains available.');}catch(e){input.checked=previous;toast(e.message,true)}finally{input.disabled=false}}
  async function detectLocation(){try{const g=await getGps();$('liveLocLat').value=g.lat.toFixed(7);$('liveLocLon').value=g.lon.toFixed(7);toast(`GPS captured ±${Math.round(g.accuracy||0)}m`)}catch(e){toast(e.message,true)}}
  async function detectIp(){try{const ip=await getPublicIp(),box=$('liveApprovedIps'),ips=box.value.split(/\s+/).filter(Boolean);if(!ips.includes(ip))ips.push(ip);box.value=ips.join('\n');toast(`Current public IP added: ${ip}`)}catch(e){toast(e.message,true)}}
  function addLocation(){const name=$('liveLocName').value.trim()||'Workplace',lat=+$('liveLocLat').value,lon=+$('liveLocLon').value,radius=+$('liveLocRadius').value||150;if(!Number.isFinite(lat)||!Number.isFinite(lon))return toast('Capture or enter valid GPS coordinates.',true);liveState.settingsLocations.push({name,lat,lon,radius_m:radius,active:true});$('liveLocName').value='';renderLocations()}
  function removeLocation(i){liveState.settingsLocations.splice(i,1);renderLocations()}
  async function saveSettings(){const ips=[...new Set($('liveApprovedIps').value.split(/\s+/).map(x=>x.trim()).filter(Boolean))],value={overtime_enabled:$('liveOvertimeEnabled')?.checked!==false,force_no_break:$('liveForceNoBreak')?.checked===true,require_location:$('liveRequireLocation').checked,require_network:$('liveRequireNetwork').checked,split_shift_enabled:$('liveSplitShiftEnabled')?$('liveSplitShiftEnabled').checked:true,allow_break_selection:$('liveAllowBreakSelection')?$('liveAllowBreakSelection').checked:true,default_break_taken:$('liveDefaultBreakTaken')?$('liveDefaultBreakTaken').value!=='false':true,duty_presence_minutes:Math.round((+$('liveDutyHours').value||9)*60),regular_net_minutes:480,break_minutes:$('liveBreakMinutes').value===''?60:Math.max(0,Number($('liveBreakMinutes').value)),late_grace_minutes:15,operational_cutoff:liveState.rules.operational_cutoff||'04:00',shift_start_times:liveState.rules.shift_start_times||['08:00','09:00','10:00','11:00','12:00','13:00','14:00','15:00','16:00','17:00'],locations:liveState.settingsLocations,approved_public_ips:ips};try{liveState.rules=await rpc('attendance_live_admin_save_settings',{p_token:ctx().token,p_value:value});updateLiveRuleState();toast('Live Attendance settings saved. Staff My Attendance will use the new Split Shift/Break rules after refresh.')}catch(e){toast(e.message,true)}}
  function fillStaffFilter(){const sel=$('liveHistStaff'),staff=ctx().staff||[];if(sel&&!sel.dataset.ready){sel.innerHTML='<option value="">All Staff</option>'+staff.map(s=>`<option value="${esc(s.portal_staff_id||s.id)}">${esc(s.name)}</option>`).join('');sel.dataset.ready='1'}}

  function setDashboardFilter(filter){dashboardFilter=filter||'';document.querySelectorAll('.live-stat-btn').forEach(x=>x.classList.toggle('active-filter',!!dashboardFilter&&x.dataset.filter===dashboardFilter));const label=$('liveDashboardFilterLabel');if(label)label.textContent=dashboardFilter?`Filtered: ${dashboardFilter}`:'Showing all staff';applyDashboardFilter()}
  function applyDashboardFilter(){const match=el=>{if(!dashboardFilter)return true;if(dashboardFilter==='Late')return Number(el.dataset.late||0)>0;if(dashboardFilter==='Review')return el.dataset.review==='1';if(dashboardFilter==='Completed')return el.dataset.status==='Completed';return el.dataset.status===dashboardFilter};document.querySelectorAll('#liveDashboardRows tr,#liveDashboardMobileList .live-dashboard-mobile-row').forEach(r=>r.hidden=!match(r))}
  let controlRows=[],controlMarks=new Set(),controlBusy=false,controlRequest=0,batchPlan=[];
  function setControlFilter(filter){controlFilter=filter||'';controlMarks.clear();renderControl();}
  function visibleControlRows(){const staff=$('liveControlStaff')?.value||'';return controlRows.filter(r=>(!staff||r.staff_id===staff)&&(!controlFilter||(controlFilter==='Review'?isReviewRow(r):controlFilter==='Completed'?(r.sessions||[]).length&&status(r)!=='On Duty':status(r)===controlFilter)));}
  function toggleControlMark(key,on){on?controlMarks.add(key):controlMarks.delete(key);$('controlMarkedCount').textContent=`${controlMarks.size} selected`;}
  function markControlAll(on){visibleControlRows().forEach(r=>toggleControlMark(rowKey(r),on));renderControl();}
  function clearControlMarks(){controlMarks.clear();renderControl();}
  function controlAction(index,action){const r=visibleControlRows()[index];if(!r||controlBusy)return;if(action==='edit')return editDay(r.staff_id,r.operational_date);openManualControl(r.staff_id,r.staff_name,action,r.operational_date);}
  function renderControl(){
    const rows=visibleControlRows(),staff=$('liveControlStaff')?.value||'',base=controlRows.filter(r=>!staff||r.staff_id===staff);
    $('liveControlSummary').innerHTML=[['On Duty',base.filter(r=>status(r)==='On Duty').length,'On Duty'],['Shift Done',base.filter(r=>(r.sessions||[]).length&&status(r)!=='On Duty').length,'Completed'],['Review',base.filter(isReviewRow).length,'Review']].map(([label,count,filter])=>`<button class="live-control-stat ${controlFilter===filter?'active-filter':''}" onclick="GoyaLiveAdmin.setControlFilter('${filter}')"><span>${label}</span><strong>${count}</strong></button>`).join('')+`<button class="live-control-clear" onclick="GoyaLiveAdmin.setControlFilter('')">All</button>`;
    $('controlMarkedCount').textContent=`${controlMarks.size} selected`;
    $('controlMarkAll').checked=rows.length>0&&rows.every(r=>controlMarks.has(rowKey(r)));
    $('liveControlList').innerHTML=rows.map((r,i)=>{const ss=r.sessions||[],c=calc(r),open=status(r)==='On Duty';return `<div class="live-control-row ${open?'on-duty':''}"><div class="control-staff"><label><input type="checkbox" ${controlMarks.has(rowKey(r))?'checked':''} onchange="GoyaLiveAdmin.toggleControlMark('${rowKey(r)}',this.checked)"> <strong>${esc(r.staff_name)}</strong></label><span>${esc(r.operational_date)} · ${esc(status(r))}${r.legacy?' · Previous':''}</span></div><div><small>Check In</small><b>${fmtTime(ss[0]?.check_in_at)}</b></div><div><small>Check Out</small><b data-checkout>${fmtTime(lastCheckout(ss))}</b></div><div><small>Working / Net</small><b data-control-clock="${i}">${mins(c.sec/60)} / ${mins(c.net)}</b></div><div><small>OT / Late</small><b data-control-ot="${i}">${otText(c.ot)} / ${Number(r.late_minutes)||0}m</b></div><div>${isReviewRow(r)?'<span class="live-verify bad">! Review</span>':verificationBadge(r)}</div><div class="control-actions">${!r.legacy?`<button class="btn success tiny" ${open?'disabled':''} onclick="GoyaLiveAdmin.controlAction(${i},'${ss.length?'REJOIN':'CHECK_IN'}')">${ss.length?'Rejoin':'Check In'}</button><button class="btn danger tiny" ${open?'':'disabled'} onclick="GoyaLiveAdmin.controlAction(${i},'CHECK_OUT')">Check Out</button>`:''}${ss.length?`<button class="btn secondary tiny" onclick="GoyaLiveAdmin.controlAction(${i},'edit')">${isReviewRow(r)?'Review / Correct':'Edit / Break'}</button>`:!r.legacy?`<button class="btn secondary tiny" onclick="GoyaLiveAdmin.reviewOne(${i})">Review Day Off</button>`:''}</div>${reviewReasonHtml(r)}</div>`}).join('')||'<div class="live-empty">No records for these filters.</div>';
  }
  function updateControlClock(){
    if($('attLiveControl')?.classList.contains('hidden'))return;
    visibleControlRows().forEach((r,i)=>{const c=calc(r),clock=document.querySelector(`[data-control-clock="${i}"]`),ot=document.querySelector(`[data-control-ot="${i}"]`);if(clock)clock.textContent=`${mins(c.sec/60)} / ${mins(c.net)}`;if(ot)ot.textContent=`${otText(c.ot)} / ${Number(r.late_minutes)||0}m`;});
  }
  async function loadControl(){
    if(controlBusy)return;
    const request=++controlRequest;clearInterval(liveState.timer);controlRows=[];controlMarks.clear();renderControl();
    try{const from=$('liveControlFrom').value,to=$('liveControlDate').value,d=await readRange(from,to,null);if(request!==controlRequest)return;
      liveState.rules=d.rules||liveState.rules;liveState.serverOffset=new Date(d.server_now).getTime()-Date.now();controlRows=d.rows;
      const sel=$('liveControlStaff'),cur=sel.value,staff=new Map((ctx().staff||[]).map(r=>[r.portal_staff_id||r.id,r.name]));controlRows.forEach(r=>staff.set(r.staff_id,r.staff_name));sel.innerHTML='<option value="">All Staff</option>'+[...staff].map(([id,name])=>`<option value="${esc(id)}">${esc(name)}</option>`).join('');sel.value=cur;renderControl();liveState.timer=setInterval(updateControlClock,1000);
    }catch(e){toast('Control records could not be loaded: '+e.message,true);}
  }
  function reviewOne(index){const r=visibleControlRows()[index];if(!r)return;controlMarks=new Set([rowKey(r)]);renderControl();previewBatch('classification');}
  function previewBatch(kind){
    if(controlBusy)return;
    const rows=visibleControlRows().filter(r=>controlMarks.has(rowKey(r)));
    if(!rows.length)return toast('Select records first.',true);
    const classification=$('controlClassification').value;
    if(kind==='classification'&&rows.some(r=>r.legacy||(r.sessions||[]).length))return toast('Day Off review only accepts live records without sessions. Select those records separately.',true);
    if(kind!=='classification'&&rows.some(r=>r.legacy||!(r.sessions||[]).length))return toast('Batch break changes require live records with sessions. Use Edit / Break for previous records.',true);
    batchPlan=rows.map(r=>({staff_id:r.staff_id,date:r.operational_date,name:r.staff_name,kind,value:kind==='classification'?classification:kind==='breakYes',before:kind==='classification'?(r.classification||'Day Off - Pending Review'):r.break_taken!==false}));
    $('batchPreviewRows').innerHTML=batchPlan.map(r=>`<tr><td>${esc(r.name)}</td><td>${esc(r.date)}</td><td>${esc(String(r.before))}</td><td>${esc(String(r.value))}</td></tr>`).join('');$('batchResult').textContent='Review these changes before submitting. Successful rows are saved individually; failures will be listed.';$('batchSubmit').disabled=false;$('batchModal').classList.remove('hidden');
  }
  function closeBatch(){if(!controlBusy){$('batchModal').classList.add('hidden');batchPlan=[];}}
  async function submitBatch(){
    if(controlBusy||!batchPlan.length)return;controlBusy=true;$('batchSubmit').disabled=true;
    let ok=0;const failed=[];const note=$('controlReviewNote').value.trim()||null;
    try{for(const item of batchPlan){try{
      const fresh=await ensureDayInHistory(item.staff_id,item.date);
      if(!fresh||fresh.legacy)throw new Error('Record changed or is unavailable. Refresh and review again.');
      if(item.kind==='classification'){
        if((fresh.sessions||[]).length||(fresh.classification||'Day Off - Pending Review')!==item.before)throw new Error('Attendance changed since preview. Refresh and review again.');
        await rpc('attendance_live_admin_classify_day',{p_token:ctx().token,p_staff_id:item.staff_id,p_date:item.date,p_classification:item.value,p_note:note??fresh.classification_note??null});
      }else{
        if(!(fresh.sessions||[]).length||(fresh.break_taken!==false)!==item.before)throw new Error('Attendance changed since preview. Refresh and review again.');
        await rpc('attendance_live_admin_set_break',{p_token:ctx().token,p_staff_id:item.staff_id,p_date:item.date,p_break_taken:item.value});
      }
      ok++;controlMarks.delete(`${item.staff_id}|${item.date}`);
    }catch(e){failed.push(`${item.name} · ${item.date}: ${e.message}`);}}
    }finally{controlBusy=false;batchPlan=[];invalidateHistory();$('batchResult').textContent=`Saved: ${ok}. Failed: ${failed.length}.`+(failed.length?'\n'+failed.join('\n'):'');await loadControl();}
  }
  async function openHistoryForRecord(staffId,date){GoyaAttendance.nav(document.querySelector('[onclick*="attLiveControl"]'),'attLiveControl');$('liveControlFrom').value=date;$('liveControlDate').value=date;await loadControl();await editDay(staffId,date);}

  function openManualControl(staffId,staffName,action,date){
    controlTarget={staffId,staffName};
    $('liveControlModalTitle').textContent=`${staffName} · Manual Attendance`;
    $('liveControlAction').value=action||'CHECK_IN';
    const now=new Date(Date.now()+liveState.serverOffset+4*3600000);$('liveControlTime').value=(date||now.toISOString().slice(0,10))+now.toISOString().slice(10,16);
    const row=controlRows.find(r=>r.staff_id===staffId&&r.operational_date===date);$('liveControlBreak').value=row?.break_taken===false?'false':'true';$('liveControlNote').value='';
    $('liveControlModal').classList.remove('hidden');
  }
  function closeControlModal(){$('liveControlModal')?.classList.add('hidden');controlTarget=null}
  async function saveManualControl(){
    if(!controlTarget||controlBusy)return;
    const action=$('liveControlAction').value,when=$('liveControlTime').value,note=$('liveControlNote').value.trim();
    if(!when)return toast('Select attendance date and time.',true);
    if(!confirm(`Save manual ${action.replace('_',' ')} for ${controlTarget.staffName}?`))return;
    controlBusy=true;
    try{
      const d=new Date(localInputToIso(when));if(Number.isNaN(d.getTime()))throw new Error('Invalid date/time.');
      await rpc('attendance_live_admin_manual_action',{p_token:ctx().token,p_staff_id:controlTarget.staffId,p_action:action,p_at:d.toISOString(),p_break_taken:$('liveControlBreak').value==='true',p_note:note});
      toast('Manual attendance saved and audit history updated.');closeControlModal();invalidateHistory();controlBusy=false;await loadControl();
    }catch(e){toast(e.message,true)}finally{controlBusy=false;}
  }
  function openManagement(){window.open('goya-live.html','_blank','noopener')}
  function openControl(){
    fillStaffFilter();
    const dateInput=$('liveControlDate');
    if(dateInput&&!dateInput.value)dateInput.value=new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Dubai'});
    if(!$('liveControlFrom').value)$('liveControlFrom').value=dateInput.value;
    loadControl();
  }
  function openDashboard(){fillStaffFilter();if(!$('liveDashDate').value)$('liveDashDate').value=new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Dubai'});loadDashboard()}
  function openHistory(){fillStaffFilter();const d=new Date(),end=d.toLocaleDateString('en-CA',{timeZone:'Asia/Dubai'}),month=end.slice(0,7),start=`${month}-01`;if(!$('liveHistMonth').value)$('liveHistMonth').value=month;if(!$('liveHistFrom').value)$('liveHistFrom').value=start;if(!$('liveHistTo').value)$('liveHistTo').value=end;loadHistory()}
  function openSettings(){loadSettings()}
  window.GoyaLiveAdmin={historyRangeChanged,invalidateHistory,toggleControlMark,markControlAll,clearControlMarks,controlAction,reviewOne,previewBatch,closeBatch,submitBatch,openDashboard,loadDashboard,setDashboardFilter,openControl,loadControl,setControlFilter,renderControl,openHistoryForRecord,openManualControl,closeControlModal,saveManualControl,openHistory,loadHistory,renderHistory,applyMonth,editDay,addLegacySecondSession,saveEditBreak,savePreviousRecordEdit,saveSessionEdit,closeEdit,exportExcel,exportPDF,exportOvertimeExcel,exportOvertimePDF,openSettings,loadSettings,detectLocation,detectIp,addLocation,removeLocation,saveSettings,setOvertime,openManagement};
  if(window.GoyaAttendance){window.GoyaAttendance.openLiveDashboard=openDashboard;window.GoyaAttendance.openLiveHistory=openHistory;window.GoyaAttendance.openLiveSettings=openSettings;}
})();
