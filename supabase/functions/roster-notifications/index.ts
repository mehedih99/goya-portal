import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import webpush from "npm:web-push@3.6.7";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

Deno.serve(async request => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const supplied = request.headers.get("x-goya-worker");
  if (!supplied) return new Response("Unauthorized", { status: 401 });
  const { data: config, error } = await db.rpc("goya_push_worker_config");
  if (error || !config) return new Response("Unavailable", { status: 503 });
  if (supplied !== config.worker_token) return new Response("Unauthorized", { status: 401 });
  webpush.setVapidDetails("https://mehedih99.github.io/goya-portal/staff.html", config.public_key, config.private_key);

  const { data: jobs, error: claimError } = await db.rpc('goya_branches_worker_claim',{p_operation:'goya_roster_push_claim'});
  if (claimError) return new Response("Unavailable", { status: 503 });
  for (let offset = 0; offset < jobs.length; offset += 5) {
    await Promise.all(jobs.slice(offset, offset + 5).map(async job => {const scoped={rpc:(name:string,args:Record<string,unknown>)=>db.rpc('goya_branch_worker_call',{p_branch:job.branch_id,p_operation:name,p_args:args})};
      const payload = { p_week: job.week_start, p_revision: job.revision, p_subscription: job.subscription_id };
      const { data: active } = await scoped.rpc('goya_roster_push_check', payload);
      if (!active) return;
      let sent = false, expired = false;
      try {
        await webpush.sendNotification(job.subscription, JSON.stringify({
          title: job.branch_name+" · Weekly schedule",
          body: "Your weekly schedule is ready in My Schedule.",
          tag: "goya-roster-" + job.branch_id + "-" + job.week_start,
          url: "./staff.html?branch="+encodeURIComponent(job.branch_id),
        }), { TTL: 300, timeout: 10000 });
        sent = true;
      } catch (error) {
        expired = [404, 410].includes((error as { statusCode?: number }).statusCode ?? 0);
      }
      await scoped.rpc('goya_roster_push_result', { ...payload, p_sent: sent, p_expired: expired });
    }));
  }
  return Response.json({ ok: true });
});

