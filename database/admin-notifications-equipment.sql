-- Additive release 49. No backfill, business-row updates or business-row deletes.
-- Existing custom PIN sessions remain the authorization boundary.
create table goya_private.equipment_reports (
 id uuid primary key default gen_random_uuid(), staff_id uuid references public.staff(id) on delete set null,
 staff_name text not null, section text not null, item_name text not null check(length(item_name) between 1 and 160),
 quantity text not null default '' check(length(quantity)<=80), details text not null check(length(details) between 1 and 2000),
 incident_date date not null, created_at timestamptz not null default now(),
 status text not null default 'Pending' check(status in ('Pending','Reviewed','Repaired','Replaced','Closed')),
 admin_note text not null default '' check(length(admin_note)<=1000), version bigint not null default 1,
 updated_at timestamptz not null default now(), request_id uuid not null, unique(staff_id,request_id));
create index equipment_reports_month on goya_private.equipment_reports(incident_date desc,created_at desc,id);
create index equipment_reports_staff on goya_private.equipment_reports(staff_id,incident_date desc);
create table goya_private.equipment_status_history (
 id bigint generated always as identity primary key,report_id uuid not null references goya_private.equipment_reports(id) on delete restrict,
 status text not null,note text not null,created_at timestamptz not null default now());
create index equipment_status_report on goya_private.equipment_status_history(report_id,id);
create table goya_private.admin_notifications (
 id bigint generated always as identity primary key,kind text not null,event_key text not null,source_ref jsonb not null,
 staff_name text not null,created_at timestamptz not null default now(),read_at timestamptz,unique(kind,event_key));
create index admin_notifications_newest on goya_private.admin_notifications(created_at desc,id desc);
create index admin_notifications_unread on goya_private.admin_notifications(id) where read_at is null;
alter table goya_private.equipment_reports enable row level security;
alter table goya_private.equipment_status_history enable row level security;
alter table goya_private.admin_notifications enable row level security;
revoke all on goya_private.equipment_reports,goya_private.equipment_status_history,goya_private.admin_notifications from public,anon,authenticated;

