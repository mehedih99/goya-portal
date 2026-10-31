-- Additive Admin device/session and audited quantity correction APIs. No business data backfill.
create table goya_private.admin_remembered_sessions(session_token text primary key references public.app_sessions(token) on delete cascade,created_at timestamptz not null default now());
create table goya_private.admin_push_devices(id uuid primary key default gen_random_uuid(),session_token text not null references goya_private.admin_remembered_sessions(session_token) on delete cascade,endpoint text unique not null,subscription jsonb not null,active boolean not null default true,updated_at timestamptz not null default now());
create index admin_push_session on goya_private.admin_push_devices(session_token);
create table goya_private.admin_push_deliveries(notification_id bigint not null references goya_private.admin_notifications(id) on delete cascade,device_id uuid not null references goya_private.admin_push_devices(id) on delete cascade,claimed_at timestamptz,sent_at timestamptz,attempts integer not null default 0,error text,cancelled_at timestamptz,primary key(notification_id,device_id));
create index admin_push_pending on goya_private.admin_push_deliveries(notification_id) where sent_at is null and attempts<3;
create table goya_private.pw_quantity_audit(id bigint generated always as identity primary key,request_id uuid unique not null,kind text not null,row_id bigint not null,old_values jsonb not null,new_values jsonb not null,reason text not null,created_at timestamptz not null default now());
create index pw_quantity_audit_row on goya_private.pw_quantity_audit(kind,row_id,id desc);
alter table goya_private.admin_remembered_sessions enable row level security;
alter table goya_private.admin_push_devices enable row level security;
alter table goya_private.admin_push_deliveries enable row level security;
alter table goya_private.pw_quantity_audit enable row level security;
revoke all on goya_private.admin_remembered_sessions,goya_private.admin_push_devices,goya_private.admin_push_deliveries,goya_private.pw_quantity_audit from public,anon,authenticated;
create function public.goya_admin_remember(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform public.require_session(p_token,true);
 insert into goya_private.admin_remembered_sessions(session_token) values(p_token) on conflict do nothing;
 update public.app_sessions set expires_at=now()+interval '30 days' where token=p_token and is_admin;
 return jsonb_build_object('token',p_token);
end $$;
create function public.goya_admin_resume(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform public.require_session(p_token,true);
 if not exists(select 1 from goya_private.admin_remembered_sessions where session_token=p_token) then raise exception using message='DEVICE_LOGIN_REQUIRED',errcode='28000';end if;
 update public.app_sessions set expires_at=now()+interval '30 days' where token=p_token and is_admin;
 return jsonb_build_object('token',p_token,'is_admin',true);
end $$;
create function goya_private.revoke_saved_admin() returns trigger language plpgsql security definer set search_path='' as $$
begin
 update public.app_sessions a set expires_at=least(a.expires_at,now()) where a.is_admin and exists(select 1 from goya_private.admin_remembered_sessions r where r.session_token=a.token);
 update goya_private.admin_push_devices set active=false,updated_at=now();
 return new;
end $$;
revoke all on function goya_private.revoke_saved_admin() from public,anon,authenticated;
create trigger revoke_saved_admin_pin after update of pin_hash on public.admin_credentials for each row when(old.pin_hash is distinct from new.pin_hash) execute function goya_private.revoke_saved_admin();

create function public.goya_admin_push_state(p_token text,p_endpoint text default '') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform public.require_session(p_token,true);
 return jsonb_build_object('public_key',(select public_key from goya_private.push_config where id), 'enabled',exists(select 1 from goya_private.admin_push_devices d join public.app_sessions s on s.token=d.session_token and s.is_admin and s.expires_at>now() where d.endpoint=p_endpoint and d.session_token=p_token and d.active));
end $$;
create function public.goya_admin_push_save(p_token text,p_subscription jsonb,p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
declare ep text:=p_subscription->>'endpoint';
begin
 perform public.require_session(p_token,true);
 if not p_enabled then update goya_private.admin_push_deliveries set cancelled_at=now() where device_id in(select id from goya_private.admin_push_devices where session_token=p_token and endpoint=ep) and sent_at is null;update goya_private.admin_push_devices set active=false,updated_at=now() where session_token=p_token and endpoint=ep;return;end if;
 if not exists(select 1 from goya_private.admin_remembered_sessions where session_token=p_token) then raise exception 'Remember this device before enabling notifications';end if;
 if ep is null or ep!~'^https://' or length(ep)>4096 or length(coalesce(p_subscription#>>'{keys,p256dh}','')) not between 40 and 256 or length(coalesce(p_subscription#>>'{keys,auth}','')) not between 16 and 128 then raise exception 'Invalid push subscription';end if;
 -- Rebinding this browser cancels pending alerts from its previous session.
 update goya_private.admin_push_deliveries set cancelled_at=now() where device_id in(select id from goya_private.admin_push_devices where endpoint=ep and session_token<>p_token) and sent_at is null;
 insert into goya_private.admin_push_devices(session_token,endpoint,subscription,active) values(p_token,ep,p_subscription,true) on conflict(endpoint) do update set session_token=excluded.session_token,subscription=excluded.subscription,active=true,updated_at=now();
end $$;
create function goya_private.queue_admin_push() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into goya_private.admin_push_deliveries(notification_id,device_id)
 select n.id,d.id from new_notifications n cross join goya_private.admin_push_devices d join public.app_sessions s on s.token=d.session_token and s.is_admin and s.expires_at>now() where d.active on conflict do nothing;
 return null;
end $$;
revoke all on function goya_private.queue_admin_push() from public,anon,authenticated;
create trigger queue_admin_submission_push after insert on goya_private.admin_notifications referencing new table as new_notifications for each statement execute function goya_private.queue_admin_push();
create function public.goya_admin_push_claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare r record;outv jsonb:='[]';
begin
 for r in select x.notification_id,x.device_id,d.subscription,n.kind,n.staff_name from goya_private.admin_push_deliveries x join goya_private.admin_push_devices d on d.id=x.device_id and d.active join public.app_sessions s on s.token=d.session_token and s.is_admin and s.expires_at>now() join goya_private.admin_notifications n on n.id=x.notification_id
 where x.sent_at is null and x.cancelled_at is null and x.attempts<3 and n.created_at>now()-interval '1 day' and (x.claimed_at is null or x.claimed_at<now()-interval '3 minutes') order by x.notification_id for update of x skip locked limit 30 loop
 update goya_private.admin_push_deliveries set claimed_at=now(),attempts=attempts+1 where notification_id=r.notification_id and device_id=r.device_id;outv:=outv||jsonb_build_array(to_jsonb(r));
 end loop;return outv;
end $$;
create function public.goya_admin_push_check(p_notification bigint,p_device uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from goya_private.admin_push_deliveries x join goya_private.admin_push_devices d on d.id=x.device_id and d.active join public.app_sessions s on s.token=d.session_token and s.is_admin and s.expires_at>now() join goya_private.admin_notifications n on n.id=x.notification_id and n.created_at>now()-interval '1 day' where x.notification_id=p_notification and x.device_id=p_device and x.sent_at is null and x.cancelled_at is null);
$$;
create function public.goya_admin_push_result(p_notification bigint,p_device uuid,p_ok boolean,p_expired boolean default false) returns void language plpgsql security definer set search_path='' as $$
begin
 update goya_private.admin_push_deliveries set sent_at=case when p_ok then now() else sent_at end,error=case when p_ok then null else 'Push delivery failed' end,attempts=case when p_expired then 3 else attempts end where notification_id=p_notification and device_id=p_device;
 if p_expired then update goya_private.admin_push_devices set active=false,updated_at=now() where id=p_device;end if;
end $$;

create function public.goya_admin_correct_pw(p_token text,p_kind text,p_id bigint,p_expected jsonb,p_quantity numeric,p_bucket text,p_reason text,p_request uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare tab text;oldv jsonb;newv jsonb;u text;sunit text;iunit text;prev goya_private.pw_quantity_audit;
begin
 perform public.require_session(p_token,true);
 if p_kind is null or p_kind not in ('production','wastage') then raise exception 'Invalid record type';end if;
 if p_quantity is null or p_quantity<=0 or p_quantity>99999999999.999 or p_quantity<>round(p_quantity,3) or p_quantity::text in ('NaN','Infinity','-Infinity') or p_bucket is null or p_bucket not in ('storage','ingredients') or p_request is null or length(trim(coalesce(p_reason,''))) not between 1 and 500 then raise exception 'Enter a positive quantity (up to 3 decimals), quantity type and correction reason';end if;
 select * into prev from goya_private.pw_quantity_audit where request_id=p_request;
 if found then if prev.kind<>p_kind or prev.row_id<>p_id or (prev.new_values->>'quantity')::numeric<>p_quantity then raise exception 'Correction reference already used';end if;return jsonb_build_object('saved',true);end if;
 tab:=case when p_kind='production' then 'production_batches' else 'wastage_entries' end;
 execute format('select to_jsonb(x) from public.%I x where id=$1 for update',tab) into oldv using p_id;
 if oldv is null then raise exception 'Record no longer available';end if;
 if (oldv->'quantity') is distinct from (p_expected->'quantity') or (oldv->'unit') is distinct from (p_expected->'unit') or (oldv->'storage_quantity') is distinct from (p_expected->'storage_quantity') or (oldv->'ingredients_quantity') is distinct from (p_expected->'ingredients_quantity') then raise exception 'Quantity changed. Reload and review again';end if;
 select storage_unit,ingredient_unit into sunit,iunit from public.internal_items where sku=oldv->>'sku' limit 1;
 u:=case when p_bucket='storage' then sunit else iunit end;
 if nullif(u,'') is null and (case when p_bucket='storage' then oldv->>'storage_quantity' else oldv->>'ingredients_quantity' end) is not null then u:=oldv->>'unit';end if;
 if nullif(u,'') is null then raise exception 'Unit unavailable. Restore the item catalog before changing quantity type';end if;
 execute format('update public.%I set quantity=$1,unit=$2,storage_quantity=$3,ingredients_quantity=$4 where id=$5 returning to_jsonb(%I.*)',tab,tab) into newv using p_quantity,u,case when p_bucket='storage' then p_quantity else null end,case when p_bucket='ingredients' then p_quantity else null end,p_id;
 insert into goya_private.pw_quantity_audit(request_id,kind,row_id,old_values,new_values,reason) values(p_request,p_kind,p_id,oldv,newv,trim(p_reason));
 return jsonb_build_object('saved',true);
end $$;
create function public.goya_admin_pw_corrections(p_token text,p_kind text,p_id bigint) returns jsonb language plpgsql security definer set search_path='' as $$
begin perform public.require_session(p_token,true);return (select coalesce(jsonb_agg(to_jsonb(q)),'[]') from(select id,old_values,new_values,reason,created_at from goya_private.pw_quantity_audit where kind=p_kind and row_id=p_id order by id desc limit 50)q);end $$;
revoke all on function public.goya_admin_remember(text),public.goya_admin_resume(text),public.goya_admin_push_state(text,text),public.goya_admin_push_save(text,jsonb,boolean),public.goya_admin_correct_pw(text,text,bigint,jsonb,numeric,text,text,uuid),public.goya_admin_pw_corrections(text,text,bigint) from public;
grant execute on function public.goya_admin_remember(text),public.goya_admin_resume(text),public.goya_admin_push_state(text,text),public.goya_admin_push_save(text,jsonb,boolean),public.goya_admin_correct_pw(text,text,bigint,jsonb,numeric,text,text,uuid),public.goya_admin_pw_corrections(text,text,bigint) to anon,authenticated;
revoke all on function public.goya_admin_push_claim(),public.goya_admin_push_check(bigint,uuid),public.goya_admin_push_result(bigint,uuid,boolean,boolean) from public,anon,authenticated;
grant execute on function public.goya_admin_push_claim(),public.goya_admin_push_check(bigint,uuid),public.goya_admin_push_result(bigint,uuid,boolean,boolean) to service_role;
