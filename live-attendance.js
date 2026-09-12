(() => {
  const cfg=window.GOYA_CONFIG||{};
  let sb=null,timer=null,refreshTimer=null,serverOffset=0,current=null,busy=false,historyRows=[],legacyRows=[],pendingAction=null,pendingBreakTaken=true;
  const $=id=>document.getElementById(id),pad=n=>String(n).padStart(2,'0');
  const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
  const ctx=()=>window.GoyaStaff?._liveContext?.()||{};
  async function client(){if(!cfg.SUPABASE_URL||!cfg.SUPABASE_ANON_KEY)throw new Error('Supabase config missing');if(!sb)sb=window.supabase.createClient(cfg.SUPABASE_URL,cfg.SUPABASE_ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});return sb}
  async function rpc(name,args={}){const c=ctx();if(!c.token)throw new Error('Staff session expired. Please login again.');await client();const {data,error}=await sb.rpc(name,args);if(error)throw new Error(error.message);return data}
  async function publicRpc(name,args={}){await client();const {data,error}=await sb.rpc(name,args);if(error)throw new Error(error.message);return data}
  function toast(msg,err=false){const host=$('toastHost')||document.body,d=document.createElement('div');d.className='toast'+(err?' err':'');d.textContent=msg;host.appendChild(d);setTimeout(()=>d.remove(),4200)}
  const fmtTime=v=>{if(!v)return '—';const d=new Date(v);return Number.isNaN(d.getTime())?'—':d.toLocaleTimeString('en-AE',{hour:'numeric',minute:'2-digit'})};
  const fmtDate=v=>{if(!v)return '—';return new Date(v+'T12:00:00').toLocaleDateString('en-AE',{day:'2-digit',month:'short',year:'numeric'})};
  const minsLabel=m=>{m=Math.max(0,Math.floor(Number(m)||0));return `${Math.floor(m/60)}h ${pad(m%60)}m`};
  const otText=m=>{m=Math.floor(Math.max(0,Number(m)||0)/30)*30;if(!m)return '0';if(m===30)return '30 min';const h=m/60;return `${Number.isInteger(h)?h:h.toFixed(1)} ${h===1?'hour':'hours'}`};
  const clockLabel=sec=>{sec=Math.max(0,Math.floor(sec));return `${pad(Math.floor(sec/3600))}:${pad(Math.floor((sec%3600)/60))}:${pad(sec%60)}`};
  const daySessions=()=>Array.isArray(current?.sessions)?current.sessions:[];
  const dayInfo=()=>current?.day||{break_taken:pendingBreakTaken,late_minutes:0,classification:'Duty'};
  const nowMs=()=>Date.now()+serverOffset;
  function effectiveStartMs(session,index,row=dayInfo()){let ms=new Date(session.check_in_at).getTime();if(index===0&&row.scheduled_start){const date=row.operational_date||current?.operational_date;const sch=new Date(`${date}T${String(row.scheduled_start).slice(0,5)}:00+04:00`).getTime();if(Number.isFinite(sch)&&ms<sch)ms=sch}return ms}
  function calcRow(row,liveNow=false){if(row?.legacy_precalc){const x=row.legacy_precalc;return {sec:Number(x.sec)||0,net:Number(x.net)||0,ot:Number(x.ot)||0,target:Number(x.target)||0,remaining:0,remainingSeconds:0,liveOt:Number(x.ot)||0,liveOtSeconds:Number(x.ot||0)*60}}const sessions=Array.isArray(row.sessions)?row.sessions:[];let sec=0;const now=liveNow?nowMs():0;sessions.forEach((session,index)=>{if(!session?.check_in_at)return;const start=effectiveStartMs(session,index,row),end=session.check_out_at?new Date(session.check_out_at).getTime():(liveNow?now:start);if(Number.isFinite(start)&&Number.isFinite(end)&&end>start)sec+=(end-start)/1000});const rules=current?.rules||{},regular=Math.max(1,Number(rules.regular_net_minutes)||480),breakMinutes=Math.max(0,Number(rules.break_minutes)||60),breakTaken=row.break_taken!==false,target=breakTaken?regular+breakMinutes:regular,presenceMinutes=sec/60,net=Math.max(0,presenceMinutes-(breakTaken?breakMinutes:0)),rawOt=Math.max(0,net-regular),ot=Math.floor(rawOt/30)*30,remainingSeconds=Math.max(0,target*60-sec),liveOtSeconds=Math.max(0,sec-target*60);return {sec,net,ot,target,remaining:remainingSeconds/60,remainingSeconds,liveOt:liveOtSeconds/60,liveOtSeconds}}
  const totals=()=>calcRow({...dayInfo(),operational_date:current?.operational_date,sessions:daySessions()},true);
  const openSession=()=>daySessions().find(s=>!s.check_out_at)||null;
  function verificationBadge(ok,text){return `<span class="live-verify ${ok?'ok':'bad'}">${ok?'✓':'!'} ${esc(text)}</span>`}
  function rowVerification(row){if(row?.legacy)return 'Previous Record';const ss=row.sessions||[];if(!ss.length)return '—';const okIn=ss.every(s=>s.check_in_verified),outs=ss.filter(s=>s.check_out_at),okOut=outs.length===ss.length&&outs.every(s=>s.check_out_verified);return okIn&&okOut?'Verified':'Review'}
  function statusLabel(row){return row.sessions?.length?(row.sessions.some(s=>!s.check_out_at)?'On Duty':(row.classification||'Duty')):(row.classification||'Day Off - Pending Review')}
  function setBreakUI(value){pendingBreakTaken=value!==false;const host=$('liveBreakTaken');if(host)host.querySelectorAll('button[data-value]').forEach(b=>b.classList.toggle('active',(b.dataset.value==='true')===pendingBreakTaken))}
  function render(){if(!current)return;const t=totals(),open=openSession(),hasSessions=daySessions().length>0,work=$('liveWorkingTime'),sub=$('liveTimerSub'),subLabel=$('liveTimerSubLabel'),ring=$('liveTimerRing');if(work)work.textContent=clockLabel(t.sec);if(t.remainingSeconds>0){if(subLabel)subLabel.textContent='Duty Remaining';if(sub)sub.textContent=clockLabel(t.remainingSeconds)}else{if(subLabel)subLabel.textContent='OT';if(sub)sub.textContent=clockLabel(t.liveOtSeconds)}if(ring){ring.classList.toggle('is-ot',t.remaining<=0);ring.classList.toggle('is-live',!!open)}
    if($('liveOperationalDate'))$('liveOperationalDate').textContent=fmtDate(current.operational_date);if($('liveLate'))$('liveLate').textContent=(dayInfo().late_minutes||0)>0?`${dayInfo().late_minutes} min`:'On Time';if($('liveSessionCount'))$('liveSessionCount').textContent=String(daySessions().length||0);if($('liveStatusText')){$('liveStatusText').textContent=open?'ON DUTY':hasSessions?'CHECKED OUT':'READY';$('liveStatusText').className='live-status '+(open?'on':hasSessions?'done':'idle')}if($('liveHeaderBadge'))$('liveHeaderBadge').textContent=open?'Live timer running':hasSessions?'Shift saved':'Ready to check in';
    pendingBreakTaken=current?.day?current.day.break_taken!==false:pendingBreakTaken;setBreakUI(pendingBreakTaken);
    $('liveCheckInBtn')?.classList.toggle('hidden',hasSessions||!!open);$('liveCheckOutBtn')?.classList.toggle('hidden',!open);$('liveRejoinBtn')?.classList.toggle('hidden',!hasSessions||!!open);
    const sess=$('liveSessionList');if(sess)sess.innerHTML=daySessions().length?daySessions().map(s=>`<div class="live-session-row"><div><span class="live-session-no">SHIFT ${s.session_no}</span><strong>${fmtTime(s.check_in_at)} <span>→</span> ${fmtTime(s.check_out_at)}</strong></div><div class="live-session-verify">${verificationBadge(!!s.check_in_verified,'In')} ${s.check_out_at?verificationBadge(!!s.check_out_verified,'Out'):''}</div></div>`).join(''):'<div class="live-empty">Your first live shift will appear here after Check In.</div>';
  }
  function tick(){render()}
  async function getPublicIp(){for(const url of ['https://api.ipify.org?format=json','https://api64.ipify.org?format=json']){try{const r=await fetch(url,{cache:'no-store'});if(r.ok){const j=await r.json();if(j.ip)return j.ip}}catch{}}throw new Error('Could not verify office network public IP. Check internet and try again.')}
  function getGps(){return new Promise((resolve,reject)=>{if(!navigator.geolocation)return reject(new Error('GPS is not supported on this device/browser.'));navigator.geolocation.getCurrentPosition(p=>resolve({lat:p.coords.latitude,lon:p.coords.longitude,accuracy:p.coords.accuracy}),e=>reject(new Error(e.code===1?'Location permission is required. Please allow location access and try again.':e.code===3?'Location request timed out. Move near a window or enable precise location, then try again.':'Could not get workplace GPS location.')),{enableHighAccuracy:true,timeout:20000,maximumAge:0})})}
  function showActionMessage(title,text,isError=true){const modal=$('liveActionModal');if(!modal)return toast(text,isError);$('liveActionModalTitle').textContent=title;$('liveActionModalText').textContent=text;$('liveActionModalStatus').innerHTML=isError?'<span class="live-verify bad">Verification failed</span>':'<span class="live-verify ok">Ready</span>';$('liveActionConfirmBtn').classList.toggle('hidden',isError);modal.classList.remove('hidden')}
  function requestAction(type){
    if(busy)return;
    const modal=$('liveActionModal');
    if(!modal){toast('Attendance confirmation panel could not open. Please refresh the page.',true);return;}
    pendingAction=type;
    const label=type==='out'?'Check Out':type==='rejoin'?'Rejoin':'Check In';
    $('liveActionModalTitle').textContent=`Confirm ${label}`;
    $('liveActionModalText').textContent='Workplace GPS and approved office network will be verified before this attendance action is saved.';
    $('liveActionModalStatus').innerHTML='<span class="live-verify wait">Ready to verify</span>';
    $('liveActionConfirmBtn').textContent=`Confirm ${label}`;
    $('liveActionConfirmBtn').classList.remove('hidden');
    modal.classList.remove('hidden');
  }
  function closeActionModal(){if(!busy)$('liveActionModal')?.classList.add('hidden')}
  async function verifyWorkplace(){
    const box=$('liveVerifyBox'),status=$('liveActionModalStatus');
    if(box)box.innerHTML='<span class="live-verify wait">Verifying GPS and office network…</span>';
    if(status)status.innerHTML='<span class="live-verify wait">Checking workplace…</span>';
    const [gps,ip]=await Promise.all([getGps(),getPublicIp()]);
    const verify=await publicRpc('attendance_live_verify_workplace',{p_lat:gps.lat,p_lon:gps.lon,p_public_ip:ip});
    if(!verify?.ok){
      const distance=Number(verify?.distance_m);
      let reason=verify?.reason||'Workplace verification failed.';
      if(/outside/i.test(reason)&&Number.isFinite(distance))reason=`You are outside the approved duty location. You are approximately ${Math.round(distance)} m from the nearest approved workplace.`;
      if(box)box.innerHTML=`${verificationBadge(false,'Location / Network Failed')}`;
      const label=pendingAction==='out'?'Check Out':pendingAction==='rejoin'?'Rejoin':'Check In';
      showActionMessage(`Cannot ${label}`,reason,true);
      const err=new Error(reason);err.verificationShown=true;throw err;
    }
    if(box)box.innerHTML=`${verificationBadge(true,`GPS ±${Math.round(gps.accuracy||0)}m`)} ${verificationBadge(true,`Network verified`)}`;
    if(status)status.innerHTML=`${verificationBadge(true,'Workplace GPS')} ${verificationBadge(true,'Office network')}`;
    return {...gps,ip,verify};
  }
  async function refresh(silent=false){try{const d=await rpc('staff_live_attendance_status',{p_token:ctx().token});current=d;serverOffset=new Date(d.server_now).getTime()-Date.now();if(current?.day)pendingBreakTaken=current.day.break_taken!==false;render();if(!silent)await loadHistory()}catch(e){if(!silent)toast(e.message,true)}}
  async function doAction(type){if(busy)return;busy=true;setButtons(true);try{const v=await verifyWorkplace();let d;if(type==='out')d=await rpc('staff_live_attendance_check_out',{p_token:ctx().token,p_lat:v.lat,p_lon:v.lon,p_public_ip:v.ip,p_break_taken:pendingBreakTaken});else{d=await rpc('staff_live_attendance_check_in',{p_token:ctx().token,p_lat:v.lat,p_lon:v.lon,p_public_ip:v.ip,p_rejoin:type==='rejoin'});await rpc('staff_live_attendance_set_break',{p_token:ctx().token,p_break_taken:pendingBreakTaken})}toast(d?.message||`${type==='out'?'Check Out':type==='rejoin'?'Rejoin':'Check In'} successful.`);$('liveActionModal')?.classList.add('hidden');await refresh()}catch(e){if(!e.verificationShown){showActionMessage('Attendance action failed',e.message,true);toast(e.message,true)}}finally{busy=false;setButtons(false)}}
  function confirmAction(){if(pendingAction)doAction(pendingAction)}
  function setButtons(dis){['liveCheckInBtn','liveCheckOutBtn','liveRejoinBtn','liveActionConfirmBtn'].forEach(id=>{if($(id))$(id).disabled=dis})}
  async function chooseBreak(value){pendingBreakTaken=value;setBreakUI(value);render();if(current?.day){try{await rpc('staff_live_attendance_set_break',{p_token:ctx().token,p_break_taken:value});current.day.break_taken=value;render();toast(value?'Break set: 9h presence / 8h net.':'No break: 8h presence target.')}catch(e){toast(e.message,true)}}}
  function durationMinutes(a,b){if(!a||!b)return 0;const x=new Date(a).getTime(),y=new Date(b).getTime();return Number.isFinite(x)&&Number.isFinite(y)&&y>x?(y-x)/60000:0}
  function normalizeLegacyMonth(d){const finals=d?.records||[],subs=d?.submissions||[],finalMap=new Map(finals.map(x=>[x.operational_date,x])),subMap=new Map();for(const x of subs){if(!subMap.has(x.operational_date))subMap.set(x.operational_date,x)}const dates=[...new Set([...finalMap.keys(),...subMap.keys()])];return dates.map(date=>{const f=finalMap.get(date),r=subMap.get(date)||f;if(!r)return null;const off=!!r.day_off;const sessions=[];if(!off&&r.punch_in){sessions.push({session_no:1,check_in_at:r.punch_in,check_out_at:r.punch_out||null,check_in_verified:true,check_out_verified:!!r.punch_out,legacy:true});if(r.split_shift&&r.shift2_in)sessions.push({session_no:2,check_in_at:r.shift2_in,check_out_at:r.shift2_out||null,check_in_verified:true,check_out_verified:!!r.shift2_out,legacy:true})}let worked=sessions.reduce((a,x)=>a+durationMinutes(x.check_in_at,x.check_out_at),0),net=f?.net_work_minutes!=null?Number(f.net_work_minutes):Math.max(0,worked-(r.break_taken===false?0:60)),ot=f?.additional_minutes!=null?Math.floor(Math.max(0,Number(f.additional_minutes))/30)*30:Math.floor(Math.max(0,net-480)/30)*30;return {operational_date:date,break_taken:r.break_taken!==false,classification:off?'Day Off':'Duty',classification_note:r.note||null,late_minutes:Number(f?.late_minutes||r.late_minutes||0),sessions,legacy:true,legacy_precalc:{sec:worked*60,net,ot,target:r.break_taken===false?480:540},legacy_record:r}}).filter(Boolean)}
  function mergeLiveAndLegacy(live,legacy){const lm=new Map(legacy.map(r=>[r.operational_date,r]));const out=[];for(const r of live){const hasLive=(r.sessions||[]).length>0 || (r.classification&&r.classification!=='Day Off - Pending Review');if(hasLive){out.push(r);lm.delete(r.operational_date)}else if(lm.has(r.operational_date)){out.push(lm.get(r.operational_date));lm.delete(r.operational_date)}else out.push(r)}for(const r of lm.values())out.push(r);return out.sort((a,b)=>String(b.operational_date).localeCompare(String(a.operational_date)))}
  function renderMonthlyDashboard(rows){const el=$('liveMonthlyDashboard');if(!el)return;let duty=0,off=0,work=0,ot=0,late=0,noBreak=0,split=0,review=0;rows.forEach(r=>{const c=calcRow(r),ss=r.sessions||[],st=statusLabel(r);if(ss.length){duty++;work+=c.sec/60;ot+=c.ot;if((r.late_minutes||0)>0)late++;if(r.break_taken===false)noBreak++;if(ss.length>1)split++}else off++;if(/Pending Review|Review/i.test(st)||ss.some(s=>!s.check_out_at))review++});el.innerHTML=[['Duty Days',duty],['Day Off',off],['Working',minsLabel(work)],['Total OT',otText(ot)],['Late Days',late],['No Break',noBreak],['Split Shift',split],['Review',review]].map(([k,v])=>`<div><span>${k}</span><strong>${v}</strong></div>`).join('')}
  function filteredHistory(){const date=$('liveHistoryDate')?.value||'';return historyRows.filter(r=>!date||r.operational_date===date)}
  function renderHistory(){const rows=filteredHistory();renderMonthlyDashboard(historyRows);const tbody=$('liveHistoryRows'),cards=$('liveHistoryCards');if(tbody)tbody.innerHTML=rows.length?rows.map(r=>{const c=calcRow(r),s=r.sessions||[],first=s[0],last=s[s.length-1],cls=statusLabel(r);return `<tr><td>${esc(r.operational_date)}</td><td>${s.length?`${fmtTime(first?.check_in_at)} → ${fmtTime(last?.check_out_at)}`:'—'}</td><td>${s.length}</td><td>${s.length?minsLabel(c.sec/60):'—'}</td><td>${s.length?minsLabel(c.net):'—'}</td><td>${c.ot?otText(c.ot):'—'}</td><td>${r.late_minutes?`${r.late_minutes} min`:'—'}</td><td>${s.length?(r.break_taken!==false?'Yes':'No'):'—'}</td><td>${esc(cls)}</td></tr>`}).join(''):'<tr><td colspan="9" class="empty">No attendance record for selected date.</td></tr>';
    if(cards)cards.innerHTML=rows.length?rows.map(r=>{const c=calcRow(r),ss=r.sessions||[],st=statusLabel(r);return `<article class="live-history-day"><header><div><span>${fmtDate(r.operational_date)}</span><strong>${esc(st)}</strong></div><span class="live-day-chip">${r.legacy?'Previous Record':(ss.length?`${ss.length} ${ss.length===1?'shift':'shifts'}`:'No shift')}</span></header>${ss.length?`<div class="live-shift-timeline">${ss.map(s=>`<div><b>Shift ${s.session_no}</b><span>${fmtTime(s.check_in_at)} → ${fmtTime(s.check_out_at)}</span><small>${verificationBadge(!!s.check_in_verified&&!!s.check_out_verified,'Verified')}</small></div>`).join('')}</div>`:'<div class="live-dayoff">No Check In recorded</div>'}<footer><span>Worked <b>${ss.length?minsLabel(c.sec/60):'—'}</b></span><span>Net <b>${ss.length?minsLabel(c.net):'—'}</b></span><span>OT <b>${c.ot?otText(c.ot):'—'}</b></span><span>Late <b>${r.late_minutes?`${r.late_minutes}m`:'—'}</b></span></footer></article>`}).join(''):'<div class="live-empty">No attendance record for selected date.</div>'}
  async function loadHistory(){const month=$('liveHistoryMonth')?.value||new Date().toISOString().slice(0,7);if($('liveHistoryMonth'))$('liveHistoryMonth').value=month;try{const [d,legacy]=await Promise.all([rpc('staff_live_attendance_history',{p_token:ctx().token,p_month:month+'-01'}),rpc('staff_attendance_month_v12',{p_token:ctx().token,p_month:month+'-01'}).catch(()=>({records:[],submissions:[]}))]);if(!current)current={rules:d.rules||{}};else current.rules=d.rules||current.rules;legacyRows=normalizeLegacyMonth(legacy);historyRows=mergeLiveAndLegacy(d.rows||[],legacyRows);renderHistory()}catch(e){toast(e.message,true)}}
  function clearDateFilter(){if($('liveHistoryDate'))$('liveHistoryDate').value='';renderHistory()}
  function downloadPDF(){const rows=filteredHistory();if(!rows.length)return toast('No attendance data to export.',true);if(!window.jspdf?.jsPDF)return toast('PDF library is still loading.',true);const {jsPDF}=window.jspdf,doc=new jsPDF({orientation:'landscape'}),staff=current?.staff?.name||ctx()?.staff?.name||'Staff',month=$('liveHistoryMonth')?.value||'',date=$('liveHistoryDate')?.value||'';let duty=0,off=0,work=0,ot=0,late=0,split=0;rows.forEach(r=>{const c=calcRow(r),ss=r.sessions||[];if(ss.length){duty++;work+=c.sec/60;ot+=c.ot;if(r.late_minutes)late++;if(ss.length>1)split++}else off++});doc.setFontSize(18);doc.text('GOYA - Live Attendance Report',14,16);doc.setFontSize(10);doc.text(`Staff: ${staff}   Period: ${date||month}`,14,24);doc.text(`Duty Days: ${duty}   Day Off: ${off}   Working: ${minsLabel(work)}   OT: ${otText(ot)}   Late Days: ${late}   Split Shifts: ${split}`,14,31);doc.autoTable({startY:37,head:[['Date','Shift Sessions','Working Time','Worked','Net','OT','Late','Break','Status','Verification']],body:rows.map(r=>{const c=calcRow(r),ss=r.sessions||[];return [r.operational_date,ss.length,ss.length?ss.map(s=>`${fmtTime(s.check_in_at)}-${fmtTime(s.check_out_at)}`).join(' | '):'—',ss.length?minsLabel(c.sec/60):'—',ss.length?minsLabel(c.net):'—',c.ot?otText(c.ot):'—',r.late_minutes?`${r.late_minutes} min`:'—',ss.length?(r.break_taken!==false?'Yes':'No'):'—',statusLabel(r),rowVerification(r)]}),styles:{fontSize:8,cellPadding:2},headStyles:{fillColor:[37,58,50]}});const safe=staff.replace(/[^a-z0-9]+/gi,'_').replace(/^_|_$/g,'');doc.save(`Goya_Live_Attendance_${safe}_${date||month}.pdf`)}
  function bind(){
    const br=$('liveBreakTaken');
    br?.querySelectorAll('button[data-value]').forEach(b=>{b.onclick=()=>chooseBreak(b.dataset.value==='true')});
    const actions={liveCheckInBtn:'in',liveCheckOutBtn:'out',liveRejoinBtn:'rejoin'};
    Object.entries(actions).forEach(([id,type])=>{
      const b=$(id);
      if(!b)return;
      b.type='button';
      b.style.pointerEvents='auto';
      b.onclick=e=>{e.preventDefault();e.stopPropagation();requestAction(type)};
    });
    if(!document.documentElement.dataset.goyaLivePunchDelegated){
      document.documentElement.dataset.goyaLivePunchDelegated='1';
      document.addEventListener('click',e=>{
        const b=e.target.closest?.('#liveCheckInBtn,#liveCheckOutBtn,#liveRejoinBtn');
        if(!b)return;
        e.preventDefault();e.stopPropagation();
        const type=b.id==='liveCheckOutBtn'?'out':b.id==='liveRejoinBtn'?'rejoin':'in';
        requestAction(type);
      },true);
      document.addEventListener('touchend',e=>{
        const b=e.target.closest?.('#liveCheckInBtn,#liveCheckOutBtn,#liveRejoinBtn');
        if(!b)return;
        e.preventDefault();e.stopPropagation();
        const type=b.id==='liveCheckOutBtn'?'out':b.id==='liveRejoinBtn'?'rejoin':'in';
        requestAction(type);
      },{capture:true,passive:false});
    }
  }
  async function open(){bind();await refresh();clearInterval(timer);timer=setInterval(tick,1000);clearInterval(refreshTimer);refreshTimer=setInterval(()=>refresh(true),60000)}
  function stop(){clearInterval(timer);clearInterval(refreshTimer)}
  window.GoyaLiveAttendance={open,refresh,checkIn:()=>requestAction('in'),checkOut:()=>requestAction('out'),rejoin:()=>requestAction('rejoin'),chooseBreak,saveBreak:()=>chooseBreak(pendingBreakTaken),loadHistory,renderHistory,clearDateFilter,downloadPDF,requestAction,confirmAction,closeActionModal,stop};
})();
