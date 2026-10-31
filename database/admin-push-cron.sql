-- Reuses the existing private worker authentication/VAPID configuration without reading or replacing secrets.
create function goya_private.run_admin_notifications() returns bigint language plpgsql security definer set search_path='' as $$
declare token text;request_id bigint;
begin
 if not exists(select 1 from goya_private.admin_push_deliveries x join goya_private.admin_push_devices d on d.id=x.device_id and d.active join public.app_sessions s on s.token=d.session_token and s.is_admin and s.expires_at>now() join goya_private.admin_notifications n on n.id=x.notification_id and n.created_at>now()-interval '1 day' where x.sent_at is null and x.cancelled_at is null and x.attempts<3 and (x.claimed_at is null or x.claimed_at<now()-interval '3 minutes')) then return null;end if;
 select worker_token into token from goya_private.push_config where id;
 select net.http_post(url:='https://yudrsojnfucvdigehkku.supabase.co/functions/v1/admin-notifications',headers:=jsonb_build_object('Content-Type','application/json','x-goya-worker',token),body:='{}'::jsonb,timeout_milliseconds:=15000) into request_id;
 return request_id;
end $$;
revoke all on function goya_private.run_admin_notifications() from public,anon,authenticated;
select cron.schedule('goya-admin-notifications','* * * * *','select goya_private.run_admin_notifications();');
