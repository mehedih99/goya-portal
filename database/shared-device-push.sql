create or replace function public.goya_staff_push_state(p_token text,p_endpoint text) returns jsonb language plpgsql security definer set search_path='' as $$
declare sess public.app_sessions;
begin
 sess:=public.require_session(p_token,false);
 -- The caller possesses this browser's endpoint. Stop reminders for a previous user on this same device.
 update goya_private.push_subscriptions set active=false,updated_at=now() where endpoint=p_endpoint and staff_id<>sess.staff_id and active;
 return jsonb_build_object('enabled',exists(select 1 from goya_private.push_subscriptions where staff_id=sess.staff_id and endpoint=p_endpoint and active));
end $$;
