-- Additive dashboard API. Existing portal tables and workflows are preserved.
create schema if not exists goya_private;
revoke all on schema goya_private from public,anon,authenticated;
create table goya_private.notices (
 id uuid primary key default gen_random_uuid(), title text not null check(length(title) between 1 and 160),
 body text not null check(length(body) between 1 and 5000), important boolean not null default false,
 active boolean not null default true, expires_at timestamptz, created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table goya_private.notices enable row level security;
create table goya_private.push_config (id boolean primary key default true check(id),public_key text not null, private_key text not null,worker_token text not null);
alter table goya_private.push_config enable row level security;
create table goya_private.push_subscriptions (
 id uuid primary key default gen_random_uuid(), staff_id uuid not null references public.staff(id),
 endpoint text unique not null check(length(endpoint)<4096), subscription jsonb not null,
 active boolean not null default true, created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
alter table goya_private.push_subscriptions enable row level security;
create index push_sub_staff on goya_private.push_subscriptions(staff_id) where active;
create table goya_private.push_deliveries (
 subscription_id uuid not null references goya_private.push_subscriptions(id), operational_date date not null,
 sent_at timestamptz,claimed_at timestamptz,attempts int not null default 0,error text,
 primary key(subscription_id,operational_date)
);
alter table goya_private.push_deliveries enable row level security;

create function public.goya_staff_dashboard(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare sess public.app_sessions; current_day jsonb; month_start date;
begin
 sess:=public.require_session(p_token,false);
 current_day:=public.staff_live_attendance_status(p_token);
 month_start:=date_trunc('month',timezone('Asia/Dubai',now()))::date;
 return jsonb_build_object('server_now',now(),'today',current_day,'month',month_start,
 'attendance',public.staff_live_attendance_history(p_token,month_start),
 'legacy',public.staff_attendance_month_v12(p_token,month_start),
 'notices',(select coalesce(jsonb_agg(to_jsonb(n) order by n.important desc,n.created_at desc),'[]'::jsonb) from goya_private.notices n where active and (expires_at is null or expires_at>now())),
 'orders',jsonb_build_object('Pending',(select count(*) from public.orders where status='Pending'),'Ordered',(select count(*) from public.orders where status='Ordered'),'Received',(select count(*) from public.orders where status='Received' and created_at>=month_start),'Not Received',(select count(*) from public.orders where status='Not Received' and created_at>=month_start)),
 'operations',jsonb_build_object('production',(select count(*) from public.production_batches where created_at>=month_start),'wastage',(select count(*) from public.wastage_entries where created_at>=month_start)),
 'push_public_key',(select public_key from goya_private.push_config where id));
end $$;
revoke all on function public.goya_staff_dashboard(text) from public;
grant execute on function public.goya_staff_dashboard(text) to anon,authenticated;

create function public.goya_staff_open_orders(p_token text,p_status text default 'Pending') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform public.require_session(p_token,false);
 if p_status not in ('Pending','Ordered') then raise exception 'Invalid open order status'; end if;
 return jsonb_build_object('orders',(select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb) from (select o.id,g.order_no,o.name,o.sku,o.quantity,o.unit,o.supplier,o.status,o.received_date,o.logged_by,o.notes,o.created_at from public.orders o join public.order_groups g on g.id=o.order_group_id where o.status=p_status)q));
end $$;
revoke all on function public.goya_staff_open_orders(text,text) from public;
grant execute on function public.goya_staff_open_orders(text,text) to anon,authenticated;

create function public.goya_admin_notices(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
begin perform public.require_session(p_token,true);return (select coalesce(jsonb_agg(to_jsonb(n) order by n.created_at desc),'[]'::jsonb) from goya_private.notices n);end $$;
create function public.goya_admin_save_notice(p_token text,p_value jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare n goya_private.notices; nid uuid:=nullif(p_value->>'id','')::uuid;
begin
 perform public.require_session(p_token,true);
 if length(trim(coalesce(p_value->>'title','')))=0 or length(trim(coalesce(p_value->>'body','')))=0 then raise exception 'Title and notice are required'; end if;
 if nid is null then
 insert into goya_private.notices(title,body,important,active,expires_at) values(trim(p_value->>'title'),trim(p_value->>'body'),coalesce((p_value->>'important')::boolean,false),coalesce((p_value->>'active')::boolean,true),nullif(p_value->>'expires_at','')::timestamptz) returning * into n;
 else
 update goya_private.notices set title=trim(p_value->>'title'),body=trim(p_value->>'body'),important=coalesce((p_value->>'important')::boolean,false),active=coalesce((p_value->>'active')::boolean,true),expires_at=nullif(p_value->>'expires_at','')::timestamptz,updated_at=now() where id=nid returning * into n;
 if not found then raise exception 'Notice not found';end if;
 end if;
 return to_jsonb(n);
end $$;
revoke all on function public.goya_admin_notices(text),public.goya_admin_save_notice(text,jsonb) from public;
grant execute on function public.goya_admin_notices(text),public.goya_admin_save_notice(text,jsonb) to anon,authenticated;

create function public.goya_staff_push(p_token text,p_subscription jsonb,p_enabled boolean default true) returns jsonb language plpgsql security definer set search_path='' as $$
declare sess public.app_sessions; ep text:=p_subscription->>'endpoint';
begin
 sess:=public.require_session(p_token,false);
 if ep is null or ep !~ '^https://(fcm[.]googleapis[.]com|updates[.]push[.]services[.]mozilla[.]com|web[.]push[.]apple[.]com|[a-z0-9-]+[.]notify[.]windows[.]com)/' then raise exception 'Unsupported push provider'; end if;
 if p_enabled and (coalesce(length(p_subscription#>>'{keys,p256dh}'),0)<20 or coalesce(length(p_subscription#>>'{keys,auth}'),0)<10) then raise exception 'Invalid push subscription'; end if;
 if p_enabled then
 insert into goya_private.push_subscriptions(staff_id,endpoint,subscription,active) values(sess.staff_id,ep,p_subscription,true)
 on conflict(endpoint) do update set staff_id=excluded.staff_id,subscription=excluded.subscription,active=true,updated_at=now();
 else update goya_private.push_subscriptions set active=false,updated_at=now() where endpoint=ep and staff_id=sess.staff_id;
 end if;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.goya_staff_push(text,jsonb,boolean) from public;
grant execute on function public.goya_staff_push(text,jsonb,boolean) to anon,authenticated;

-- Worker APIs are executable only by the service role; no browser can claim jobs or read secrets.
create function public.goya_push_worker_config() returns jsonb language sql security definer set search_path='' as $$ select to_jsonb(c) from goya_private.push_config c where id $$;
revoke all on function public.goya_push_worker_config() from public,anon,authenticated;
grant execute on function public.goya_push_worker_config() to service_role;

create function goya_private.due_reminders() returns table(subscription_id uuid,staff_id uuid,operational_date date,target_minutes int,remaining_minutes int,subscription jsonb)
language sql stable security definer set search_path='' as $$
 with rules as (select public.attendance_live_rules() r),
 active as (select s.staff_id,s.operational_date,sum(extract(epoch from(coalesce(s.check_out_at,now())-s.check_in_at))/60) worked,
 bool_or(s.check_out_at is null) is_open from public.attendance_live_sessions s join public.staff st on st.id=s.staff_id and st.active
 where not s.is_deleted and s.operational_date>=public.attendance_live_operational_date(now())-1
 group by s.staff_id,s.operational_date),
 due as (select a.*,case when coalesce((r.r->>'force_no_break')::boolean,false) then 480 when coalesce(d.break_taken,true) then 540 else 480 end target
 from active a cross join rules r left join public.attendance_live_days d using(staff_id,operational_date)
 where a.is_open and now()<=public.attendance_live_cutoff_at(a.operational_date))
 select p.id,p.staff_id,a.operational_date,a.target,greatest(0,ceil(a.target-a.worked)::int),p.subscription
 from due a join goya_private.push_subscriptions p on p.staff_id=a.staff_id and p.active
 where a.worked>=a.target-15 and a.worked<a.target
$$;
revoke all on function goya_private.due_reminders() from public,anon,authenticated;
create function public.goya_push_claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare r record; outv jsonb:='[]';
begin
 for r in select * from goya_private.due_reminders() limit 100 loop
 insert into goya_private.push_deliveries(subscription_id,operational_date,claimed_at,attempts)
 values(r.subscription_id,r.operational_date,now(),1)
 on conflict(subscription_id,operational_date) do update set claimed_at=now(),attempts=goya_private.push_deliveries.attempts+1
 where goya_private.push_deliveries.sent_at is null and goya_private.push_deliveries.attempts<3 and goya_private.push_deliveries.claimed_at<now()-interval '3 minutes';
 if found then outv:=outv||jsonb_build_array(to_jsonb(r));end if;
 end loop;
 return outv;
end $$;
create function public.goya_push_check(p_id uuid,p_date date) returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from goya_private.due_reminders() where subscription_id=p_id and operational_date=p_date) $$;
create function public.goya_push_result(p_id uuid,p_date date,p_ok boolean,p_expired boolean default false) returns void language plpgsql security definer set search_path='' as $$
begin
 update goya_private.push_deliveries set sent_at=case when p_ok then now() else sent_at end,error=case when p_ok then null else 'Push delivery failed' end where subscription_id=p_id and operational_date=p_date;
 if p_expired then update goya_private.push_subscriptions set active=false where id=p_id;end if;
end $$;
revoke all on function public.goya_push_claim(),public.goya_push_check(uuid,date),public.goya_push_result(uuid,date,boolean,boolean) from public,anon,authenticated;
grant execute on function public.goya_push_claim(),public.goya_push_check(uuid,date),public.goya_push_result(uuid,date,boolean,boolean) to service_role;

create function goya_private.force_break_policy() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if coalesce((public.attendance_live_rules()->>'force_no_break')::boolean,false) and new.operational_date>=public.attendance_live_operational_date(now()) then new.break_taken:=false;end if;return new;
end $$;
revoke all on function goya_private.force_break_policy() from public,anon,authenticated;
create trigger enforce_goya_break_policy before insert or update on public.attendance_live_days for each row execute function goya_private.force_break_policy();
create function public.goya_staff_push_state(p_token text,p_endpoint text) returns jsonb language plpgsql security definer set search_path='' as $$
declare sess public.app_sessions;
begin sess:=public.require_session(p_token,false);return jsonb_build_object('enabled',exists(select 1 from goya_private.push_subscriptions where staff_id=sess.staff_id and endpoint=p_endpoint and active));end $$;
revoke all on function public.goya_staff_push_state(text,text) from public;
grant execute on function public.goya_staff_push_state(text,text) to anon,authenticated;
