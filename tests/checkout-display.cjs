// Display-only regression, with all network access blocked.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {chromium}=require(require.resolve('playwright',{paths:[process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES||process.cwd()]}));
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE_PATH||undefined,args:['--no-sandbox']});
 const root=path.resolve(__dirname,'..');
 for(const mode of ['admin','live']){
  const page=await browser.newPage({timezoneId:'America/New_York',viewport:{width:1440,height:1000}}),errors=[];page.on('pageerror',e=>errors.push(e.message));await page.route('**/*',r=>r.abort());
  const name=mode==='admin'?'attendance':'goya-live';
  await page.setContent(fs.readFileSync(path.join(root,name+'.html'),'utf8').replace(/<script\b[^>]*>[\s\S]*?<\/script>/g,'').replace(/<link\b[^>]*>/g,''));
  for(const css of mode==='admin'?['attendance.css','live-attendance.css','attendance-admin.css']:['goya-live.css'])await page.addStyleTag({path:path.join(root,css)});
  await page.evaluate(()=>{
   const session=(n,out)=>({id:'s'+n,session_no:n,check_in_at:'2026-10-23T04:00:00Z',check_out_at:out});
   const rows=[{staff_id:'a',staff_name:'No checkout',classification:'Weekly Off',sessions:[]},{staff_id:'b',staff_name:'Completed',sessions:[session(1,'2026-10-23T14:00:00Z')]},{staff_id:'c',staff_name:'Split shift',sessions:[session(2,'2026-10-23T17:00:00Z'),session(1,'2026-10-23T14:00:00Z')]},{staff_id:'d',staff_name:'Rejoined',sessions:[session(1,'2026-10-23T14:00:00Z'),session(2,null)]}].map(r=>({...r,operational_date:'2026-10-23'}));
   window.GOYA_CONFIG={SUPABASE_URL:'https://test.invalid',SUPABASE_ANON_KEY:'test'};
   window.GoyaAttendance={_liveContext:()=>({token:'test',staff:[]})};
   window.supabase={createClient:()=>({rpc:async(name)=>{if(!['attendance_live_public_dashboard','attendance_live_admin_history','attendance_legacy_admin_history'].includes(name))throw Error('Unexpected RPC '+name);return {data:name==='attendance_legacy_admin_history'?{rows:[]}:{rows,rules:{},server_now:'2026-10-23T18:00:00Z',operational_date:'2026-10-23',staff:rows.map(r=>({id:r.staff_id,name:r.staff_name})),days:rows,sessions:rows.flatMap(r=>r.sessions.map(s=>({...s,staff_id:r.staff_id})))}}}})};
   if(document.getElementById('attApp')){document.getElementById('attLogin').classList.add('hidden');document.getElementById('attApp').classList.remove('hidden');document.querySelectorAll('[data-view]').forEach(x=>x.classList.add('hidden'));document.getElementById('attLiveControl').classList.remove('hidden');document.getElementById('liveControlFrom').value='2026-10-23';document.getElementById('liveControlDate').value='2026-10-23';}
  });
  await page.addScriptTag({path:path.join(root,mode==='admin'?'live-admin.js':'goya-live.js')});
  if(mode==='admin')await page.evaluate(()=>GoyaLiveAdmin.loadControl());else await page.evaluate(()=>window.dispatchEvent(new Event('DOMContentLoaded')));
  await page.waitForFunction(()=>document.querySelectorAll('[data-checkout]').length===4);
  assert.deepEqual(await page.locator('[data-checkout]').allTextContents(),(mode==='admin'?['6:00 PM','—','6:00 PM','9:00 PM']:['—','6:00 PM','9:00 PM','6:00 PM']));
  await page.screenshot({path:'/tmp/goya-checkout-'+mode+'-desktop.png',fullPage:true});
  await page.setViewportSize({width:390,height:844});await page.waitForTimeout(350);
  assert.deepEqual(await page.locator('[data-checkout]').allTextContents(),(mode==='admin'?['6:00 PM','—','6:00 PM','9:00 PM']:['—','6:00 PM','9:00 PM','6:00 PM']));
  await page.screenshot({path:'/tmp/goya-checkout-'+mode+'-mobile.png',fullPage:true});
  assert.deepEqual(errors,[]);await page.close();
 }
 await browser.close();console.log('PASS: both pages show no-checkout, completed, unsorted split shifts and rejoined checkout times in UAE time on desktop/mobile; read-only RPCs only.');
})().catch(e=>{console.error(e);process.exit(1)});
