import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import webpush from 'npm:web-push@3.6.7';
const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
Deno.serve(async req=>{
 if(req.method!=='POST')return new Response('Method not allowed',{status:405});
 try{
  const {data:config,error}=await db.rpc('goya_push_worker_config');
  if(error||!config)return new Response('Unavailable',{status:503});
  if(!req.headers.get('x-goya-worker')||req.headers.get('x-goya-worker')!==config.worker_token)return new Response('Unauthorized',{status:401});
  webpush.setVapidDetails('https://mehedih99.github.io/goya-portal/admin.html',config.public_key,config.private_key);
  const {data:jobs,error:claimError}=await db.rpc('goya_branches_worker_claim',{p_operation:'goya_admin_push_claim'});if(claimError)throw claimError;
  const labels={orders:'Order',production:'Production',wastage:'Wastage',feedback:'Complaint / Feedback',inventory:'Inventory',inventory_shared:'Inventory',equipment:'Equipment / Breakage'};
  let sent=0,failed=0;
  const batch=jobs||[];
  for(let i=0;i<batch.length;i+=5)await Promise.all(batch.slice(i,i+5).map(async j=>{const scoped={rpc:(name:string,args:Record<string,unknown>)=>db.rpc('goya_branch_worker_call',{p_branch:j.branch_id,p_operation:name,p_args:args})};
   const args={p_notification:j.notification_id,p_device:j.device_id};const {data:allowed,error:checkError}=await scoped.rpc('goya_admin_push_check',args);if(checkError||!allowed)return;
   try{await webpush.sendNotification(j.subscription,JSON.stringify({title:`${j.branch_name} · ${labels[j.kind]||'Submission'}`,body:`${String(j.staff_name||'Staff').slice(0,100)} submitted a new record. Open Admin to review.`,tag:`goya-admin-${j.notification_id}`,url:'https://mehedih99.github.io/goya-portal/admin.html?branch='+encodeURIComponent(j.branch_id)+'#notifications'}),{TTL:3600,urgency:'high',timeout:10000});await scoped.rpc('goya_admin_push_result',{...args,p_ok:true});sent++;}
   catch(e){await scoped.rpc('goya_admin_push_result',{...args,p_ok:false,p_expired:[404,410].includes(e.statusCode)});failed++;}
  }));return Response.json({ok:true,sent,failed});
 }catch{return Response.json({ok:false,error:'Admin notification processing failed'},{status:500});}
});

