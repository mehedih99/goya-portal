(() => {
  const cfg=window.GOYA_CONFIG||{};
  let sb=null,timer=null,refreshTimer=null,serverOffset=0,current=null,busy=false,historyRows=[],pendingAction=null,pendingBreakTaken=true;
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
  function activeSessions(row){return (Array.isArray(row?.sessions)?row.sessions:[]).filter(s=>!s.is_deleted).slice().sort((a,b)=>new Date(a.check_in_at)-new Date(b.check_in_at))}
  function minutesAtZone(ts,row){const d=new Date(ts);if(Number.isNaN(d.getTime()))return null;const tz=current?.rules?.timezone||'Asia/Dubai';const parts=new Intl.DateTimeFormat('en-GB',{timeZone:tz,hour:'2-digit',minute:'2-digit',hour12:false}).formatToParts(d);const h=Number(parts.find(x=>x.type==='hour')?.value),m=Number(parts.find(x=>x.type==='minute')?.value);return Number.isFinite(h)&&Number.isFinite(m)?h*60+m:null}
  function matchedShift(row){const ss=activeSessions(row);if(!ss.length)return null;const punch=minutesAtZone(ss[0].check_in_at,row);if(punch==null)return null;const rr=current?.rules||{},shifts=Array.isArray(rr.shift_start_times)?rr.shift_start_times:['08:00','09:00','10:00','11:00','12:00','13:00','14:00','15:00','16:00','17:00'];let best=null,bestDist=null;shifts.forEach(v=>{const [h,m]=String(v).split(':').map(Number),sm=h*60+m,dist=Math.abs(punch-sm);if(bestDist==null||dist<bestDist||(dist===bestDist&&sm>best)){best=sm;bestDist=dist}});return best}
  function derivedLate(row){const ss=activeSessions(row);if(!ss.length)return 0;const punch=minutesAtZone(ss[0].check_in_at,row),sh=matchedShift(row),grace=Number(current?.rules?.late_grace_minutes)||15;if(punch==null||sh==null)return 0;return punch-sh>grace?punch-sh:0}
  function effectiveStartMs(session,index,row=dayInfo()){let ms=new Date(session.check_in_at).getTime();if(index===0){const sm=matchedShift({...row,sessions:activeSessions(row)});const date=row.operational_date||current?.operational_date;if(sm!=null&&date){const h=Math.floor(sm/60),m=sm%60,sch=new Date(`${date}T${pad(h)}:${pad(m)}:00+04:00`).getTime();if(Number.isFinite(sch)&&ms<sch)ms=sch}}return ms}
  function calcRow(row,liveNow=false){const sessions=activeSessions(row);let sec=0;const now=liveNow?nowMs():0;sessions.forEach((s,i)=>{const st=effectiveStartMs(s,i,{...row,sessions}),en=s.check_out_at?new Date(s.check_out_at).getTime():(liveNow?now:st);if(Number.isFinite(st)&&Number.isFinite(en)&&en>st)sec+=(en-st)/1000});const rules=current?.rules||{},breakTaken=row.break_taken!==false,breakMin=breakTaken?(Number(rules.break_minutes)||60):0,regular=Number(rules.regular_net_minutes)||480,target=breakTaken?(Number(rules.duty_presence_minutes)||540):regular,net=Math.max(0,sec/60-breakMin),ot=Math.floor(Math.max(0,net-regular)/30)*30;return {sec,net,ot,target,remaining:Math.max(0,target-sec/60),liveOt:Math.max(0,net-regular)}}
  const totals=()=>calcRow({...dayInfo(),operational_date:current?.operational_date,sessions:daySessions()},true);
  const openSession=()=>daySessions().find(s=>!s.check_out_at)||null;
  function verificationBadge(ok,text){return `<span class="live-verify ${ok?'ok':'bad'}">${ok?'✓':'!'} ${esc(text)}</span>`}
  function rowVerification(row){const ss=row.sessions||[];if(!ss.length)return '—';const okIn=ss.every(s=>s.check_in_verified),outs=ss.filter(s=>s.check_out_at),okOut=outs.length===ss.length&&outs.every(s=>s.check_out_verified);return okIn&&okOut?'Verified':'Review'}
  function friendlyPunchError(message=''){const m=String(message||'');if(/attendance_live_one_open_session_idx|duplicate key value violates unique constraint/i.test(m))return 'You already have an active attendance session. The current live session will be restored.';if(/already checked in/i.test(m))return 'You already have an active attendance session.';if(/already worked today/i.test(m))return 'You already completed a session today. Use Rejoin to continue your split shift.';if(/No active Check In found/i.test(m))return 'No active Check In was found. Refresh the page and try again.';return m||'Attendance action could not be completed.'}
  function statusLabel(row){const ss=activeSessions(row);if(ss.some(s=>!s.check_out_at))return 'On Duty';if(ss.length)return 'Shift Done';return row.classification||'Day Off - Pending Review'}
  function setBreakUI(value){pendingBreakTaken=value!==false;const host=$('liveBreakTaken');if(host)host.querySelectorAll('button[data-value]').forEach(b=>b.classList.toggle('active',(b.dataset.value==='true')===pendingBreakTaken))}
  function render(){if(!current)return;const t=totals(),open=openSession(),hasSessions=daySessions().length>0,work=$('liveWorkingTime'),sub=$('liveTimerSub'),subLabel=$('liveTimerSubLabel'),ring=$('liveTimerRing');if(work)work.textContent=clockLabel(t.sec);if(t.remaining>0){if(subLabel)subLabel.textContent='Duty Remaining';if(sub)sub.textContent=clockLabel(t.remaining*60)}else{if(subLabel)subLabel.textContent='OT';if(sub)sub.textContent=clockLabel(t.liveOt*60)}if(ring){ring.classList.toggle('is-ot',t.remaining<=0);ring.classList.toggle('is-live',!!open)}
    if($('liveOperationalDate'))$('liveOperationalDate').textContent=fmtDate(current.operational_date);const liveLate=derivedLate({...dayInfo(),operational_date:current?.operational_date,sessions:daySessions()});if($('liveLate'))$('liveLate').textContent=liveLate>0?`${liveLate} min`:'On Time';if($('liveSessionCount'))$('liveSessionCount').textContent=String(daySessions().length||0);if($('liveStatusText')){$('liveStatusText').textContent=open?'ON DUTY':hasSessions?'CHECKED OUT':'READY';$('liveStatusText').className='live-status '+(open?'on':hasSessions?'done':'idle')}if($('liveHeaderBadge'))$('liveHeaderBadge').textContent=open?'Live timer running':hasSessions?'Shift saved':'Ready to check in';
    pendingBreakTaken=current?.day?current.day.break_taken!==false:pendingBreakTaken;setBreakUI(pendingBreakTaken);
    $('liveCheckInBtn')?.classList.toggle('hidden',hasSessions||!!open);$('liveCheckOutBtn')?.classList.toggle('hidden',!open);$('liveRejoinBtn')?.classList.toggle('hidden',!hasSessions||!!open);
    const sess=$('liveSessionList');if(sess){const ss=activeSessions({sessions:daySessions()});sess.innerHTML=ss.length?ss.map((s,i)=>`<div class="live-session-row"><div><span class="live-session-no">SHIFT ${i+1}</span><strong>${fmtTime(s.check_in_at)} <span>→</span> ${fmtTime(s.check_out_at)}</strong></div><span class="live-saved-chip">${s.check_out_at?'Saved':'Live'}</span></div>`).join(''):'<div class="live-empty">Your first live shift will appear here after Check In.</div>'}
  }
  function tick(){render()}
  async function getPublicIp(){for(const url of ['https://api.ipify.org?format=json','https://api64.ipify.org?format=json']){try{const r=await fetch(url,{cache:'no-store'});if(r.ok){const j=await r.json();if(j.ip)return j.ip}}catch{}}throw new Error('Could not verify office network public IP. Check internet and try again.')}
  function getGps(){
    return new Promise((resolve,reject)=>{
      if(!navigator.geolocation)return reject(new Error('GPS is not supported on this device/browser.'));
      let attempts=0,best=null,finished=false;
      const fail=e=>{if(finished)return;finished=true;reject(new Error(e?.code===1?'Location permission is required. Please allow precise location and try again.':e?.code===3?'Fresh location timed out. Keep GPS on, move near a window and try again.':'Could not get fresh workplace GPS location.'))};
      const read=()=>navigator.geolocation.getCurrentPosition(p=>{
        const age=Date.now()-(p.timestamp||0),g={lat:p.coords.latitude,lon:p.coords.longitude,accuracy:p.coords.accuracy,timestamp:p.timestamp,age};
        if(!best||g.accuracy<best.accuracy)best=g;
        attempts++;
        if(age<=15000&&(g.accuracy||9999)<=100){finished=true;return resolve(g)}
        if(attempts<3)return setTimeout(read,650);
        if(best&&best.age<=30000){finished=true;return resolve(best)}
        fail({code:3});
      },fail,{enableHighAccuracy:true,timeout:12000,maximumAge:0});
      read();
    })
  }
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
    if(status)status.innerHTML=`${verificationBadge(true,verify.location_name||'Workplace')} ${verificationBadge(true,'Office network')}`;
    return {...gps,ip,verify};
  }
  async function refresh(silent=false){try{const d=await rpc('staff_live_attendance_status',{p_token:ctx().token});current=d;serverOffset=new Date(d.server_now).getTime()-Date.now();if(current?.day)pendingBreakTaken=current.day.break_taken!==false;render();if(!silent)await loadHistory()}catch(e){if(!silent)toast(e.message,true)}}
  async function doAction(type){
    if(busy)return;
    busy=true;setButtons(true);
    try{
      // Always read the latest server state first. This restores an already-open session
      // after refresh, device change or a previous duplicate tap instead of inserting again.
      await refresh(true);
      const existingOpen=openSession();
      if((type==='in'||type==='rejoin')&&existingOpen){
        $('liveActionModal')?.classList.add('hidden');
        render();
        toast('You are already checked in. Your live timer has been restored.');
        return;
      }
      if(type==='out'&&!existingOpen){
        throw new Error('No active Check In was found. Refresh the page and try again.');
      }
      const v=await verifyWorkplace();
      let d;
      if(type==='out'){
        d=await rpc('staff_live_attendance_check_out',{p_token:ctx().token,p_lat:v.lat,p_lon:v.lon,p_public_ip:v.ip,p_break_taken:pendingBreakTaken});
      }else{
        d=await rpc('staff_live_attendance_check_in',{p_token:ctx().token,p_lat:v.lat,p_lon:v.lon,p_public_ip:v.ip,p_rejoin:type==='rejoin'});
        if(d?.duplicate){
          await refresh(true);
          $('liveActionModal')?.classList.add('hidden');
          render();
          toast('You are already checked in. Your active session was restored.');
          return;
        }
        await rpc('staff_live_attendance_set_break',{p_token:ctx().token,p_break_taken:pendingBreakTaken});
      }
      toast(d?.message||`${type==='out'?'Check Out':type==='rejoin'?'Rejoin':'Check In'} successful.`);
      $('liveActionModal')?.classList.add('hidden');
      await refresh();
    }catch(e){
      const msg=friendlyPunchError(e?.message);
      if(/active attendance session|already checked in/i.test(msg)){
        try{await refresh(true);render();$('liveActionModal')?.classList.add('hidden')}catch{}
      }
      if(!e.verificationShown){showActionMessage('Attendance action failed',msg,true);toast(msg,true)}
    }finally{busy=false;setButtons(false)}
  }
  function confirmAction(){if(pendingAction)doAction(pendingAction)}
  function setButtons(dis){['liveCheckInBtn','liveCheckOutBtn','liveRejoinBtn','liveActionConfirmBtn'].forEach(id=>{if($(id))$(id).disabled=dis})}
  async function chooseBreak(value){pendingBreakTaken=value;setBreakUI(value);render();if(current?.day){try{await rpc('staff_live_attendance_set_break',{p_token:ctx().token,p_break_taken:value});current.day.break_taken=value;render();toast(value?'Break set: 9h presence / 8h net.':'No break: 8h presence target.')}catch(e){toast(e.message,true)}}}
  function renderMonthlyDashboard(rows){const el=$('liveMonthlyDashboard');if(!el)return;let duty=0,off=0,work=0,ot=0,late=0,noBreak=0,split=0,review=0;rows.forEach(r=>{const c=calcRow(r),ss=activeSessions(r),st=statusLabel(r);if(ss.length){duty++;work+=c.sec/60;ot+=c.ot;if(derivedLate(r)>0)late++;if(r.break_taken===false)noBreak++;if(ss.length>1)split++}else off++;if(/Pending Review|Review/i.test(st)||ss.some(s=>!s.check_out_at))review++});el.innerHTML=[['Duty Days',duty],['Day Off',off],['Working',minsLabel(work)],['Total OT',otText(ot)],['Late Days',late],['No Break',noBreak],['Split Shift',split],['Review',review]].map(([k,v])=>`<div><span>${k}</span><strong>${v}</strong></div>`).join('')}
  function filteredHistory(){const date=$('liveHistoryDate')?.value||'';return historyRows.filter(r=>!date||r.operational_date===date)}
  function renderHistory(){const rows=filteredHistory();renderMonthlyDashboard(historyRows);const tbody=$('liveHistoryRows'),cards=$('liveHistoryCards');if(tbody)tbody.innerHTML=rows.length?rows.map(r=>{const c=calcRow(r),s=activeSessions(r),first=s[0],last=s[s.length-1],cls=statusLabel(r),lm=derivedLate(r);return `<tr><td>${esc(r.operational_date)}</td><td>${s.length?`${fmtTime(first?.check_in_at)} → ${fmtTime(last?.check_out_at)}`:'—'}</td><td>${s.length}</td><td>${s.length?minsLabel(c.sec/60):'—'}</td><td>${s.length?minsLabel(c.net):'—'}</td><td>${c.ot?otText(c.ot):'—'}</td><td>${lm?`${lm} min`:'—'}</td><td>${s.length?(r.break_taken!==false?'Yes':'No'):'—'}</td><td>${esc(cls)}</td></tr>`}).join(''):'<tr><td colspan="9" class="empty">No attendance record for selected date.</td></tr>';
    if(cards)cards.innerHTML=rows.length?rows.map(r=>{const c=calcRow(r),ss=activeSessions(r),st=statusLabel(r),lm=derivedLate(r);return `<article class="live-history-day"><header><div><span>${fmtDate(r.operational_date)}</span><strong>${esc(st)}</strong></div><span class="live-day-chip">${ss.length?`${ss.length} ${ss.length===1?'shift':'shifts'}`:'No shift'}</span></header>${ss.length?`<div class="live-shift-timeline">${ss.map((s,i)=>`<div><b>Shift ${i+1}</b><span>${fmtTime(s.check_in_at)} → ${fmtTime(s.check_out_at)}</span></div>`).join('')}</div>`:'<div class="live-dayoff">No Check In recorded</div>'}<footer><span>Worked <b>${ss.length?minsLabel(c.sec/60):'—'}</b></span><span>Net <b>${ss.length?minsLabel(c.net):'—'}</b></span><span>OT <b>${c.ot?otText(c.ot):'—'}</b></span><span>Late <b>${lm?`${lm}m`:'—'}</b></span></footer></article>`}).join(''):'<div class="live-empty">No attendance record for selected date.</div>'}
  async function loadHistory(){const month=$('liveHistoryMonth')?.value||new Date().toISOString().slice(0,7);if($('liveHistoryMonth'))$('liveHistoryMonth').value=month;try{const d=await rpc('staff_live_attendance_history',{p_token:ctx().token,p_month:month+'-01'});if(!current)current={rules:d.rules||{}};else current.rules=d.rules||current.rules;historyRows=d.rows||[];renderHistory()}catch(e){toast(e.message,true)}}
  function clearDateFilter(){if($('liveHistoryDate'))$('liveHistoryDate').value='';renderHistory()}
  function downloadPDF(){const rows=filteredHistory();if(!rows.length)return toast('No attendance data to export.',true);if(!window.jspdf?.jsPDF)return toast('PDF library is still loading.',true);const {jsPDF}=window.jspdf,doc=new jsPDF({orientation:'landscape'}),staff=current?.staff?.name||ctx()?.staff?.name||'Staff',month=$('liveHistoryMonth')?.value||'',date=$('liveHistoryDate')?.value||'';let duty=0,off=0,work=0,ot=0,late=0,split=0;rows.forEach(r=>{const c=calcRow(r),ss=activeSessions(r);if(ss.length){duty++;work+=c.sec/60;ot+=c.ot;if(derivedLate(r)>0)late++;if(ss.length>1)split++}else off++});doc.setFontSize(18);doc.text('GOYA - Live Attendance Report',14,16);doc.setFontSize(10);doc.text(`Staff: ${staff}   Period: ${date||month}`,14,24);doc.text(`Duty Days: ${duty}   Day Off: ${off}   Working: ${minsLabel(work)}   OT: ${otText(ot)}   Late Days: ${late}   Split Shifts: ${split}`,14,31);doc.autoTable({startY:37,head:[['Date','Shift Sessions','Working Time','Worked','Net','OT','Late','Break','Status']],body:rows.map(r=>{const c=calcRow(r),ss=activeSessions(r),lm=derivedLate(r);return [r.operational_date,ss.length,ss.length?ss.map((s,i)=>`S${i+1} ${fmtTime(s.check_in_at)}-${fmtTime(s.check_out_at)}`).join(' | '):'—',ss.length?minsLabel(c.sec/60):'—',ss.length?minsLabel(c.net):'—',c.ot?otText(c.ot):'—',lm?`${lm} min`:'—',ss.length?(r.break_taken!==false?'Yes':'No'):'—',statusLabel(r)]}),styles:{fontSize:8,cellPadding:2},headStyles:{fillColor:[48,81,70]}});const safe=staff.replace(/[^a-z0-9]+/gi,'_').replace(/^_|_$/g,'');doc.save(`Goya_Live_Attendance_${safe}_${date||month}.pdf`)}
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
    if(!document.documentElement.dataset.goyaLivePunchDelegatedV23){
      document.documentElement.dataset.goyaLivePunchDelegatedV23='1';
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