create function public.goya_equipment_submit(p_token text,p_request_id uuid,p_value jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.app_sessions;s public.staff;r goya_private.equipment_reports;d date;v_section text;
begin
 a:=public.require_session(p_token,false);select * into s from public.staff where id=a.staff_id and active;
 if s.id is null then raise exception 'Staff is inactive or unauthorized';end if;
 if p_request_id is null then raise exception 'Submission reference is required';end if;
 select * into r from goya_private.equipment_reports where staff_id=s.id and request_id=p_request_id;
 if r.id is not null then return jsonb_build_object('id',r.id,'saved',true);end if;
 if p_value is null or jsonb_typeof(p_value)<>'object' then raise exception 'Invalid report';end if;
 if length(trim(coalesce(p_value->>'item_name',''))) not between 1 and 160 or length(trim(coalesce(p_value->>'details',''))) not between 1 and 2000
 or length(trim(coalesce(p_value->>'quantity','')))>80 then raise exception 'Enter an equipment name and details within the allowed length';end if;
 d:=(p_value->>'incident_date')::date;v_section:=trim(coalesce(p_value->>'section',''));
 if d is null or d<date '2000-01-01' or d>(now() at time zone 'Asia/Dubai')::date then raise exception 'Choose a valid incident date, no later than today';end if;
 if not(v_section=any(coalesce(s.sections,'{}'::text[]))) and not(v_section='' and cardinality(coalesce(s.sections,'{}'::text[]))=0) then raise exception 'Choose one of your assigned sections';end if;
 insert into goya_private.equipment_reports(staff_id,staff_name,section,item_name,quantity,details,incident_date,request_id)
 values(s.id,s.name,v_section,trim(p_value->>'item_name'),trim(coalesce(p_value->>'quantity','')),trim(p_value->>'details'),d,p_request_id)
 on conflict(staff_id,request_id) do nothing returning * into r;
 if r.id is null then select * into r from goya_private.equipment_reports where staff_id=s.id and request_id=p_request_id;end if;
 return jsonb_build_object('id',r.id,'saved',true);
end $$;

create function public.goya_equipment_list(p_token text,p_month date,p_page integer default 1,p_admin boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.app_sessions;total bigint;pg integer;rows jsonb;m date;
begin
 a:=public.require_session(p_token,p_admin);
 if not p_admin and not exists(select 1 from public.staff where id=a.staff_id and active) then raise exception 'Staff is inactive or unauthorized';end if;
 if p_month is null then raise exception 'Select a month';end if;m:=date_trunc('month',p_month)::date;
 select count(*) into total from goya_private.equipment_reports where incident_date>=m and incident_date<(m+interval '1 month') and (p_admin or staff_id=a.staff_id);
 pg:=greatest(1,least(coalesce(p_page,1),greatest(1,ceil(total/30.0)::integer)));
 select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into rows from
 (select id,staff_name,section,item_name,quantity,details,incident_date,created_at,status,admin_note,version,updated_at from goya_private.equipment_reports
 where incident_date>=m and incident_date<(m+interval '1 month') and (p_admin or staff_id=a.staff_id) order by created_at desc,id desc limit 30 offset (pg-1)*30)q;
 return jsonb_build_object('rows',rows,'total',total,'page',pg);
end $$;

create function public.goya_equipment_review(p_token text,p_id uuid,p_version bigint,p_status text,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r goya_private.equipment_reports;
begin
 perform public.require_session(p_token,true);
 if p_status is null or p_status not in ('Pending','Reviewed','Repaired','Replaced','Closed') or length(coalesce(p_note,''))>1000 then raise exception 'Invalid status or note';end if;
 update goya_private.equipment_reports set status=p_status,admin_note=coalesce(p_note,''),version=version+1,updated_at=now() where id=p_id and version=p_version returning * into r;
 if r.id is null then raise exception 'Record changed or is unavailable. Refresh and review again';end if;
 insert into goya_private.equipment_status_history(report_id,status,note) values(r.id,r.status,r.admin_note);
 return jsonb_build_object('saved',true);
end $$;

-- Statement triggers group item rows, with a uniqueness key as a second deduplication guard.
create function goya_private.capture_admin_submission()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='orders' then
  insert into goya_private.admin_notifications(kind,event_key,source_ref,staff_name)
  select 'orders',order_group_id::text,jsonb_build_object('group_id',order_group_id),min(coalesce(logged_by,'Staff')) from inserted_rows where order_group_id is not null group by order_group_id on conflict do nothing;
 elsif tg_table_name='production_batches' then
  insert into goya_private.admin_notifications(kind,event_key,source_ref,staff_name)
  select 'production',batch_group_id::text,jsonb_build_object('group_id',batch_group_id),min(coalesce(logged_by,'Staff')) from inserted_rows where batch_group_id is not null group by batch_group_id on conflict do nothing;
 elsif tg_table_name='wastage_entries' then
  insert into goya_private.admin_notifications(kind,event_key,source_ref,staff_name)
  select 'wastage',wastage_group_id::text,jsonb_build_object('group_id',wastage_group_id),min(coalesce(logged_by,'Staff')) from inserted_rows where wastage_group_id is not null group by wastage_group_id on conflict do nothing;
 elsif tg_table_name='complaint_feedback' then
  insert into goya_private.admin_notifications(kind,event_key,source_ref,staff_name)
  select 'feedback',id::text,jsonb_build_object('id',id),case when hide_identity then 'Anonymous' else coalesce(staff_name,'Staff') end from inserted_rows on conflict do nothing;
 elsif tg_table_name='inventory_submissions' then
  insert into goya_private.admin_notifications(kind,event_key,source_ref,staff_name)
  select 'inventory',jsonb_build_array(i.session_id,i.staff_id,i.section,i.submitted_at)::text,jsonb_build_object('session_id',i.session_id,'staff_id',i.staff_id,'section',i.section),coalesce(s.name,'Staff') from inserted_rows i left join public.staff s on s.id=i.staff_id on conflict do nothing;
 elsif tg_table_name='inventory_shared_finals' then
  insert into goya_private.admin_notifications(kind,event_key,source_ref,staff_name)
  select 'inventory_shared',id::text,jsonb_build_object('id',id,'sheet_id',sheet_id),coalesce(submitted_name,'Staff') from inserted_rows on conflict do nothing;
 elsif tg_table_name='equipment_reports' then
  insert into goya_private.admin_notifications(kind,event_key,source_ref,staff_name)
  select 'equipment',id::text,jsonb_build_object('id',id),staff_name from inserted_rows on conflict do nothing;
 end if;
 -- Only notification pointers expire. Equipment and all source records are retained.
 delete from goya_private.admin_notifications where created_at<now()-interval '90 days';
 return null;
end $$;
revoke all on function goya_private.capture_admin_submission() from public,anon,authenticated;
create trigger goya_admin_orders after insert on public.orders referencing new table as inserted_rows for each statement execute function goya_private.capture_admin_submission();
create trigger goya_admin_production after insert on public.production_batches referencing new table as inserted_rows for each statement execute function goya_private.capture_admin_submission();
create trigger goya_admin_wastage after insert on public.wastage_entries referencing new table as inserted_rows for each statement execute function goya_private.capture_admin_submission();
create trigger goya_admin_feedback after insert on public.complaint_feedback referencing new table as inserted_rows for each statement execute function goya_private.capture_admin_submission();
create trigger goya_admin_inventory after insert on public.inventory_submissions referencing new table as inserted_rows for each statement execute function goya_private.capture_admin_submission();
create trigger goya_admin_shared_final after insert on goya_private.inventory_shared_finals referencing new table as inserted_rows for each statement execute function goya_private.capture_admin_submission();
create trigger goya_admin_equipment after insert on goya_private.equipment_reports referencing new table as inserted_rows for each statement execute function goya_private.capture_admin_submission();

create function public.goya_admin_notifications(p_token text,p_page integer default 1,p_unread boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare total bigint;unread bigint;pg integer;rows jsonb;last_id bigint;
begin
 perform public.require_session(p_token,true);
 select count(*) filter(where not p_unread or read_at is null),count(*) filter(where read_at is null),coalesce(max(id),0) into total,unread,last_id from goya_private.admin_notifications where created_at>=now()-interval '90 days';
 pg:=greatest(1,least(coalesce(p_page,1),greatest(1,ceil(total/30.0)::integer)));
 select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into rows from (select id,kind,staff_name,created_at,read_at from goya_private.admin_notifications where created_at>=now()-interval '90 days' and (not p_unread or read_at is null) order by id desc limit 30 offset (pg-1)*30)q;
 return jsonb_build_object('rows',rows,'total',total,'unread',unread,'page',pg,'last_id',last_id);
end $$;
create function public.goya_admin_notification_count(p_token text)
returns bigint language plpgsql security definer set search_path='' as $$
begin perform public.require_session(p_token,true);return (select count(*) from goya_private.admin_notifications where read_at is null and created_at>=now()-interval '90 days');end $$;
create function public.goya_admin_notifications_read(p_token text,p_through bigint)
returns void language plpgsql security definer set search_path='' as $$
begin perform public.require_session(p_token,true);update goya_private.admin_notifications set read_at=now() where id<=p_through and read_at is null;end $$;

create function public.goya_admin_notification_detail(p_token text,p_id bigint,p_page integer default 1)
returns jsonb language plpgsql security definer set search_path='' as $$
declare n goya_private.admin_notifications;items jsonb;total bigint;pg integer:=greatest(1,least(coalesce(p_page,1),100000));offst integer;ref jsonb;
begin
 perform public.require_session(p_token,true);select * into n from goya_private.admin_notifications where id=p_id;
 if n.id is null then raise exception 'Notification is unavailable; open the original module to view its records';end if;
 ref:=n.source_ref;offst:=(pg-1)*30;
 if n.kind='orders' then
  select count(*) into total from public.orders where order_group_id=(ref->>'group_id')::uuid;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into items from(select name,sku,quantity,unit,supplier,status,notes,created_at from public.orders where order_group_id=(ref->>'group_id')::uuid order by id limit 30 offset offst)q;
 elsif n.kind='production' then
  select count(*) into total from public.production_batches where batch_group_id=(ref->>'group_id')::uuid;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into items from(select name,sku,storage_quantity,ingredients_quantity,quantity,unit,admin_status,created_at from public.production_batches where batch_group_id=(ref->>'group_id')::uuid order by id limit 30 offset offst)q;
 elsif n.kind='wastage' then
  select count(*) into total from public.wastage_entries where wastage_group_id=(ref->>'group_id')::uuid;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into items from(select name,sku,storage_quantity,ingredients_quantity,quantity,unit,reason,admin_status,created_at from public.wastage_entries where wastage_group_id=(ref->>'group_id')::uuid order by id limit 30 offset offst)q;
 elsif n.kind='feedback' then
  select coalesce(jsonb_agg(jsonb_build_object('type',type,'details',details,'staff_name',case when hide_identity then 'Anonymous' else staff_name end,'created_at',created_at)),'[]') into items from public.complaint_feedback where id=(ref->>'id')::bigint;total:=jsonb_array_length(items);
 elsif n.kind='equipment' then
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into items from(select item_name,quantity,details,section,incident_date,status,admin_note from goya_private.equipment_reports where id=(ref->>'id')::uuid)q;total:=jsonb_array_length(items);
 elsif n.kind='inventory_shared' then
  select coalesce(jsonb_array_length(f.items),0) into total from goya_private.inventory_shared_finals f where id=(ref->>'id')::uuid;
  select coalesce(jsonb_agg(q.value),'[]') into items from(select e.value from goya_private.inventory_shared_finals f cross join lateral jsonb_array_elements(f.items) with ordinality e(value,ord) where f.id=(ref->>'id')::uuid order by e.ord limit 30 offset offst)q;
 else
  select count(*) into total from public.inventory_counts where session_id=(ref->>'session_id')::uuid and staff_id=(ref->>'staff_id')::uuid and section=ref->>'section';
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into items from(select item_name,sku,section,storage_quantity,ingredients_quantity,counted_by,counted_at from public.inventory_counts where session_id=(ref->>'session_id')::uuid and staff_id=(ref->>'staff_id')::uuid and section=ref->>'section' order by id limit 30 offset offst)q;
 end if;
 update goya_private.admin_notifications set read_at=coalesce(read_at,now()) where id=n.id;
 return jsonb_build_object('kind',n.kind,'rows',items,'total',coalesce(total,0),'page',pg,'source_ref',ref);
end $$;

revoke all on function public.goya_equipment_submit(text,uuid,jsonb),public.goya_equipment_list(text,date,integer,boolean),public.goya_equipment_review(text,uuid,bigint,text,text),public.goya_admin_notifications(text,integer,boolean),public.goya_admin_notification_count(text),public.goya_admin_notifications_read(text,bigint),public.goya_admin_notification_detail(text,bigint,integer) from public;
grant execute on function public.goya_equipment_submit(text,uuid,jsonb),public.goya_equipment_list(text,date,integer,boolean),public.goya_equipment_review(text,uuid,bigint,text,text),public.goya_admin_notifications(text,integer,boolean),public.goya_admin_notification_count(text),public.goya_admin_notifications_read(text,bigint),public.goya_admin_notification_detail(text,bigint,integer) to anon,authenticated;
