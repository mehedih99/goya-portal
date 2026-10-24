(() => {
 'use strict';
 const $=id=>document.getElementById(id),ctx=()=>window.GoyaStaff?._liveContext?.()||{},esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 let db,data=null,loading=false,noticeIndex=0,paused=false,noticeTimer=null,tickTimer=null,refreshTimer=null,offset=0,pushBusy=false,pushEnabled=false,registration=null,requestId=0;
 const mins=n=>{n=Math.max(0,Math.floor(Number(n)||0));return `${Math.floor(n/60)}h ${String(n%60).padStart(2,'0')}m`;};
 const uae=v=>v?new Date(v).toLocaleTimeString('en-AE',{hour:'numeric',minute:'2-digit',timeZone:'Asia/Dubai'}):'—';
 async function rpc(name,args={}){const token=ctx().token;if(!token)throw Error('Please sign in again.');if(!db)db=window.supabase.createClient(GOYA_CONFIG.SUPABASE_URL,GOYA_CONFIG.SUPABASE_ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});const {data,error}=await db.rpc(name,{p_token:token,...args});if(error)throw Error(error.message);return data;}
 function visible(){return !$('staffDashboard')?.classList.contains('hidden')&&!document.hidden;}
 function totals(row,rules={},live=false){
  if(row.legacy_precalc)return row.legacy_precalc;
  let work=0;const now=Date.now()+offset;
  for(const s of row.sessions||[]){const a=Date.parse(s.check_in_at),b=s.check_out_at?Date.parse(s.check_out_at):(live?now:a);if(Number.isFinite(a)&&Number.isFinite(b)&&b>a)work+=(b-a)/60000;}
  const regular=Number(rules.regular_net_minutes??480),breakMinutes=Number(rules.break_minutes??60),breakTaken=live&&rules.force_no_break?false:row.break_taken!==false;
  const target=regular+(breakTaken?breakMinutes:0),net=Math.max(0,work-(breakTaken?breakMinutes:0));return {work,net,ot:Math.max(0,Math.floor(net-regular)),target,breakTaken};
 }
 function mergedMonth(payload){
  const final=new Map((payload.legacy?.records||[]).map(r=>[r.operational_date,r])),legacy=new Map();
  for(const r of payload.legacy?.submissions||[])if(!legacy.has(r.operational_date))legacy.set(r.operational_date,r);
  for(const [date,r]of final)legacy.set(date,r);
  const converted=new Map([...legacy].map(([date,r])=>{const ss=r.day_off?[]:[{check_in_at:r.punch_in,check_out_at:r.punch_out},...(r.split_shift?[{check_in_at:r.shift2_in,check_out_at:r.shift2_out}]:[])].filter(s=>s.check_in_at);const c=totals({sessions:ss,break_taken:r.break_taken},payload.today?.rules);const net=r.net_work_minutes==null?c.net:Number(r.net_work_minutes);return[date,{operational_date:date,classification:r.day_off?'Day Off':'Duty',late_minutes:Number(r.late_minutes)||0,sessions:ss,legacy:true,legacy_precalc:{...c,net,ot:Math.max(0,Math.floor(net-480))}}];}));
  const result=[];for(const r of payload.attendance?.rows||[]){if(!(r.sessions||[]).length&&r.classification==='Day Off - Pending Review'&&converted.has(r.operational_date))result.push(converted.get(r.operational_date));else result.push(r);converted.delete(r.operational_date);}return [...result,...converted.values()];
 }
 function needsReview(r,today){const ss=r.sessions||[];return (!ss.length&&r.classification==='Day Off - Pending Review'&&r.operational_date<today)||ss.some(s=>s.check_in_verified===false||s.check_out_at&&s.check_out_verified===false||!s.check_out_at&&r.operational_date<today);}
 function render(){
  if(!data)return;const name=ctx().user?.name||'Staff',hour=Number(new Intl.DateTimeFormat('en-GB',{hour:'2-digit',hourCycle:'h23',timeZone:'Asia/Dubai'}).format(new Date(Date.now()+offset)));
  $('dashGreeting').textContent=`Good ${hour<12?'morning':hour<17?'afternoon':'evening'}, ${name}`;
  $('dashDate').textContent=new Date(Date.now()+offset).toLocaleDateString('en-AE',{weekday:'long',day:'numeric',month:'long',year:'numeric',timeZone:'Asia/Dubai'});
  const orders=data.orders||{};$('dashOrders').innerHTML=['Pending','Ordered','Received','Not Received'].map(st=>`<button class="dash-order-stat ${st==='Pending'?'pending':''}" ${['Pending','Ordered'].includes(st)?`onclick="GoyaStaff.openDashboardOrders('${st}')"`:'onclick="GoyaStaff.openMonthHistory()"'}><strong>${Number(orders[st])||0}</strong><span>${esc(st)}</span><small>${['Pending','Ordered'].includes(st)?'All dates':'This month'}</small></button>`).join('');
  $('dashMonthLabel').textContent=new Date(data.month+'T12:00:00').toLocaleDateString('en-AE',{month:'long',year:'numeric'});
  const rows=mergedMonth(data),summary={duty:0,off:0,leave:0,net:0,ot:0,late:0,review:0};
  const today=data.today.operational_date;
  for(const r of rows){const ss=r.sessions||[],c=totals(r,data.today.rules,false);if(ss.length){summary.duty++;summary.net+=c.net;summary.ot+=c.ot;}else if(['Weekly Off','Day Off','Public Holiday'].includes(r.classification))summary.off++;else if(/Leave/.test(r.classification||''))summary.leave++;if(Number(r.late_minutes)>0)summary.late++;if(needsReview(r,today))summary.review++;}
  $('dashMonthly').innerHTML=[['Duty Days',summary.duty],['Off / Holiday',summary.off],['Leave',summary.leave],['Net Hours',mins(summary.net)],['Overtime',mins(summary.ot)],['Late Days',summary.late]].map(([k,v])=>`<div><span>${k}</span><strong>${v}</strong></div>`).join('');
  $('dashAttention').textContent=summary.review?`${summary.review} attendance record${summary.review===1?'':'s'} need review. Open My Attendance for details.`:'No outstanding attendance issues.';
  const a=ctx().user?.access||{};$('dashQuick').innerHTML=[['Order History','staffHistory',true],['Production','staffProduction',a.production],['Wastage','staffWastage',a.wastage],['Inventory','staffInventory',a.inventory||(ctx().data?.inventory_sessions||[]).length],['Additional Info','staffInfo',(ctx().data?.info_pages||[]).length],['Feedback','staffComplaint',true]].filter(x=>x[2]).map(([label,id])=>`<button class="btn secondary" onclick="GoyaDashboard.go('${id}')">${label} →</button>`).join('');
  $('dashOperations').textContent=`Team activity this month: ${Number(data.operations?.production)||0} production entries · ${Number(data.operations?.wastage)||0} wastage entries`;
  renderNotice();renderClock();
 }
 function renderClock(){if(!data)return;const d=data.today,ss=d.sessions||[],open=ss.find(s=>!s.check_out_at),row={...(d.day||{}),sessions:ss},c=totals(row,d.rules,true),status=open?'On Duty':ss.length?'Completed':d.day?.classification&&d.day.classification!=='Day Off - Pending Review'?d.day.classification:'Not checked in yet';
  $('dashTodayStatus').textContent=status;$('dashTodayStatus').classList.toggle('on',!!open);$('dashCheckIn').textContent=uae(ss[0]?.check_in_at);const outs=ss.filter(s=>s.check_out_at).sort((a,b)=>Date.parse(b.check_out_at)-Date.parse(a.check_out_at));$('dashCheckOut').textContent=uae(outs[0]?.check_out_at);
  $('dashWorked').textContent=mins(c.work);$('dashTarget').textContent=mins(c.target);$('dashBreak').textContent=d.rules?.force_no_break?'No break · set by Admin':c.breakTaken?'Break included':'No break';$('dashRemaining').textContent=mins(Math.ceil(Math.max(0,c.target-c.work)));$('dashProgress').value=Math.min(100,c.work/c.target*100);
  $('dashReminderTime').textContent=open?(c.work>=c.target?'Duty target reached':`Reminder ${c.work>=c.target-15?'is due now':`in ${mins(Math.ceil(c.target-15-c.work))}`} · ${c.target/60}h target`):'Reminder runs only while checked in';
 }
 function renderNotice(){const ns=data?.notices||[];if(!ns.length){$('dashNoticeContent').innerHTML='<span class="dash-eyebrow">NOTICE BOARD</span><h2>No new notices</h2><p>Management updates will appear here.</p>';$('dashNoticeControls').hidden=true;return;}
 noticeIndex=((noticeIndex%ns.length)+ns.length)%ns.length;const n=ns[noticeIndex];$('dashNoticeContent').innerHTML=`<span class="dash-eyebrow">NOTICE BOARD ${n.important?'<b class="dash-important">IMPORTANT</b>':''}</span><h2>${esc(n.title)}</h2><p>${esc(n.body)}</p><small>Management · ${esc(new Date(n.updated_at).toLocaleDateString('en-AE',{day:'numeric',month:'short',timeZone:'Asia/Dubai'}))}</small>`;
 $('dashNoticeControls').hidden=ns.length<2;$('dashNoticePosition').textContent=`${noticeIndex+1} / ${ns.length}`;$('dashNoticePause').textContent=paused?'Play':'Pause';$('dashNoticePause').setAttribute('aria-pressed',String(paused));}
 function step(n){noticeIndex+=n;renderNotice();}function togglePause(){paused=!paused;renderNotice();}
 async function open(force=false){if(loading||!ctx().token)return;if(data&&!force){renderClock();return;}const id=++requestId,token=ctx().token;loading=true;$('dashLoading').hidden=false;$('dashError').textContent='';
  try{const result=await rpc('goya_staff_dashboard');if(id!==requestId||token!==ctx().token)return;data=result;offset=Date.parse(data.server_now)-Date.now();render();await syncPushState();}
  catch(e){if(id===requestId)$('dashError').textContent='Dashboard could not refresh: '+e.message+' Use Refresh to retry. Other sections remain available.';}
  finally{if(id===requestId){loading=false;$('dashLoading').hidden=true;}}
 }
 function go(id){if(id==='staffHistory')return window.GoyaStaff.openMonthHistory();const btn=document.querySelector(`.nav button[onclick*="'${id}'"]`);window.GoyaStaff.nav(btn,id);if(id==='staffLiveAttendance')window.GoyaLiveAttendance.open();}
 async function serviceWorker(){if(!('serviceWorker'in navigator))throw Error('This browser does not support reminders.');if(!registration)registration=await navigator.serviceWorker.register('sw.js');return navigator.serviceWorker.ready;}
 async function syncPushState(){const label=$('dashPushStatus');if(!('Notification'in window)||!('PushManager'in window)){label.textContent='Push reminders are not supported here. On iPhone, add this portal to the Home Screen first.';return;}
  try{const reg=await serviceWorker(),sub=await reg.pushManager.getSubscription();pushEnabled=sub?!!(await rpc('goya_staff_push_state',{p_endpoint:sub.endpoint})).enabled:false;label.textContent=Notification.permission==='denied'?'Notifications are blocked in browser settings.':pushEnabled?'Reminders enabled on this device.':'Reminders are off on this device.';$('dashPushEnable').textContent=pushEnabled?'Disable reminders':'Enable reminders';}catch{label.textContent='Reminders are unavailable. Try again when connected.';}
 }
 function keyBytes(s){const raw=atob(s.replace(/-/g,'+').replace(/_/g,'/'));return Uint8Array.from(raw,c=>c.charCodeAt(0));}
 async function togglePush(){if(pushBusy)return;pushBusy=true;$('dashPushEnable').disabled=true;try{
  if(!('Notification'in window)||!('PushManager'in window))throw Error('Use a supported browser. On iPhone, add the portal to the Home Screen and open it from there.');
  if(!pushEnabled){const permission=await Notification.requestPermission();if(permission!=='granted')throw Error('Allow notifications in your device/browser settings to receive reminders.');}
  const reg=await serviceWorker();let sub=await reg.pushManager.getSubscription();
  if(pushEnabled){if(sub){await rpc('goya_staff_push',{p_subscription:sub.toJSON(),p_enabled:false});await sub.unsubscribe();}}
  else{if(!data?.push_public_key)throw Error('Reminders are not configured yet.');if(!sub)sub=await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:keyBytes(data.push_public_key)});await rpc('goya_staff_push',{p_subscription:sub.toJSON(),p_enabled:true});}
  await syncPushState();
 }catch(e){$('dashPushStatus').textContent=e.message;}finally{pushBusy=false;$('dashPushEnable').disabled=false;}}
 async function logout(){let sub;try{if(pushEnabled){const reg=await serviceWorker();sub=await reg.pushManager.getSubscription();if(sub)await rpc('goya_staff_push',{p_subscription:sub.toJSON(),p_enabled:false});}}catch{}finally{if(sub)try{await sub.unsubscribe();}catch{}stop();}}
 function stop(){requestId++;data=null;loading=false;clearInterval(tickTimer);clearInterval(refreshTimer);clearInterval(noticeTimer);}
 function init(){if(!$('staffDashboard'))return;paused=!!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;noticeTimer=setInterval(()=>{if(visible()&&!paused&&!$('dashNotice').matches(':hover')&&!$('dashNotice').contains(document.activeElement))step(1);},7000);tickTimer=setInterval(()=>{if(visible())renderClock();},1000);refreshTimer=setInterval(()=>{if(visible())open(true);},90000);
  document.addEventListener('goya:attendance-updated',()=>{data=null;if(visible())open(true);});document.addEventListener('visibilitychange',()=>{if(visible()&&ctx().token)open(true);});}
 window.GoyaDashboard={open,go,step,togglePause,togglePush,logout,stop};document.addEventListener('DOMContentLoaded',init);
})();
