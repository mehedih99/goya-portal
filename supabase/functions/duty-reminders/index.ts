import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import webpush from 'npm:web-push@3.6.7';
const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
Deno.serve(async req=>{
 if(req.method!=='POST')return new Response('Method not allowed',{status:405});
 try{
  const {data:config,error}=await db.rpc('goya_push_worker_config');
  if(error||!config)return new Response('Unavailable',{status:503});
  const supplied=req.headers.get('x-goya-worker')||'';
  if(!supplied||supplied!==config.worker_token)return new Response('Unauthorized',{status:401});
  webpush.setVapidDetails('https://mehedih99.github.io/goya-portal/staff.html',config.public_key,config.private_key);
  const {data:jobs,error:claimError}=await db.rpc('goya_branches_worker_claim',{p_operation:'goya_push_claim'});
  if(claimError)throw claimError;
  let sent=0,failed=0;
  const list=jobs||[];
  for(let i=0;i<list.length;i+=5){await Promise.all(list.slice(i,i+5).map(async j=>{const scoped={rpc:(name:string,args:Record<string,unknown>)=>db.rpc('goya_branch_worker_call',{p_branch:j.branch_id,p_operation:name,p_args:args})};
   const {data:stillDue,error:checkError}=await scoped.rpc('goya_push_check',{p_id:j.subscription_id,p_date:j.operational_date});
   if(checkError||!stillDue)return;
   try{
    await webpush.sendNotification(j.subscription,JSON.stringify({title:j.branch_name+' · Duty reminder',body:`Your ${j.target_minutes/60}-hour duty target is about ${j.remaining_minutes} minutes away. Check out when your work is complete.`,tag:`goya-duty-${j.branch_id}-${j.operational_date}`,url:'./staff.html?branch='+encodeURIComponent(j.branch_id)}),{TTL:60,urgency:'high',timeout:10000});
    await scoped.rpc('goya_push_result',{p_id:j.subscription_id,p_date:j.operational_date,p_ok:true});sent++;
   }catch(e){await scoped.rpc('goya_push_result',{p_id:j.subscription_id,p_date:j.operational_date,p_ok:false,p_expired:[404,410].includes(e.statusCode)});failed++;}
  }));}
  // Notice queue is independent of attendance rules and never auto-enrols a device.
  let noticeSent=0,noticeFailed=0,noticeQueueError=false;
  const {data:notices,error:noticeError}=await db.rpc('goya_branches_worker_claim',{p_operation:'goya_notice_push_claim'});
  if(noticeError){noticeQueueError=true;}else{
   const batch=notices||[];
   for(let i=0;i<batch.length;i+=5){await Promise.all(batch.slice(i,i+5).map(async j=>{const scoped={rpc:(name:string,args:Record<string,unknown>)=>db.rpc('goya_branch_worker_call',{p_branch:j.branch_id,p_operation:name,p_args:args})};
    const {data:allowed,error:checkError}=await scoped.rpc('goya_notice_push_check',{p_notice:j.notice_id,p_subscription:j.subscription_id});
    if(checkError||!allowed)return;
    try{
     await webpush.sendNotification(j.subscription,JSON.stringify({title:`${j.branch_name} · ${j.title}`,body:String(j.body).slice(0,240),tag:`goya-notice-${j.notice_id}`,url:'./staff.html?branch='+encodeURIComponent(j.branch_id)}),{TTL:300,urgency:'high',timeout:10000});
     await scoped.rpc('goya_notice_push_result',{p_notice:j.notice_id,p_subscription:j.subscription_id,p_ok:true});noticeSent++;
    }catch(e){await scoped.rpc('goya_notice_push_result',{p_notice:j.notice_id,p_subscription:j.subscription_id,p_ok:false,p_expired:[404,410].includes(e.statusCode)});noticeFailed++;}
   }));}
  }
  return Response.json({ok:true,sent,failed,noticeSent,noticeFailed,noticeQueueError});
 }catch{return Response.json({ok:false,error:'Reminder processing failed'},{status:500});}
});

