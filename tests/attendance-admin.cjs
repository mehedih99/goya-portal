// Offline browser regression: every Supabase request is mocked; no production traffic.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {chromium}=require(require.resolve('playwright',{paths:[process.env.CODEX_PRIMARY_RUNTIME_NODE_MODULES||process.cwd()]}));
(async()=>{
const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE_PATH||undefined,args:['--no-sandbox','--disable-dev-shm-usage']});
const page=await browser.newPage({viewport:{width:1440,height:1000},timezoneId:'America/New_York'});
const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.accept());
await page.route('**/*',route=>route.abort());
const root=path.resolve(__dirname,'..');
await page.setContent(fs.readFileSync(path.join(root,'attendance.html'),'utf8').replace(/<script\b[^>]*>[\s\S]*?<\/script>/g,'').replace(/<link\b[^>]*>/g,''));
await page.addStyleTag({content:fs.readFileSync(path.join(root,'attendance.css'),'utf8')+fs.readFileSync(path.join(root,'live-attendance.css'),'utf8')+fs.readFileSync(path.join(root,'attendance-admin.css'),'utf8')});
await page.evaluate(()=>{
window.calls=[];window.writes=[];window.failLegacy=false;window.failStaff='';window.delay=0;window.generatedFiles=[];
window.rows=[
 {staff_id:'a',staff_name:"A O'Brien",operational_date:'2026-10-01',classification:'Day Off - Pending Review',sessions:[]},
 {staff_id:'b',staff_name:'Beta',operational_date:'2026-10-01',classification:'Day Off - Pending Review',sessions:[]},
 {staff_id:'c',staff_name:'Charlie',operational_date:'2026-10-01',classification:'Duty',break_taken:true,sessions:[{id:'s1',session_no:1,check_in_at:'2026-10-01T04:00:00Z',check_out_at:'2026-10-01T14:00:00Z',check_in_verified:true,check_out_verified:true}]}
];
window.GOYA_CONFIG={SUPABASE_URL:'https://test.invalid',SUPABASE_ANON_KEY:'test'};
window.GoyaAttendance={_liveContext:()=>({token:'test',staff:rows.map(r=>({id:r.staff_id,name:r.staff_name}))}),nav:(btn,id)=>{document.querySelectorAll('[data-view]').forEach(x=>x.classList.add('hidden'));document.getElementById(id).classList.remove('hidden')}};
window.supabase={createClient:()=>({rpc:async(name,args)=>{
 calls.push({name,args});if(delay)await new Promise(r=>setTimeout(r,delay));
 if(name==='attendance_legacy_admin_history')return failLegacy?{error:{message:'Legacy unavailable'}}:{data:{rows:[]}};
 if(name==='attendance_live_admin_history')return {data:{rules:{regular_net_minutes:480,break_minutes:60},server_now:'2026-10-23T08:00:00Z',rows:structuredClone(rows.filter(r=>r.operational_date>=args.p_start&&r.operational_date<=args.p_end&&(!args.p_staff_id||args.p_staff_id===r.staff_id)))}};
 writes.push({name,args});if(args.p_staff_id===failStaff)return {error:{message:'Simulated save failure'}};
 if(name==='attendance_live_admin_classify_day')rows.find(r=>r.staff_id===args.p_staff_id).classification=args.p_classification;
 if(name==='attendance_live_admin_set_break')rows.find(r=>r.staff_id===args.p_staff_id).break_taken=args.p_break_taken;
 return {data:{}};
}})};
window.XLSX={utils:{book_new:()=>({SheetNames:[],sheets:[]}),json_to_sheet:x=>x,book_append_sheet:(wb,data,name)=>{wb.SheetNames.push(name);wb.sheets.push(data)}},writeFile:(wb,name)=>generatedFiles.push({type:'xlsx',wb,name})};
window.jspdf={jsPDF:class{constructor(){this.tables=[]}setFontSize(){}text(){}addPage(){}autoTable(o){this.tables.push(o)}save(name){generatedFiles.push({type:'pdf',tables:this.tables,name})}}};
document.getElementById('attLogin').classList.add('hidden');document.getElementById('attApp').classList.remove('hidden');
for(const id of ['liveHistFrom','liveControlFrom'])document.getElementById(id).value='2026-10-01';
for(const id of ['liveHistTo','liveControlDate'])document.getElementById(id).value='2026-10-31';
});
await page.addScriptTag({path:path.join(root,'live-admin.js')});
const run=fn=>page.evaluate(fn);
await run(async()=>{GoyaLiveAdmin.openHistory();await GoyaLiveAdmin.loadHistory();GoyaAttendance.nav(null,'attLiveHistory')});
assert.equal(await page.locator('#liveHistoryAdminRows tr').count(),3);
assert.equal(await page.locator('#attLiveHistory button').filter({hasText:/^(Save|Edit|Delete|Check In|Check Out)$/}).count(),0);
assert.equal(await page.locator('button').filter({hasText:'Device Attendance'}).count(),0);
await run(()=>{GoyaLiveAdmin.exportExcel();GoyaLiveAdmin.exportPDF();GoyaLiveAdmin.exportOvertimeExcel();GoyaLiveAdmin.exportOvertimePDF()});
const out=await run(()=>generatedFiles);assert.equal(out.length,4);assert.equal(out[0].wb.sheets[1].length,3);assert.equal(out[0].wb.sheets[1][2].OT,'1h');assert.ok(out[0].wb.sheets[1][2]['Session Details'].includes('8:00'));
assert.equal(out[2].wb.sheets[0][0]['OT Minutes'],60);
await page.selectOption('#liveHistStatus','Completed');assert.equal(await page.locator('#liveHistoryAdminRows tr').count(),1);
await page.selectOption('#liveHistStatus','');
await run(()=>{document.getElementById('liveHistMonth').value='2028-02';GoyaLiveAdmin.applyMonth();GoyaLiveAdmin.exportExcel()});
assert.equal(await page.inputValue('#liveHistTo'),'2028-02-29');assert.equal(await run(()=>generatedFiles.length),4);
await run(async()=>{document.getElementById('liveHistFrom').value='2026-10-01';document.getElementById('liveHistTo').value='2026-10-31';failLegacy=true;await GoyaLiveAdmin.loadHistory();GoyaLiveAdmin.exportPDF()});assert.equal(await run(()=>generatedFiles.length),4);
await run(async()=>{failLegacy=false;delay=30;const pending=GoyaLiveAdmin.loadHistory();GoyaLiveAdmin.invalidateHistory();await pending;delay=0;GoyaLiveAdmin.exportExcel()});assert.equal(await run(()=>generatedFiles.length),4);
await run(async()=>{GoyaAttendance.nav(null,'attLiveControl');await GoyaLiveAdmin.loadControl();GoyaLiveAdmin.setControlFilter('Review');GoyaLiveAdmin.markControlAll(true);GoyaLiveAdmin.previewBatch('classification')});
assert.equal(await page.locator('#batchPreviewRows tr').count(),2);
await run(async()=>{failStaff='b';await Promise.all([GoyaLiveAdmin.submitBatch(),GoyaLiveAdmin.submitBatch()])});
assert.match(await page.locator('#batchResult').innerText(),/Saved: 1. Failed: 1/);
assert.equal(await run(()=>writes.filter(x=>x.name==='attendance_live_admin_classify_day').length),2);
await run(()=>{GoyaLiveAdmin.closeBatch();failStaff='';GoyaLiveAdmin.setControlFilter('Review');GoyaLiveAdmin.markControlAll(true);GoyaLiveAdmin.previewBatch('classification');rows.find(r=>r.staff_id==='b').sessions=[{id:'new',check_in_at:'2026-10-01T05:00:00Z'}]});
await run(()=>GoyaLiveAdmin.submitBatch());assert.match(await page.locator('#batchResult').innerText(),/Attendance changed/);assert.equal(await run(()=>writes.length),2);
await run(async()=>{GoyaLiveAdmin.closeBatch();GoyaLiveAdmin.setControlFilter('');await GoyaLiveAdmin.editDay('c','2026-10-01')});
assert.equal(await page.locator('[data-field="in"]').inputValue(),'2026-10-01T08:00');
await page.locator('[data-field="out"]').fill('2026-10-01T07:00');await page.locator('#liveEditSessions button').click();assert.equal(await run(()=>writes.length),2);
await run(()=>GoyaLiveAdmin.closeEdit());
await run(()=>{GoyaLiveAdmin.openManualControl('a',"A O'Brien",'CHECK_IN','2026-10-01')});
assert.ok((await page.inputValue('#liveControlTime')).startsWith('2026-10-01T'));
await run(()=>GoyaLiveAdmin.closeControlModal());
await run(()=>document.getElementById('toastHost').replaceChildren());
await page.screenshot({path:'/tmp/goya-control-desktop.png',fullPage:true});
await page.setViewportSize({width:390,height:844});
await page.waitForTimeout(350);
await page.screenshot({path:'/tmp/goya-control-mobile.png',fullPage:true});
assert.deepEqual(errors,[]);assert.equal(await run(()=>writes.some(x=>/delete|archive/.test(x.name))),false);
await run(async()=>{GoyaLiveAdmin.openManualControl('a',"A O'Brien",'CHECK_IN','2026-10-01');document.getElementById('liveControlTime').value='2026-10-01T08:30';await Promise.all([GoyaLiveAdmin.saveManualControl(),GoyaLiveAdmin.saveManualControl()])});
const manual=await run(()=>writes.filter(x=>x.name==='attendance_live_admin_manual_action'));assert.equal(manual.length,1);assert.equal(manual[0].args.p_at,'2026-10-01T04:30:00.000Z');
await run(()=>{GoyaLiveAdmin.toggleControlMark('c|2026-10-01',true);GoyaLiveAdmin.previewBatch('breakNo')});await run(()=>GoyaLiveAdmin.submitBatch());assert.match(await page.locator('#batchResult').innerText(),/Saved: 1. Failed: 0/);assert.equal(await run(()=>rows.find(x=>x.staff_id==='c').break_taken),false);await run(()=>GoyaLiveAdmin.closeBatch());
console.log('PASS: read-only reports, filters, 4 exports, UAE times, leap month, stale/failed reports, batch preview, partial failure, duplicate submit, concurrent record change, invalid session times, desktop/mobile rendering; no live network requests.');
if(process.env.TEST_EXPORT_MODULES){
 const modules=process.env.TEST_EXPORT_MODULES;
 for(const file of ['xlsx/dist/xlsx.full.min.js','jspdf/dist/jspdf.umd.min.js','jspdf-autotable/dist/jspdf.plugin.autotable.min.js'])await page.addScriptTag({path:path.join(modules,file)});
 await run(async()=>{GoyaAttendance.nav(null,'attLiveHistory');await GoyaLiveAdmin.loadHistory()});
 for(const method of ['exportExcel','exportPDF','exportOvertimeExcel','exportOvertimePDF']){
   const pending=page.waitForEvent('download');await page.evaluate(method=>GoyaLiveAdmin[method](),method);const download=await pending;
   const output=path.join('/tmp',download.suggestedFilename());await download.saveAs(output);assert.equal(await download.failure(),null);
   const bytes=fs.readFileSync(output);assert.ok(bytes.length>500);
   if(output.endsWith('.pdf'))assert.equal(bytes.subarray(0,4).toString(),'%PDF');
   else {const XLSX=require(path.join(modules,'xlsx'));const wb=XLSX.read(bytes);assert.ok(wb.SheetNames.length>=1);}
 }
 await page.screenshot({path:'/tmp/goya-report-mobile.png',fullPage:true});
 console.log('PASS: real PDF and XLSX downloads generated and parsed (4 files).');
}
await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
