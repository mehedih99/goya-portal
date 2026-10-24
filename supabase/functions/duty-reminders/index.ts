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
  const {data:jobs,error:claimError}=await db.rpc('goya_push_claim');
  if(claimError)throw claimError;
  let sent=0,failed=0;
  const list=jobs||[];
  for(let i=0;i<list.length;i+=5){await Promise.all(list.slice(i,i+5).map(async j=>{
   const {data:stillDue,error:checkError}=await db.rpc('goya_push_check',{p_id:j.subscription_id,p_date:j.operational_date});
   if(checkError||!stillDue)return;
   try{
    await webpush.sendNotification(j.subscription,JSON.stringify({title:'GOYA · Duty reminder',body:`Your ${j.target_minutes/60}-hour duty target is about ${j.remaining_minutes} minutes away. Check out when your work is complete.`,tag:`goya-duty-${j.operational_date}`,url:'./staff.html'}),{TTL:60,urgency:'high',timeout:10000});
    await db.rpc('goya_push_result',{p_id:j.subscription_id,p_date:j.operational_date,p_ok:true});sent++;
   }catch(e){await db.rpc('goya_push_result',{p_id:j.subscription_id,p_date:j.operational_date,p_ok:false,p_expired:[404,410].includes(e.statusCode)});failed++;}
  }));}
  return Response.json({ok:true,sent,failed});
 }catch{return Response.json({ok:false,error:'Reminder processing failed'},{status:500});}
});
