-- Additive: existing notices keep their original creation date and visibility.
alter table goya_private.notices add column published_at timestamptz;
update goya_private.notices set published_at=created_at where published_at is null;
alter table goya_private.notices alter column published_at set default now();
alter table goya_private.notices alter column published_at set not null;
create or replace function public.goya_admin_save_notice(p_token text,p_value jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare n goya_private.notices; nid uuid:=nullif(p_value->>'id','')::uuid;
begin
 perform public.require_session(p_token,true);
 if length(trim(coalesce(p_value->>'title','')))=0 or length(trim(coalesce(p_value->>'body','')))=0 then raise exception 'Title and notice are required'; end if;
 if nullif(p_value->>'expires_at','')::timestamptz <= coalesce(nullif(p_value->>'published_at','')::timestamptz,case when nid is not null then (select published_at from goya_private.notices where id=nid) end,now()) then raise exception 'Expiry must be after the published date'; end if;
 if nid is null then
 insert into goya_private.notices(title,body,important,active,expires_at,published_at) values(trim(p_value->>'title'),trim(p_value->>'body'),coalesce((p_value->>'important')::boolean,false),coalesce((p_value->>'active')::boolean,true),nullif(p_value->>'expires_at','')::timestamptz,coalesce(nullif(p_value->>'published_at','')::timestamptz,now())) returning * into n;
 else
 update goya_private.notices set title=trim(p_value->>'title'),body=trim(p_value->>'body'),important=coalesce((p_value->>'important')::boolean,false),active=coalesce((p_value->>'active')::boolean,true),expires_at=nullif(p_value->>'expires_at','')::timestamptz,published_at=coalesce(nullif(p_value->>'published_at','')::timestamptz,published_at),updated_at=now() where id=nid returning * into n;
 if not found then raise exception 'Notice not found';end if;
 end if;
 return to_jsonb(n);
end $$;
create or replace function public.goya_staff_dashboard(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare sess public.app_sessions; current_day jsonb; month_start date;
begin
 sess:=public.require_session(p_token,false);
 current_day:=public.staff_live_attendance_status(p_token);
 month_start:=date_trunc('month',timezone('Asia/Dubai',now()))::date;
 return jsonb_build_object('server_now',now(),'today',current_day,'month',month_start,
 'attendance',public.staff_live_attendance_history(p_token,month_start),
 'legacy',public.staff_attendance_month_v12(p_token,month_start),
 'notices',(select coalesce(jsonb_agg(to_jsonb(n) order by n.important desc,n.published_at desc),'[]'::jsonb) from goya_private.notices n where active and published_at<=now() and (expires_at is null or expires_at>now())),
 'orders',jsonb_build_object('Pending',(select count(*) from public.orders where status='Pending'),'Ordered',(select count(*) from public.orders where status='Ordered'),'Received',(select count(*) from public.orders where status='Received' and created_at>=month_start),'Not Received',(select count(*) from public.orders where status='Not Received' and created_at>=month_start)),
 'operations',jsonb_build_object('production',(select count(*) from public.production_batches where created_at>=month_start),'wastage',(select count(*) from public.wastage_entries where created_at>=month_start)),
 'push_public_key',(select public_key from goya_private.push_config where id));
end $$;

-- CREATE OR REPLACE preserves existing grants and session checks.
