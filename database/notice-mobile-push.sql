-- Opt-in notice delivery queue. No existing notice is automatically broadcast.
create table goya_private.notice_push_jobs (
 notice_id uuid primary key references goya_private.notices(id),
 requested_at timestamptz not null default now(),started_at timestamptz,cancelled_at timestamptz
);
alter table goya_private.notice_push_jobs enable row level security;
create table goya_private.notice_push_deliveries (
 notice_id uuid not null references goya_private.notice_push_jobs(notice_id),
 subscription_id uuid not null references goya_private.push_subscriptions(id),
 staff_id uuid not null references public.staff(id),claimed_at timestamptz,sent_at timestamptz,
 attempts int not null default 0,error text,
 primary key(notice_id,subscription_id)
);
alter table goya_private.notice_push_deliveries enable row level security;
revoke all on goya_private.notice_push_jobs,goya_private.notice_push_deliveries from public,anon,authenticated;

-- Preserve the existing save API and its authorization; enqueue atomically with Save.
do $$ declare definition text; begin
 definition:=pg_get_functiondef('public.goya_admin_save_notice(text,jsonb)'::regprocedure);
 if position('return to_jsonb(n);' in definition)=0 then raise exception 'Notice save function changed; review before patching';end if;
 definition:=replace(definition,'return to_jsonb(n);',$patch$
 if coalesce((p_value->>'send_push')::boolean,false) then
  if not n.active or not n.important then raise exception 'Mobile notification requires an Important, published notice';end if;
  if n.expires_at is not null and n.expires_at<=now() then raise exception 'Expired notices cannot send notifications';end if;
  insert into goya_private.notice_push_jobs(notice_id) values(n.id) on conflict(notice_id) do nothing;
 end if;
 if not n.active or not n.important then
  update goya_private.notice_push_jobs set cancelled_at=coalesce(cancelled_at,now()) where notice_id=n.id;
 end if;
 return to_jsonb(n)||jsonb_build_object('push_requested',exists(select 1 from goya_private.notice_push_jobs where notice_id=n.id));
$patch$);
 execute definition;
end $$;

create or replace function public.goya_admin_notices(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform public.require_session(p_token,true);
 return (select coalesce(jsonb_agg(to_jsonb(n)||jsonb_build_object('push',case when j.notice_id is null then null else jsonb_build_object('requested_at',j.requested_at,'started_at',j.started_at,'cancelled_at',j.cancelled_at,'devices',(select count(*) from goya_private.notice_push_deliveries d where d.notice_id=n.id),'sent',(select count(*) from goya_private.notice_push_deliveries d where d.notice_id=n.id and sent_at is not null),'failed',(select count(*) from goya_private.notice_push_deliveries d where d.notice_id=n.id and sent_at is null and attempts>=3)) end) order by n.created_at desc),'[]'::jsonb) from goya_private.notices n left join goya_private.notice_push_jobs j on j.notice_id=n.id);
end $$;

create function public.goya_notice_push_claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare j record; r record; outv jsonb:='[]';
begin
 -- Snapshot recipients exactly once at publication; future opt-ins do not receive old broadcasts.
 for j in select q.notice_id from goya_private.notice_push_jobs q join goya_private.notices n on n.id=q.notice_id
 where q.started_at is null and q.cancelled_at is null and n.active and n.important and n.published_at<=now() and (n.expires_at is null or n.expires_at>now())
 order by q.requested_at for update of q skip locked limit 20 loop
  insert into goya_private.notice_push_deliveries(notice_id,subscription_id,staff_id)
  select j.notice_id,p.id,p.staff_id from goya_private.push_subscriptions p join public.staff s on s.id=p.staff_id and s.active where p.active
  on conflict do nothing;
  update goya_private.notice_push_jobs set started_at=now() where notice_id=j.notice_id;
 end loop;
 for r in select d.notice_id,d.subscription_id,p.subscription,n.title,n.body from goya_private.notice_push_deliveries d
 join goya_private.notices n on n.id=d.notice_id join goya_private.notice_push_jobs q on q.notice_id=d.notice_id and q.cancelled_at is null
 join goya_private.push_subscriptions p on p.id=d.subscription_id and p.staff_id=d.staff_id and p.active
 join public.staff s on s.id=d.staff_id and s.active
 where d.sent_at is null and d.attempts<3 and (d.claimed_at is null or d.claimed_at<now()-interval '3 minutes')
 and n.active and n.important and n.published_at<=now() and (n.expires_at is null or n.expires_at>now())
 order by q.requested_at for update of d skip locked limit 50 loop
  update goya_private.notice_push_deliveries set claimed_at=now(),attempts=attempts+1 where notice_id=r.notice_id and subscription_id=r.subscription_id;
  outv:=outv||jsonb_build_array(to_jsonb(r));
 end loop;
 return outv;
end $$;
create function public.goya_notice_push_check(p_notice uuid,p_subscription uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from goya_private.notice_push_deliveries d join goya_private.notices n on n.id=d.notice_id
 join goya_private.notice_push_jobs q on q.notice_id=n.id and q.cancelled_at is null
 join goya_private.push_subscriptions p on p.id=d.subscription_id and p.staff_id=d.staff_id and p.active
 join public.staff s on s.id=d.staff_id and s.active
 where d.notice_id=p_notice and d.subscription_id=p_subscription and d.sent_at is null and n.active and n.important and n.published_at<=now() and (n.expires_at is null or n.expires_at>now()))
$$;
create function public.goya_notice_push_result(p_notice uuid,p_subscription uuid,p_ok boolean,p_expired boolean default false) returns void language plpgsql security definer set search_path='' as $$
begin
 update goya_private.notice_push_deliveries set sent_at=case when p_ok then now() else sent_at end,error=case when p_ok then null else 'Push delivery failed' end,
 attempts=case when p_expired then 3 else attempts end where notice_id=p_notice and subscription_id=p_subscription;
 if p_expired then update goya_private.push_subscriptions set active=false,updated_at=now() where id=p_subscription;end if;
end $$;
revoke all on function public.goya_notice_push_claim(),public.goya_notice_push_check(uuid,uuid),public.goya_notice_push_result(uuid,uuid,boolean,boolean) from public,anon,authenticated;
grant execute on function public.goya_notice_push_claim(),public.goya_notice_push_check(uuid,uuid),public.goya_notice_push_result(uuid,uuid,boolean,boolean) to service_role;

create or replace function goya_private.run_duty_reminders() returns bigint language plpgsql security definer set search_path='' as $$
declare token text; request_id bigint;
begin
 if not exists(select 1 from goya_private.push_subscriptions where active) and not exists(select 1 from goya_private.notice_push_jobs j join goya_private.notices n on n.id=j.notice_id where j.started_at is null and j.cancelled_at is null and n.active and n.important and n.published_at<=now() and (n.expires_at is null or n.expires_at>now())) then return null;end if;
 select worker_token into token from goya_private.push_config where id;
 select net.http_post(url:='https://yudrsojnfucvdigehkku.supabase.co/functions/v1/duty-reminders',headers:=jsonb_build_object('Content-Type','application/json','x-goya-worker',token),body:='{}'::jsonb,timeout_milliseconds:=15000) into request_id;
 return request_id;
end $$;
