create extension if not exists pg_cron;
create extension if not exists pg_net;
create function goya_private.run_duty_reminders() returns bigint language plpgsql security definer set search_path='' as $$
declare token text; request_id bigint;
begin
 if not exists(select 1 from goya_private.push_subscriptions where active) then return null;end if;
 select worker_token into token from goya_private.push_config where id;
 select net.http_post(url:='https://yudrsojnfucvdigehkku.supabase.co/functions/v1/duty-reminders',headers:=jsonb_build_object('Content-Type','application/json','x-goya-worker',token),body:='{}'::jsonb,timeout_milliseconds:=15000) into request_id;
 return request_id;
end $$;
revoke all on function goya_private.run_duty_reminders() from public,anon,authenticated;
select cron.schedule('goya-duty-reminders','* * * * *','select goya_private.run_duty_reminders();');
