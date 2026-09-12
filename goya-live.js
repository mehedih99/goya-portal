(() => {
  'use strict';
  const cfg = window.GOYA_CONFIG || {};
  const state = { data:null, rows:[], rules:{}, filter:'', serverOffset:0, timer:null, refresh:null };
  const $ = id => document.getElementById(id);
  const pad = n => String(n).padStart(2,'0');
  let sb = null;

  async function client(){
    if(!cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY) throw new Error('Supabase configuration is missing.');
    if(!sb) sb = window.supabase.createClient(cfg.SUPABASE_URL,cfg.SUPABASE_ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
    return sb;
  }
  async function rpc(name,args={}){ const c=await client(); const {data,error}=await c.rpc(name,args); if(error) throw new Error(error.message); return data; }
  function toast(msg,err=false){ const host=$('toastHost')||document.body,d=document.createElement('div'); d.className='mgmt-toast'+(err?' err':''); d.textContent=msg; host.appendChild(d); setTimeout(()=>d.remove(),3600); }
  const fmtTime=v=>{if(!v)return '—';const d=new Date(v);return Number.isNaN(d.getTime())?'—':d.toLocaleTimeString('en-AE',{hour:'numeric',minute:'2-digit'})};
  const mins=m=>{m=Math.max(0,Math.floor(Number(m)||0));return `${Math.floor(m/60)}h ${pad(m%60)}m`};
  const clock=s=>{s=Math.max(0,Math.floor(Number(s)||0));return `${pad(Math.floor(s/3600))}:${pad(Math.floor((s%3600)/60))}:${pad(s%60)}`};

  function group(d){
    const dm=new Map((d.days||[]).map(x=>[x.staff_id,x])), sm=new Map();
    for(const x of d.sessions||[]){ if(!sm.has(x.staff_id))sm.set(x.staff_id,[]); sm.get(x.staff_id).push(x); }
    for(const arr of sm.values()) arr.sort((a,b)=>(a.session_no||0)-(b.session_no||0));
    return (d.staff||[]).map(s=>({...(dm.get(s.id)||{operational_date:d.operational_date,break_taken:true,classification:'Day Off - Pending Review',late_minutes:0}),staff_id:s.id,staff_name:s.name,sessions:sm.get(s.id)||[]}));
  }
  function status(r){const ss=r.sessions||[];if(ss.some(x=>!x.check_out_at))return 'On Duty';if(ss.length)return 'Shift Done';return r.classification||'Day Off - Pending Review'}
  function review(r){const ss=r.sessions||[];if(!ss.length)return status(r)==='Day Off - Pending Review';return ss.some(x=>x.check_in_verified===false || (x.check_out_at && x.check_out_verified===false))}
  function calc(r,serverNow){
    const rules=state.rules||{},ss=r.sessions||[];let sec=0;const now=serverNow?new Date(serverNow).getTime():Date.now()+state.serverOffset;
    ss.forEach((x,i)=>{if(!x?.check_in_at)return;let st=new Date(x.check_in_at).getTime();if(i===0&&r.scheduled_start){const sch=new Date(`${r.operational_date}T${String(r.scheduled_start).slice(0,5)}:00+04:00`).getTime();if(Number.isFinite(sch)&&st<sch)st=sch}const en=x.check_out_at?new Date(x.check_out_at).getTime():now;if(Number.isFinite(st)&&Number.isFinite(en)&&en>st)sec+=(en-st)/1000});
    const regular=Math.max(1,Number(rules.regular_net_minutes)||480),breakMinutes=Math.max(0,Number(rules.break_minutes)||60),breakTaken=r.break_taken!==false,target=breakTaken?regular+breakMinutes:regular,net=Math.max(0,sec/60-(breakTaken?breakMinutes:0)),ot=Math.floor(Math.max(0,net-regular)/30)*30,remainingSeconds=Math.max(0,target*60-sec),liveOtSeconds=Math.max(0,sec-target*60);
    return {sec,net,ot,remainingSeconds,liveOtSeconds};
  }
  function matches(r){if(!state.filter)return true;if(state.filter==='On Duty')return status(r)==='On Duty';if(state.filter==='Shift Done')return status(r)==='Shift Done';if(state.filter==='Late')return Number(r.late_minutes||0)>0;if(state.filter==='Review')return review(r);return true}

  function render(){
    const rows=state.rows||[];let on=0,done=0,rev=0,late=0;
    rows.forEach(r=>{if(status(r)==='On Duty')on++;if(status(r)==='Shift Done')done++;if(review(r))rev++;if(Number(r.late_minutes||0)>0)late++});
    $('mgmtOn').textContent=on;$('mgmtDone').textContent=done;$('mgmtReview').textContent=rev;$('mgmtLate').textContent=late;
    document.querySelectorAll('.summary-card').forEach(b=>b.classList.toggle('active',b.dataset.filter===state.filter));
    const picked=rows.filter(matches).filter(r=>status(r)!=='Day Off - Pending Review'||state.filter==='Review');
    $('mgmtPanelTitle').textContent=state.filter||'Attendance';
    $('mgmtList').innerHTML=picked.length?picked.map(r=>{const c=calc(r),ss=r.sessions||[],open=status(r)==='On Duty',st=status(r);return `<div class="staff-row ${open?'row-live':''}"><div class="staff-name"><strong>${open?'<i class="pulse"></i>':''}${escapeHtml(r.staff_name)}</strong><span>${escapeHtml(st)}${r.late_minutes?` · Late ${Number(r.late_minutes)}m`:''}</span></div><div class="metric"><small>Check In</small><b>${fmtTime(ss[0]?.check_in_at)}</b></div><div class="metric"><small>Working</small><b>${mins(c.sec/60)}</b></div><div class="metric"><small>${open?(c.remainingSeconds>0?'Remaining':'OT'):'Net'}</small><b class="${open&&c.remainingSeconds<=0?'ot':'remaining'}">${open?(c.remainingSeconds>0?clock(c.remainingSeconds):clock(c.liveOtSeconds)):mins(c.net)}</b></div><div class="metric"><small>Sessions</small><b>${ss.length}</b></div><span class="status-pill ${open?'on':review(r)?'review':''}">${escapeHtml(st)}</span></div>`}).join(''):'<div class="empty-state">No attendance records in this view.</div>';
    const d=new Date(Date.now()+state.serverOffset);$('mgmtUpdated').textContent=`Updated ${d.toLocaleTimeString('en-AE',{hour:'numeric',minute:'2-digit',second:'2-digit'})}`;
  }
  function escapeHtml(v){return String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]))}

  async function load(){
    try{
      const date=$('mgmtDate').value||null;
      const d=await rpc('attendance_live_public_dashboard',{p_date:date});
      state.data=d; if(!$('mgmtDate').value)$('mgmtDate').value=d.operational_date; state.rules=d.rules||{}; state.serverOffset=new Date(d.server_now).getTime()-Date.now(); state.rows=group(d); render(); clearInterval(state.timer); state.timer=setInterval(render,1000);
    }catch(e){ $('mgmtList').innerHTML=`<div class="empty-state error">${escapeHtml(e.message)}</div>`; toast(e.message,true); }
  }

  function summary(rows){
    const by=new Map();
    for(const r of rows){if(!by.has(r.staff_id))by.set(r.staff_id,{name:r.staff_name,duty:0,off:0,work:0,net:0,ot:0,late:0,split:0});const x=by.get(r.staff_id),ss=r.sessions||[],st=status(r),c=calc(r,r.server_now);if(ss.length){x.duty++;x.work+=c.sec/60;x.net+=c.net;x.ot+=c.ot;if(Number(r.late_minutes||0)>0)x.late++;if(ss.length>1)x.split++}else if(/Leave|Off|Holiday|Absent|Sick/i.test(st))x.off++;}
    return [...by.values()].sort((a,b)=>a.name.localeCompare(b.name));
  }
  async function downloadMonth(){
    try{
      const month=$('mgmtMonth').value;if(!month)return toast('Select month first.',true);
      const d=await rpc('attendance_live_public_month',{p_month:month+'-01'});state.rules=d.rules||state.rules;state.serverOffset=new Date(d.server_now).getTime()-Date.now();const data=summary(d.rows||[]);if(!data.length)return toast('No attendance for selected month.',true);if(!window.jspdf?.jsPDF)return toast('PDF library is still loading.',true);
      const {jsPDF}=window.jspdf,doc=new jsPDF({orientation:'landscape'}),total=data.reduce((a,x)=>a+x.ot,0);doc.setFontSize(19);doc.text('GOYA LIVE - Management Monthly Attendance',14,17);doc.setFontSize(10);doc.text(`Period: ${month}   Staff: ${data.length}   Total OT: ${mins(total)}`,14,25);doc.autoTable({startY:31,head:[['Staff','Duty Days','Off / Leave','Working','Net','OT','Late Days','Split Shifts']],body:data.map(x=>[x.name,x.duty,x.off,mins(x.work),mins(x.net),x.ot?mins(x.ot):'0',x.late,x.split]),styles:{fontSize:9,cellPadding:2.6},headStyles:{fillColor:[39,45,48]},alternateRowStyles:{fillColor:[246,247,247]}});doc.save(`Goya_Live_Management_${month}.pdf`);
    }catch(e){toast(e.message,true)}
  }
  async function init(){
    const now=new Date(),month=`${now.getFullYear()}-${pad(now.getMonth()+1)}`;$('mgmtMonth').value=month;
    document.querySelectorAll('.summary-card').forEach(b=>b.addEventListener('click',()=>{state.filter=state.filter===b.dataset.filter?'':b.dataset.filter;render()}));$('mgmtAll').onclick=()=>{state.filter='';render()};$('mgmtDate').onchange=load;$('mgmtRefresh').onclick=load;$('mgmtPdf').onclick=downloadMonth;
    await load();clearInterval(state.refresh);state.refresh=setInterval(load,30000);
    if('serviceWorker' in navigator) navigator.serviceWorker.register('goya-live-sw.js').catch(()=>{});
  }
  window.addEventListener('DOMContentLoaded',init);
})();
