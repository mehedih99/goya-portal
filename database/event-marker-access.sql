begin;set local lock_timeout='5s';

-- Verify that every pre-existing business row remains unchanged in this transaction.
create temporary table goya_access_preservation(schema_name text,table_name text,row_count bigint,fingerprint text) on commit drop;
do $preserve$ declare r record;n bigint;h text;begin for r in select schemaname,tablename from pg_tables where schemaname in('public','goya_private') and tablename not in('app_sessions','admin_credentials','push_config','push_subscriptions','admin_push_devices','staff_remembered_sessions','admin_remembered_sessions','staff_leave_email_settings') loop
execute format('select count(*),md5(coalesce(string_agg(md5((to_jsonb(x)-''permissions'')::text),'''' order by md5((to_jsonb(x)-''permissions'')::text)),'''')) from %I.%I x',r.schemaname,r.tablename) into n,h;
insert into goya_access_preservation values(r.schemaname,r.tablename,n,h);end loop;end $preserve$;
alter table goya_private.branch_members add column permissions jsonb not null default '{}';
create table goya_private.staff_access_versions(staff_id uuid primary key references public.staff(id),revision integer not null default 0);
create table goya_private.staff_access_audit(id bigint generated always as identity primary key,staff_id uuid not null references public.staff(id),before_data jsonb,after_data jsonb,created_at timestamptz not null default now());
alter table goya_private.staff_access_versions enable row level security;alter table goya_private.staff_access_audit enable row level security;
create function goya_private.branch_access(employee uuid,b uuid default goya_private.current_branch()) returns jsonb language sql stable security definer set search_path='' as $$select jsonb_build_object('order',s.can_order,'production',s.can_production,'wastage',s.can_wastage,'inventory',(s.can_inventory or exists(select 1 from public.inventory_sessions v where v.branch_id=b and v.active and s.id=any(v.assigned_staff_ids))),'equipment',true,'attendance',true,'schedule',true,'sections',to_jsonb(s.sections))||coalesce((select permissions from goya_private.branch_members where staff_id=employee and branch_id=b),'{}') from public.staff s where s.id=employee$$;
revoke all on function goya_private.branch_access(uuid,uuid) from public;grant execute on function goya_private.branch_access(uuid,uuid) to goya_operations;
-- Explicitly preserve all existing branch permissions when the centralized editor is introduced.
update goya_private.branch_members m set permissions=goya_private.branch_access(m.staff_id,m.branch_id);
create view goya_private.branch_staff_effective with(security_invoker=true) as select (jsonb_populate_record(null::public.staff,to_jsonb(s)||jsonb_build_object('can_order',(a.v->>'order')::boolean,'can_production',(a.v->>'production')::boolean,'can_wastage',(a.v->>'wastage')::boolean,'can_inventory',(a.v->>'inventory')::boolean,'sections',a.v->'sections'))).* from public.staff s cross join lateral(select goya_private.branch_access(s.id) v)a where exists(select 1 from goya_private.branch_members m where m.staff_id=s.id and m.branch_id=goya_private.current_branch());
grant select,update on goya_private.branch_staff_effective to goya_operations;
create function goya_private.check_capability(p_token text,p_key text,p_items jsonb default null) returns void language plpgsql security definer set search_path='' as $$declare sess public.app_sessions;access jsonb;item jsonb;begin
select * into sess from public.app_sessions where token=p_token and expires_at>now();if sess.token is null then raise exception 'Session expired or unauthorized';end if;if sess.is_admin then return;end if;perform public.require_session(p_token,false);access:=goya_private.branch_access(sess.staff_id);
if not coalesce((access->>p_key)::boolean,false) then raise exception 'This branch does not grant % access',p_key;end if;
if p_items is not null and p_key in('order','production','wastage') then for item in select value from jsonb_array_elements(p_items) loop
 if p_key='order' then if not exists(select 1 from public.master_items x where lower(btrim(x.sku))=lower(btrim(item->>'sku')) and x.items_type in(select jsonb_array_elements_text(access->'sections'))) then raise exception 'An item is outside your allowed sections or is no longer available';end if;
 else if not exists(select 1 from public.internal_items x where lower(btrim(x.sku))=lower(btrim(item->>'sku')) and x.items_type in(select jsonb_array_elements_text(access->'sections'))) then raise exception 'An item is outside your allowed sections or is no longer available';end if;end if;end loop;end if;end$$;
revoke all on function goya_private.check_capability(text,text,jsonb) from public;grant execute on function goya_private.check_capability(text,text,jsonb) to goya_operations;
create function public.goya_staff_access_get(p_token text,p_staff uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$begin perform public.require_session(p_token,true);return jsonb_build_object('revision',coalesce((select revision from goya_private.staff_access_versions where staff_id=p_staff),0),'rows',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'kind',b.kind,'archived',b.archived_at is not null,'enabled',m.staff_id is not null,'permissions',coalesce(goya_private.branch_access(p_staff,b.id),jsonb_build_object('order',true,'production',true,'wastage',true,'inventory',false,'equipment',true,'attendance',true,'schedule',true,'sections','[]'::jsonb))) order by b.created_at,b.id) from goya_private.branches b left join goya_private.branch_members m on m.branch_id=b.id and m.staff_id=p_staff),'[]'));end$$;
create function public.goya_staff_access_save(p_token text,p_staff uuid,p_rows jsonb,p_expected integer default 0) returns integer language plpgsql security definer set search_path='' as $$declare v integer;r jsonb;perms jsonb;k text;old_data jsonb;begin perform public.require_session(p_token,true);perform 1 from public.staff where id=p_staff for update;if not found then raise exception 'Staff not found';end if;
select coalesce(revision,0) into v from goya_private.staff_access_versions where staff_id=p_staff;if coalesce(v,0)<>p_expected then raise exception 'Access changed on another device. Reopen before saving';end if;
if jsonb_typeof(p_rows) is distinct from 'array' or jsonb_array_length(p_rows)<>(select count(*) from goya_private.branches) or (select count(distinct value->>'id') from jsonb_array_elements(p_rows))<>jsonb_array_length(p_rows) then raise exception 'Reload the complete branch list before saving';end if;
perform 1 from goya_private.branches order by id for update;old_data:=public.goya_staff_access_get(p_token,p_staff);
for r in select value from jsonb_array_elements(p_rows) loop
if not exists(select 1 from goya_private.branches where id=(r->>'id')::uuid) or jsonb_typeof(r->'enabled') is distinct from 'boolean' or jsonb_typeof(r->'permissions') is distinct from 'object' then raise exception 'Invalid branch access';end if;perms:=r->'permissions';
for k in select unnest(array['order','production','wastage','inventory','equipment','attendance','schedule']) loop if jsonb_typeof(perms->k) is distinct from 'boolean' then raise exception 'Choose valid access switches';end if;end loop;
if jsonb_typeof(perms->'sections') is distinct from 'array' or exists(select 1 from jsonb_array_elements_text(perms->'sections') s where s not in('Bar','Kitchen','Pastry','Packaging')) then raise exception 'Choose valid sections';end if;
if exists(select 1 from public.attendance_live_sessions where staff_id=p_staff and branch_id=(r->>'id')::uuid and check_out_at is null and not coalesce(is_deleted,false)) and (not (r->>'enabled')::boolean or not (perms->>'attendance')::boolean) then raise exception 'Check staff out of the active duty before removing attendance or branch access';end if;
if ((r->>'enabled')::boolean is distinct from exists(select 1 from goya_private.branch_members where staff_id=p_staff and branch_id=(r->>'id')::uuid)) or perms is distinct from (select permissions from goya_private.branch_members where staff_id=p_staff and branch_id=(r->>'id')::uuid) then update goya_private.branches set revision=revision+1 where id=(r->>'id')::uuid;end if;if (r->>'enabled')::boolean then insert into goya_private.branch_members(branch_id,staff_id,permissions) values((r->>'id')::uuid,p_staff,perms) on conflict(branch_id,staff_id) do update set permissions=excluded.permissions;
else delete from goya_private.branch_members where branch_id=(r->>'id')::uuid and staff_id=p_staff;end if;end loop;
insert into goya_private.staff_access_versions values(p_staff,1) on conflict(staff_id) do update set revision=staff_access_versions.revision+1 returning revision into v;
insert into goya_private.staff_access_audit(staff_id,before_data,after_data) values(p_staff,old_data,public.goya_staff_access_get(p_token,p_staff));return v;end$$;
revoke all on function public.goya_staff_access_get(text,uuid),public.goya_staff_access_save(text,uuid,jsonb,integer) from public;grant execute on function public.goya_staff_access_get(text,uuid),public.goya_staff_access_save(text,uuid,jsonb,integer) to anon,authenticated,goya_operations;
CREATE OR REPLACE FUNCTION goya_private.profile_save_base(p_token text, p_row jsonb, p_profile jsonb, p_expected timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid:=nullif(p_row->>'id','')::uuid; previous goya_private.staff_hr_profiles; saved jsonb;
begin
 perform goya_private.require_employee_session(p_token,true);
 if nullif(btrim(p_row->>'name'),'') is null then raise exception 'Full name is required'; end if;
 if employee is null and (nullif(p_profile->>'joining_date','') is null or nullif(btrim(p_profile->>'mobile'),'') is null
 or nullif(btrim(p_profile->>'position'),'') is null or jsonb_array_length(coalesce(p_row->'sections','[]'))=0) then
 raise exception 'Full name, joining date, mobile, position, section and PIN are required'; end if;
 if nullif(p_profile->>'date_of_birth','')::date>(now() at time zone 'Asia/Dubai')::date then raise exception 'Check date of birth'; end if;
 if nullif(p_profile->>'probation_end','')::date<nullif(p_profile->>'joining_date','')::date then raise exception 'Probation must end on or after joining'; end if;
 if employee is not null then
  perform 1 from public.staff where id=employee for update;
  if not found then raise exception 'Staff member not found'; end if;
  select * into previous from goya_private.staff_hr_profiles where staff_id=employee;
  if previous.updated_at is distinct from p_expected then raise exception 'Profile changed. Reopen it before saving.'; end if;
  if previous.last_day is not null and coalesce((p_row->>'active')::boolean,false) then raise exception 'Use Rejoin staff to reactivate'; end if;
 end if;
 if nullif(p_profile->>'last_day','') is distinct from previous.last_day::text then raise exception 'Use the resignation action to change last working day'; end if;
 saved:=public.admin_save_staff(p_token,p_row); employee:=(saved->>'id')::uuid;
 perform public.goya_hr_save_profile(p_token,employee,p_profile||jsonb_build_object('employee_code',coalesce(previous.employee_code,''),'branch','GOYA'));
 update goya_private.staff_hr_profiles set roster_group=coalesce(p_profile->>'roster_group',roster_group),mobile=left(coalesce(p_profile->>'mobile',mobile),60),email=left(coalesce(p_profile->>'email',email),254),address=left(coalesce(p_profile->>'address',address),1000),
 nationality=left(coalesce(p_profile->>'nationality',nationality),100),date_of_birth=nullif(p_profile->>'date_of_birth','')::date,
 employment_type=left(coalesce(p_profile->>'employment_type',employment_type),80),probation_end=nullif(p_profile->>'probation_end','')::date,
 emergency_name=left(coalesce(p_profile->>'emergency_name',emergency_name),120),emergency_relationship=left(coalesce(p_profile->>'emergency_relationship',emergency_relationship),80),
 emergency_phone=left(coalesce(p_profile->>'emergency_phone',emergency_phone),60) where staff_id=employee;
 return jsonb_build_object('id',employee,'profile',(select to_jsonb(p) from goya_private.staff_hr_profiles p where p.staff_id=employee));
end $function$
;
alter function goya_private.profile_save_base(p_token text, p_row jsonb, p_profile jsonb, p_expected timestamp with time zone) owner to goya_operations;revoke all on function goya_private.profile_save_base(p_token text, p_row jsonb, p_profile jsonb, p_expected timestamp with time zone) from public;grant execute on function goya_private.profile_save_base(p_token text, p_row jsonb, p_profile jsonb, p_expected timestamp with time zone) to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_people_save_staff(p_token text, p_row jsonb, p_profile jsonb, p_expected timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ declare saved jsonb;begin saved:=goya_private.profile_save_base(p_token,p_row,p_profile,p_expected);if p_row ? 'branch_access' then perform public.goya_staff_access_save(p_token,(saved->>'id')::uuid,p_row->'branch_access',coalesce((p_row->>'access_revision')::int,0));end if;return saved;end $function$
;
CREATE OR REPLACE FUNCTION public.submit_order(p_token text, p_notes text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions;s public.staff;gid uuid;it jsonb;n int:=0;order_no text;
begin perform goya_private.check_capability(p_token,'order',p_items);
  sess:=public.require_session(p_token,false);select * into s from goya_private.branch_staff_effective where id=sess.staff_id;
  if not s.can_order then raise exception 'Order access disabled'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'No items in order'; end if;
  gid:=gen_random_uuid();order_no:=case when goya_private.current_branch()='00000000-0000-0000-0000-000000000001' then 'GOYA-' else 'EVENT-' end||to_char(now(),'YYYYMMDD-HH24MISS')||'-'||substr(replace(gid::text,'-',''),1,5);
  insert into public.order_groups(id,order_no,submitted_by,staff_name,notes) values(gid,order_no,s.id,s.name,null);
  for it in select * from jsonb_array_elements(p_items) loop
    insert into public.orders(order_group_id,name,sku,quantity,unit,supplier,logged_by,notes) values(gid,trim(it->>'name'),trim(it->>'sku'),(it->>'quantity')::numeric,trim(it->>'unit'),nullif(trim(it->>'supplier'),''),s.name,nullif(trim(it->>'notes'),''));n:=n+1;
  end loop;
  return jsonb_build_object('order_group_id',gid,'order_no',order_no,'count',n);
end $function$
;
CREATE OR REPLACE FUNCTION public.submit_production(p_token text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; s public.staff; gid uuid; it jsonb; n int:=0;
begin perform goya_private.check_capability(p_token,'production',p_items);
  sess := public.require_session(p_token,false);
  select * into s from goya_private.branch_staff_effective where id=sess.staff_id;
  if not s.can_production then raise exception 'Production access disabled'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'No production items'; end if;
  gid:=gen_random_uuid();
  for it in select * from jsonb_array_elements(p_items) loop
    insert into public.production_batches(batch_group_id,name,sku,quantity,unit,storage_quantity,ingredients_quantity,logged_by)
    values(gid,trim(it->>'name'),trim(it->>'sku'),(it->>'quantity')::numeric,trim(it->>'unit'),
      nullif(it->>'storage_quantity','')::numeric,nullif(it->>'ingredients_quantity','')::numeric,s.name);
    n:=n+1;
  end loop;
  return jsonb_build_object('group_id',gid,'count',n);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.submit_wastage(p_token text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; s public.staff; gid uuid; it jsonb; n int:=0; sq numeric; iq numeric;
begin perform goya_private.check_capability(p_token,'wastage',p_items);
  sess := public.require_session(p_token,false);
  select * into s from goya_private.branch_staff_effective where id=sess.staff_id;
  if not s.can_wastage then raise exception 'Wastage access disabled'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'No wastage items'; end if;
  gid:=gen_random_uuid();
  for it in select * from jsonb_array_elements(p_items) loop
    sq := nullif(it->>'storage_quantity','')::numeric;
    iq := nullif(it->>'ingredients_quantity','')::numeric;
    insert into public.wastage_entries(wastage_group_id,name,sku,quantity,unit,storage_quantity,ingredients_quantity,reason,logged_by)
    values(gid,trim(it->>'name'),trim(it->>'sku'),(it->>'quantity')::numeric,trim(it->>'unit'),sq,iq,trim(it->>'reason'),s.name);
    n:=n+1;
  end loop;
  return jsonb_build_object('group_id',gid,'count',n);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.goya_orders_page(p_token text, p_admin boolean DEFAULT false, p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f jsonb:=coalesce(p_filters,'{}'); lo timestamptz; hi timestamptz; od date:=nullif(f->>'order_date','')::date; rd date:=nullif(f->>'received_date','')::date;
 st text:=nullif(f->>'status',''); sp text:=nullif(f->>'supplier',''); q text:=lower(nullif(trim(f->>'search'),'')); all_dates boolean:=coalesce((f->>'all_dates')::boolean,false);
 total bigint; counts jsonb; rowsv jsonb; pagev integer; monthv date;
begin perform goya_private.check_capability(p_token,'order',null);
 perform public.require_session(p_token,p_admin);
 if p_admin then lo:=nullif(f->>'from','')::timestamptz;hi:=nullif(f->>'to','')::timestamptz;
 else
  if all_dates and coalesce(st,'') not in ('Pending','Ordered') then raise exception 'All-date staff history is limited to open orders';end if;
  if not all_dates then monthv:=date_trunc('month',coalesce(nullif(f->>'month','')::date,timezone('Asia/Dubai',now())::date))::date;lo:=monthv::timestamp at time zone 'Asia/Dubai';hi:=(monthv+interval '1 month')::timestamp at time zone 'Asia/Dubai';end if;
 end if;
 if lo is not null and hi is not null and hi<=lo then raise exception 'End date must be after start date';end if;
 with base as (
 select o.status from public.orders o join public.order_groups g on g.id=o.order_group_id
 where (lo is null or o.created_at>=lo) and (hi is null or o.created_at<hi)
 and (not all_dates or p_admin or o.status in ('Pending','Ordered'))
 and (sp is null or coalesce(o.supplier,'')=sp)
 and (q is null or position(q in lower(coalesce(o.name,'')))>0 or position(q in lower(coalesce(o.sku,'')))>0)
 and (od is null or (o.created_at>=od::timestamp at time zone 'Asia/Dubai' and o.created_at<(od+1)::timestamp at time zone 'Asia/Dubai'))
 and (rd is null or o.received_date=rd)
 ) select count(*) filter(where st is null or status=st),jsonb_build_object('Pending',count(*) filter(where status='Pending'),'Ordered',count(*) filter(where status='Ordered'),'Received',count(*) filter(where status='Received'),'Not Received',count(*) filter(where status='Not Received')) into total,counts from base;
 pagev:=least(greatest(coalesce(p_page,1),1),greatest(1,ceil(total/30.0)::integer));
 select coalesce(jsonb_agg(x.rowv order by x.created_at desc,x.id desc),'[]') into rowsv from (
 select o.id,o.created_at,case when p_admin then to_jsonb(o)||jsonb_build_object('order_no',g.order_no,'branch_snapshot',g.branch_snapshot,'submitted_at',g.submitted_at,'group_notes',g.notes)
 else jsonb_build_object('id',o.id,'order_no',g.order_no,'branch_snapshot',g.branch_snapshot,'name',o.name,'sku',o.sku,'quantity',o.quantity,'unit',o.unit,'supplier',o.supplier,'status',o.status,'received_date',o.received_date,'logged_by',o.logged_by,'notes',o.notes,'created_at',o.created_at) end rowv
 from public.orders o join public.order_groups g on g.id=o.order_group_id
 where (lo is null or o.created_at>=lo) and (hi is null or o.created_at<hi)
 and (st is null or o.status=st) and (not all_dates or p_admin or o.status in ('Pending','Ordered'))
 and (sp is null or coalesce(o.supplier,'')=sp)
 and (q is null or position(q in lower(coalesce(o.name,'')))>0 or position(q in lower(coalesce(o.sku,'')))>0)
 and (od is null or (o.created_at>=od::timestamp at time zone 'Asia/Dubai' and o.created_at<(od+1)::timestamp at time zone 'Asia/Dubai'))
 and (rd is null or o.received_date=rd)
 order by o.created_at desc,o.id desc limit 30 offset ((pagev-1)::bigint*30)
 )x;
 return jsonb_build_object('rows',rowsv,'total',total,'counts',counts,'page',pagev,'page_size',30);
end $function$
;
CREATE OR REPLACE FUNCTION public.goya_staff_open_orders(p_token text, p_status text DEFAULT 'Pending'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin perform goya_private.check_capability(p_token,'order',null);
 perform public.require_session(p_token,false);
 if p_status not in ('Pending','Ordered') then raise exception 'Invalid open order status'; end if;
 return jsonb_build_object('orders',(select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb) from (select o.id,g.order_no,o.name,o.sku,o.quantity,o.unit,o.supplier,o.status,o.received_date,o.logged_by,o.notes,o.created_at from public.orders o join public.order_groups g on g.id=o.order_group_id where o.status=p_status)q));
end $function$
;
CREATE OR REPLACE FUNCTION public.goya_equipment_submit(p_token text, p_request_id uuid, p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.app_sessions;s public.staff;r goya_private.equipment_reports;d date;v_section text;
begin perform goya_private.check_capability(p_token,'equipment',null);
 a:=public.require_session(p_token,false);select * into s from goya_private.branch_staff_effective where id=a.staff_id and active;
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
end $function$
;
CREATE OR REPLACE FUNCTION public.goya_equipment_list(p_token text, p_month date, p_page integer DEFAULT 1, p_admin boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.app_sessions;total bigint;pg integer;rows jsonb;m date;
begin perform goya_private.check_capability(p_token,'equipment',null);
 a:=public.require_session(p_token,p_admin);
 if not p_admin and not exists(select 1 from goya_private.branch_staff_effective where id=a.staff_id and active) then raise exception 'Staff is inactive or unauthorized';end if;
 if p_month is null then raise exception 'Select a month';end if;m:=date_trunc('month',p_month)::date;
 select count(*) into total from goya_private.equipment_reports where incident_date>=m and incident_date<(m+interval '1 month') and (p_admin or staff_id=a.staff_id);
 pg:=greatest(1,least(coalesce(p_page,1),greatest(1,ceil(total/30.0)::integer)));
 select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into rows from
 (select id,staff_name,section,item_name,quantity,details,incident_date,created_at,status,admin_note,version,updated_at from goya_private.equipment_reports
 where incident_date>=m and incident_date<(m+interval '1 month') and (p_admin or staff_id=a.staff_id) order by created_at desc,id desc limit 30 offset (pg-1)*30)q;
 return jsonb_build_object('rows',rows,'total',total,'page',pg);
end $function$
;
CREATE OR REPLACE FUNCTION public.inventory_work(p_token text, p_session_id uuid, p_section text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions;s public.staff;subtime timestamptz;draft_items jsonb;allowed boolean;
begin perform goya_private.check_capability(p_token,'inventory',null);
  if exists(select 1 from public.inventory_sessions where id=p_session_id and shared_count) then return public.goya_inventory_shared_work(p_token,p_session_id,p_section);end if;
  sess:=public.require_session(p_token,false);select * into s from goya_private.branch_staff_effective where id=sess.staff_id;
  select exists(select 1 from public.inventory_sessions v where v.id=p_session_id and v.active and p_section=any(v.sections) and p_section=any(s.sections) and (s.id=any(v.assigned_staff_ids) or (coalesce(array_length(v.assigned_staff_ids,1),0)=0 and s.can_inventory))) into allowed;
  if not allowed then raise exception 'Inventory section is not assigned to this staff'; end if;
  select submitted_at into subtime from public.inventory_submissions where session_id=p_session_id and staff_id=s.id and section=p_section;
  select items into draft_items from public.inventory_drafts where session_id=p_session_id and staff_id=s.id and section=p_section;
  return jsonb_build_object('done',subtime is not null,'submitted_at',subtime,'draft',coalesce(draft_items,'[]'::jsonb),'items',(
    select coalesce(jsonb_agg(to_jsonb(z) order by lower(z.name),z.source),'[]'::jsonb) from (
      select m.name,m.sku,m.storage_unit,m.ingredient_unit,'Master'::text source from public.master_items m where m.active=true and lower(m.items_type)=lower(p_section)
      union all
      select i.name,i.sku,i.storage_unit,i.ingredient_unit,'Internal'::text source from public.internal_items i where i.active=true and lower(i.items_type)=lower(p_section)
    )z
  ));
end $function$
;
CREATE OR REPLACE FUNCTION public.inventory_save_draft(p_token text, p_session_id uuid, p_section text, p_items jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions;s public.staff;
begin perform goya_private.check_capability(p_token,'inventory',null);
  if exists(select 1 from public.inventory_sessions where id=p_session_id and shared_count) then raise exception 'Shared count: refresh your Staff Portal to save or submit safely';end if;
  sess:=public.require_session(p_token,false);select * into s from goya_private.branch_staff_effective where id=sess.staff_id;
  perform public.inventory_work(p_token,p_session_id,p_section);
  if exists(select 1 from public.inventory_submissions where session_id=p_session_id and staff_id=s.id and section=p_section) then raise exception 'This section is already submitted'; end if;
  insert into public.inventory_drafts(session_id,staff_id,section,items,updated_at) values(p_session_id,s.id,p_section,coalesce(p_items,'[]'::jsonb),now()) on conflict(session_id,staff_id,section) do update set items=excluded.items,updated_at=now();
  return true;
end $function$
;
CREATE OR REPLACE FUNCTION public.inventory_submit_final(p_token text, p_session_id uuid, p_section text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions;s public.staff;it jsonb;expected int;provided int;n int:=0;
begin perform goya_private.check_capability(p_token,'inventory',null);
  if exists(select 1 from public.inventory_sessions where id=p_session_id and shared_count) then raise exception 'Shared count: refresh your Staff Portal to save or submit safely';end if;
  sess:=public.require_session(p_token,false);select * into s from goya_private.branch_staff_effective where id=sess.staff_id;
  perform public.inventory_work(p_token,p_session_id,p_section);
  if exists(select 1 from public.inventory_submissions where session_id=p_session_id and staff_id=s.id and section=p_section) then raise exception 'This section is already submitted'; end if;
  select count(*) into expected from (select sku from public.master_items where active=true and lower(items_type)=lower(p_section) union all select sku from public.internal_items where active=true and lower(items_type)=lower(p_section))q;
  if jsonb_typeof(p_items)<>'array' then raise exception 'Invalid inventory payload'; end if; provided:=jsonb_array_length(p_items);
  if provided<>expected then raise exception 'All inventory items must be completed before submission'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    if coalesce(it->>'storage_quantity','')='' or coalesce(it->>'ingredients_quantity','')='' then raise exception 'Every item requires Storage Qty and Ingredients Qty'; end if;
    insert into public.inventory_counts(session_id,staff_id,item_name,sku,section,storage_quantity,ingredients_quantity,counted_by,counted_at) values(p_session_id,s.id,trim(it->>'item_name'),trim(it->>'sku'),p_section,(it->>'storage_quantity')::numeric,(it->>'ingredients_quantity')::numeric,s.name,now()) on conflict(session_id,staff_id,sku,section) do update set item_name=excluded.item_name,storage_quantity=excluded.storage_quantity,ingredients_quantity=excluded.ingredients_quantity,counted_by=excluded.counted_by,counted_at=excluded.counted_at;
    n:=n+1;
  end loop;
  insert into public.inventory_submissions(session_id,staff_id,section,submitted_at) values(p_session_id,s.id,p_section,now());
  delete from public.inventory_drafts where session_id=p_session_id and staff_id=s.id and section=p_section;
  return jsonb_build_object('count',n,'done',true);
end $function$
;
CREATE OR REPLACE FUNCTION public.save_inventory_count(p_token text, p_session_id uuid, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; s public.staff; it jsonb; n int:=0; sec text;
begin perform goya_private.check_capability(p_token,'inventory',null);
  if exists(select 1 from public.inventory_sessions where id=p_session_id and shared_count) then raise exception 'Shared count: refresh your Staff Portal to save safely';end if;
  sess:=public.require_session(p_token,false); select * into s from goya_private.branch_staff_effective where id=sess.staff_id;
  if not exists(select 1 from public.inventory_sessions v where v.id=p_session_id and v.active and (
    s.id=any(v.assigned_staff_ids) or (coalesce(array_length(v.assigned_staff_ids,1),0)=0 and s.can_inventory and s.sections && v.sections)
  )) then raise exception 'Inventory session not assigned to this staff'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    sec:=trim(it->>'section');
    insert into public.inventory_counts(session_id,item_name,sku,section,storage_quantity,ingredients_quantity,counted_by,counted_at)
    values(p_session_id,trim(it->>'item_name'),trim(it->>'sku'),sec,nullif(it->>'storage_quantity','')::numeric,
      nullif(it->>'ingredients_quantity','')::numeric,s.name,now())
    on conflict(session_id,sku,section) do update set storage_quantity=excluded.storage_quantity,
      ingredients_quantity=excluded.ingredients_quantity,counted_by=excluded.counted_by,counted_at=excluded.counted_at;
    n:=n+1;
  end loop;
  return jsonb_build_object('count',n);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.goya_inventory_shared_work(p_token text, p_session_id uuid, p_section text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare h goya_private.inventory_shared_sheets;begin perform goya_private.check_capability(p_token,'inventory',null); h:=goya_private.inventory_shared_open(p_token,p_session_id,p_section);return goya_private.inventory_shared_payload(h.id)||jsonb_build_object('viewer_id',(public.require_session(p_token,false)).staff_id);end $function$
;
CREATE OR REPLACE FUNCTION public.goya_inventory_shared_save(p_token text, p_session_id uuid, p_section text, p_generation bigint, p_changes jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare h goya_private.inventory_shared_sheets;a public.app_sessions;s public.staff;x jsonb;l goya_private.inventory_shared_lines;sv numeric;iv numeric;conflicts jsonb:='[]';
begin perform goya_private.check_capability(p_token,'inventory',null);
 h:=goya_private.inventory_shared_open(p_token,p_session_id,p_section);a:=public.require_session(p_token,false);select * into s from goya_private.branch_staff_effective where id=a.staff_id;
 if h.submitted_at is not null then return jsonb_build_object('ok',false,'reason','submitted','sheet',goya_private.inventory_shared_payload(h.id));end if;
 if p_generation is distinct from h.generation then return jsonb_build_object('ok',false,'reason','reopened','sheet',goya_private.inventory_shared_payload(h.id));end if;
 if jsonb_typeof(p_changes) is distinct from 'array' or jsonb_array_length(p_changes)>2000 then raise exception 'Invalid changes';end if;
 if exists(select j.value->>'sku' from jsonb_array_elements(p_changes)j group by j.value->>'sku' having count(*)>1) then raise exception 'Duplicate item changes';end if;
 for x in select * from jsonb_array_elements(p_changes) loop
  select * into l from goya_private.inventory_shared_lines where sheet_id=h.id and sku=x->>'sku';
  if not found then raise exception 'Unknown inventory item';end if;
  if not(x ? 'storage_quantity' and x ? 'ingredients_quantity' and x ? 'version') then raise exception 'Incomplete change payload';end if;
  sv:=nullif(x->>'storage_quantity','')::numeric;iv:=nullif(x->>'ingredients_quantity','')::numeric;
  if (sv is not null and (sv<0 or sv>1000000000000 or sv<>round(sv,3) or sv::text in ('NaN','Infinity','-Infinity'))) or (iv is not null and (iv<0 or iv>1000000000000 or iv<>round(iv,3) or iv::text in ('NaN','Infinity','-Infinity'))) then raise exception 'Use nonnegative quantities with up to three decimal places';end if;
  if (x->>'version')::bigint is distinct from l.version and (sv is distinct from l.storage_quantity or iv is distinct from l.ingredients_quantity) then conflicts:=conflicts||jsonb_build_array(x->>'sku');end if;
 end loop;
 if jsonb_array_length(conflicts)>0 then return jsonb_build_object('ok',false,'reason','conflict','conflicts',conflicts,'sheet',goya_private.inventory_shared_payload(h.id));end if;
 for x in select * from jsonb_array_elements(p_changes) loop
  select * into l from goya_private.inventory_shared_lines where sheet_id=h.id and sku=x->>'sku';sv:=nullif(x->>'storage_quantity','')::numeric;iv:=nullif(x->>'ingredients_quantity','')::numeric;
  if sv is distinct from l.storage_quantity or iv is distinct from l.ingredients_quantity then
   insert into goya_private.inventory_shared_audit(sheet_id,sku,event,actor_id,actor_name,old_values,new_values) values(h.id,l.sku,'edit',s.id,s.name,jsonb_build_object('storage',l.storage_quantity,'ingredients',l.ingredients_quantity),jsonb_build_object('storage',sv,'ingredients',iv));
   update goya_private.inventory_shared_lines set storage_quantity=sv,ingredients_quantity=iv,version=version+1,updated_by=s.id,updated_name=s.name,updated_at=now() where sheet_id=h.id and sku=l.sku;
   update goya_private.inventory_shared_sheets set version=version+1 where id=h.id;
  end if;
 end loop;
 return jsonb_build_object('ok',true,'sheet',goya_private.inventory_shared_payload(h.id));
end $function$
;
CREATE OR REPLACE FUNCTION public.goya_inventory_shared_submit(p_token text, p_session_id uuid, p_section text, p_generation bigint, p_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare h goya_private.inventory_shared_sheets;a public.app_sessions;s public.staff;
begin perform goya_private.check_capability(p_token,'inventory',null);
 h:=goya_private.inventory_shared_open(p_token,p_session_id,p_section);a:=public.require_session(p_token,false);select * into s from goya_private.branch_staff_effective where id=a.staff_id;
 if h.submitted_at is not null then return jsonb_build_object('ok',true,'already_submitted',true,'sheet',goya_private.inventory_shared_payload(h.id));end if;
 if p_generation is distinct from h.generation or p_version is distinct from h.version then return jsonb_build_object('ok',false,'reason','changed','sheet',goya_private.inventory_shared_payload(h.id));end if;
 if not exists(select 1 from goya_private.inventory_shared_lines where sheet_id=h.id) or exists(select 1 from goya_private.inventory_shared_lines where sheet_id=h.id and (storage_quantity is null or ingredients_quantity is null)) then raise exception 'Complete both quantities for every item before submission';end if;
 insert into goya_private.inventory_shared_finals(sheet_id,generation,version,submitted_by,submitted_name,items) values(h.id,h.generation,h.version,s.id,s.name,goya_private.inventory_shared_payload(h.id)->'items');
 insert into public.inventory_counts(session_id,staff_id,item_name,sku,section,storage_quantity,ingredients_quantity,counted_by,counted_at,shared_sheet_id,sheet_name,counting_date)
 select p_session_id,s.id,item_name,sku,p_section,storage_quantity,ingredients_quantity,coalesce(updated_name,s.name),now(),h.id,h.sheet_name,h.counting_date from goya_private.inventory_shared_lines where sheet_id=h.id
 on conflict(shared_sheet_id,sku) where shared_sheet_id is not null do update set staff_id=excluded.staff_id,storage_quantity=excluded.storage_quantity,ingredients_quantity=excluded.ingredients_quantity,counted_by=excluded.counted_by,counted_at=excluded.counted_at;
 update goya_private.inventory_shared_sheets set submitted_at=now(),submitted_by=s.id,submitted_name=s.name,version=version+1 where id=h.id;
 insert into goya_private.inventory_shared_audit(sheet_id,event,actor_id,actor_name) values(h.id,'submit',s.id,s.name);
 return jsonb_build_object('ok',true,'sheet',goya_private.inventory_shared_payload(h.id));
end $function$
;
CREATE OR REPLACE FUNCTION public.goya_inventory_shared_history(p_token text, p_session_id uuid, p_section text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.app_sessions;h goya_private.inventory_shared_sheets;begin perform goya_private.check_capability(p_token,'inventory',null);
 begin a:=public.require_session(p_token,true);select * into h from goya_private.inventory_shared_sheets where session_id=p_session_id and section=p_section;
 exception when others then h:=goya_private.inventory_shared_open(p_token,p_session_id,p_section);end;
 return jsonb_build_object('events',coalesce((select jsonb_agg(to_jsonb(q)) from (select sku,event,actor_name,old_values,new_values,created_at from goya_private.inventory_shared_audit where sheet_id=h.id order by id desc limit 100)q),'[]'::jsonb),
 'submissions',coalesce((select jsonb_agg(to_jsonb(q)) from (select generation,submitted_name,submitted_at,items from goya_private.inventory_shared_finals where sheet_id=h.id order by generation desc)q),'[]'::jsonb));
end $function$
;
CREATE OR REPLACE FUNCTION public.goya_roster_my_week(p_token text, p_week date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_staff_id uuid;
begin perform goya_private.check_capability(p_token,'schedule',null);
  v_staff_id := (public.require_session(p_token,false)).staff_id;
  if not exists(select 1 from goya_private.branch_staff s where s.id=v_staff_id and s.active) then
    raise exception using message='Not authorized',errcode='28000';
  end if;
  return jsonb_build_object('week',(select jsonb_build_object(
      'days',(select jsonb_agg(case when goya_private.employed_on(v_staff_id,p_week+ord::int-1) then value else 'null'::jsonb end order by ord) from jsonb_array_elements(p.schedule->'staff'->v_staff_id::text) with ordinality days(value,ord)),'notes',p.schedule->>'notes','published_at',p.published_at)
    from goya_private.roster_weeks w join goya_private.roster_publications p
      on p.week_start=w.week_start and p.revision=w.published_revision
    where w.week_start=p_week and (p.schedule->'staff')?v_staff_id::text),
    'latest_publication',(select jsonb_build_object('week',w.week_start,'published_at',p.published_at,'revision',p.revision)
      from goya_private.roster_weeks w join goya_private.roster_publications p
      on p.week_start=w.week_start and p.revision=w.published_revision
      where w.week_start+6 >= (now() at time zone 'Asia/Dubai')::date and (p.schedule->'staff') ? v_staff_id::text
      order by p.published_at desc limit 1),
    'weeks',coalesce((select jsonb_agg(w.week_start order by w.week_start desc)
    from goya_private.roster_weeks w join goya_private.roster_publications p
      on p.week_start=w.week_start and p.revision=w.published_revision
    where (p.schedule->'staff')?v_staff_id::text),'[]'::jsonb));
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_live_attendance_status(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  s public.staff;
  od date := public.attendance_live_operational_date(now());
  active_od date := od;
  rules jsonb := public.attendance_live_rules();
  open_row public.attendance_live_sessions;
  cutoff_at timestamptz;
  d public.attendance_live_days;
begin perform goya_private.check_capability(p_token,'attendance',null);
  sess := public.require_session(p_token,false);
  select * into s from goya_private.branch_staff_effective where id=sess.staff_id;

  -- Find the real active session regardless of midnight rollover.
  select * into open_row
    from public.attendance_live_sessions x
   where x.staff_id=s.id
     and x.check_out_at is null
     and coalesce(x.is_deleted,false)=false
   order by x.check_in_at desc
   limit 1;

  if open_row.id is not null then
    cutoff_at := public.attendance_live_cutoff_at(open_row.operational_date);

    if now() <= cutoff_at then
      active_od := open_row.operational_date;
    else
      -- Only close it when the cutoff is after the actual check-in.
      if cutoff_at >= open_row.check_in_at then
        update public.attendance_live_sessions
           set check_out_at=cutoff_at,
               check_out_location_name='Auto Day Close',
               check_out_verified=false,
               updated_at=now()
         where id=open_row.id
           and check_out_at is null;

        begin
          perform public.attendance_live_recalculate_day_internal(s.id,open_row.operational_date);
        exception when undefined_function then
          null;
        end;
      end if;
      open_row := null;
    end if;
  end if;

  select * into d
    from public.attendance_live_days x
   where x.staff_id=s.id
     and x.operational_date=active_od
     and coalesce(x.is_deleted,false)=false;

  return jsonb_build_object(
    'server_now',now(),
    'operational_date',active_od,
    'staff',jsonb_build_object('id',s.id,'name',s.name,'sections',s.sections,'active',s.active),
    'rules',rules,
    'day',to_jsonb(d),
    'sessions',coalesce((
      select jsonb_agg(to_jsonb(x) order by x.session_no)
        from public.attendance_live_sessions x
       where x.staff_id=s.id
         and x.operational_date=active_od
         and coalesce(x.is_deleted,false)=false
    ),'[]'::jsonb)
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.staff_live_attendance_check_in(p_token text, p_lat double precision, p_lon double precision, p_public_ip text, p_rejoin boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  s public.staff;
  od date := public.attendance_live_operational_date(now());
  verify jsonb;
  sh jsonb;
  open_row public.attendance_live_sessions;
  prior_count int := 0;
  next_no int := 1;
  new_row public.attendance_live_sessions;
  d public.attendance_live_days;
  cutoff_at timestamptz;
begin perform goya_private.check_capability(p_token,'attendance',null);
  sess := public.require_session(p_token,false);
  select * into s from goya_private.branch_staff_effective where id=sess.staff_id and active=true;
  if s.id is null then raise exception 'Staff account is inactive or unavailable'; end if;
  if not goya_private.employed_on(s.id,od) then raise exception 'Attendance is available only within your employment dates'; end if;
  perform pg_advisory_xact_lock(hashtext(s.id::text));

  select * into open_row
    from public.attendance_live_sessions
   where staff_id=s.id
     and check_out_at is null
     and coalesce(is_deleted,false)=false
   order by check_in_at desc
   limit 1;

  if open_row.id is not null then
    cutoff_at := public.attendance_live_cutoff_at(open_row.operational_date);
    if now() <= cutoff_at then
      return jsonb_build_object(
        'ok',true,'duplicate',true,'message','Already checked in',
        'session',to_jsonb(open_row),'server_now',now()
      );
    elsif cutoff_at >= open_row.check_in_at then
      update public.attendance_live_sessions
         set check_out_at=cutoff_at,
             check_out_location_name='Auto Day Close',
             check_out_verified=false,
             updated_at=now()
       where id=open_row.id
         and check_out_at is null;

      begin
        perform public.attendance_live_recalculate_day_internal(s.id,open_row.operational_date);
      exception when undefined_function then
        null;
      end;
      open_row := null;
    else
      raise exception 'An older live session needs Admin review before a new Check In.';
    end if;
  end if;

  select count(*) into prior_count
    from public.attendance_live_sessions
   where staff_id=s.id
     and operational_date=od
     and coalesce(is_deleted,false)=false;

  if p_rejoin and prior_count=0 then
    raise exception 'No completed duty session found to rejoin';
  end if;
  if not p_rejoin and prior_count>0 then
    raise exception 'You already worked today. Use Rejoin for a new split-shift session.';
  end if;

  verify := public.attendance_live_verify_workplace(p_lat,p_lon,p_public_ip);
  if not coalesce((verify->>'ok')::boolean,false) then
    raise exception '%',coalesce(verify->>'reason','Workplace verification failed');
  end if;

  sh := public.attendance_live_shift_info(now());
  next_no := prior_count+1;

  insert into public.attendance_live_sessions(
    staff_id,operational_date,session_no,check_in_at,
    check_in_lat,check_in_lon,check_in_public_ip,check_in_location_name,
    check_in_distance_m,check_in_verified,is_deleted
  ) values(
    s.id,od,next_no,now(),p_lat,p_lon,p_public_ip,verify->>'location_name',
    nullif(verify->>'distance_m','')::numeric,true,false
  ) returning * into new_row;

  insert into public.attendance_live_days(
    staff_id,operational_date,break_taken,classification,scheduled_start,
    late_minutes,is_deleted,deleted_at,deleted_reason
  ) values(
    s.id,od,true,'Duty',nullif(sh->>'scheduled_start','')::time,
    case when next_no=1 then coalesce((sh->>'late_minutes')::int,0) else 0 end,
    false,null,null
  )
  on conflict(branch_id,staff_id,operational_date) do update set
    classification='Duty',
    is_deleted=false,
    deleted_at=null,
    deleted_reason=null,
    scheduled_start=case when next_no=1 then excluded.scheduled_start else coalesce(public.attendance_live_days.scheduled_start,excluded.scheduled_start) end,
    late_minutes=case when next_no=1 then excluded.late_minutes else public.attendance_live_days.late_minutes end,
    updated_at=now()
  returning * into d;

  insert into public.attendance_live_audit(staff_id,operational_date,session_id,actor_type,action,after_data)
  values(
    s.id,od,new_row.id,'staff',case when p_rejoin then 'REJOIN' else 'CHECK_IN' end,
    jsonb_build_object('session',to_jsonb(new_row),'verification',verify)
  );

  return jsonb_build_object(
    'ok',true,'duplicate',false,'session',to_jsonb(new_row),
    'day',to_jsonb(d),'verification',verify,'server_now',now()
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.staff_live_attendance_set_break(p_token text, p_break_taken boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  open_row public.attendance_live_sessions;
  target_date date;
begin perform goya_private.check_capability(p_token,'attendance',null);
  sess := public.require_session(p_token,false);

  select * into open_row
    from public.attendance_live_sessions
   where staff_id=sess.staff_id
     and check_out_at is null
     and coalesce(is_deleted,false)=false
   order by check_in_at desc
   limit 1;

  target_date := coalesce(open_row.operational_date,public.attendance_live_operational_date(now()));

  update public.attendance_live_days
     set break_taken=coalesce(p_break_taken,true),updated_at=now()
   where staff_id=sess.staff_id
     and operational_date=target_date
     and coalesce(is_deleted,false)=false;

  return found;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.staff_live_attendance_set_split(p_token text, p_split_shift boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  od date:=public.attendance_live_operational_date(now());
  rules jsonb:=public.attendance_live_rules();
begin perform goya_private.check_capability(p_token,'attendance',null);
  sess:=public.require_session(p_token,false);

  if coalesce(p_split_shift,false)
     and coalesce((rules->>'split_shift_enabled')::boolean,true)=false then
    raise exception 'Split Shift is disabled by Admin';
  end if;

  update public.attendance_live_days
     set split_shift_allowed=coalesce(p_split_shift,false),
         updated_at=now()
   where staff_id=sess.staff_id
     and operational_date=od
     and coalesce(is_deleted,false)=false;

  -- If today's day row does not exist yet, create it safely so the staff choice
  -- can be stored before/around the duty flow without deleting any existing data.
  if not found then
    insert into public.attendance_live_days(
      staff_id,
      operational_date,
      break_taken,
      classification,
      split_shift_allowed
    )
    values(
      sess.staff_id,
      od,
      true,
      'Duty',
      coalesce(p_split_shift,false)
    )
    on conflict(branch_id,staff_id, operational_date) do update
      set split_shift_allowed=excluded.split_shift_allowed,
          updated_at=now();
  end if;

  return true;
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_live_attendance_check_out(p_token text, p_lat double precision, p_lon double precision, p_public_ip text, p_break_taken boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  s public.staff;
  verify jsonb;
  r public.attendance_live_sessions;
  before_row jsonb;
  cutoff_at timestamptz;
begin perform goya_private.check_capability(p_token,'attendance',null);
  sess := public.require_session(p_token,false);
  select * into s from goya_private.branch_staff_effective where id=sess.staff_id;
  perform pg_advisory_xact_lock(hashtext(s.id::text));

  select * into r
    from public.attendance_live_sessions
   where staff_id=s.id
     and check_out_at is null
     and coalesce(is_deleted,false)=false
   order by check_in_at desc
   limit 1;

  if r.id is null then
    raise exception 'No active Check In found';
  end if;

  cutoff_at := public.attendance_live_cutoff_at(r.operational_date);
  if now() > cutoff_at then
    if cutoff_at >= r.check_in_at then
      update public.attendance_live_sessions
         set check_out_at=cutoff_at,
             check_out_location_name='Auto Day Close',
             check_out_verified=false,
             updated_at=now()
       where id=r.id and check_out_at is null;

      begin
        perform public.attendance_live_recalculate_day_internal(s.id,r.operational_date);
      exception when undefined_function then
        null;
      end;
    end if;
    raise exception 'Check Out window closed at %',
      to_char(cutoff_at at time zone coalesce((public.attendance_live_rules()->>'timezone'),'Asia/Dubai'),'HH24:MI');
  end if;

  verify := public.attendance_live_verify_workplace(p_lat,p_lon,p_public_ip);
  if not coalesce((verify->>'ok')::boolean,false) then
    raise exception '%',coalesce(verify->>'reason','Workplace verification failed');
  end if;

  before_row := to_jsonb(r);

  update public.attendance_live_sessions
     set check_out_at=now(),
         check_out_lat=p_lat,
         check_out_lon=p_lon,
         check_out_public_ip=p_public_ip,
         check_out_location_name=verify->>'location_name',
         check_out_distance_m=nullif(verify->>'distance_m','')::numeric,
         check_out_verified=true,
         updated_at=now()
   where id=r.id
   returning * into r;

  update public.attendance_live_days
     set break_taken=coalesce(p_break_taken,true),
         is_deleted=false,
         deleted_at=null,
         deleted_reason=null,
         updated_at=now()
   where staff_id=s.id and operational_date=r.operational_date;

  begin
    perform public.attendance_live_recalculate_day_internal(s.id,r.operational_date);
  exception when undefined_function then
    null;
  end;

  insert into public.attendance_live_audit(
    staff_id,operational_date,session_id,actor_type,action,before_data,after_data
  ) values(
    s.id,r.operational_date,r.id,'staff','CHECK_OUT',before_row,
    jsonb_build_object('session',to_jsonb(r),'verification',verify,'break_taken',p_break_taken)
  );

  return jsonb_build_object('ok',true,'session',to_jsonb(r),'verification',verify,'server_now',now());
end;
$function$
;
CREATE OR REPLACE FUNCTION public.staff_live_attendance_history(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  sd date:=date_trunc('month',p_month)::date;
  ed date:=(date_trunc('month',p_month)+interval '1 month - 1 day')::date;
  rules jsonb:=public.attendance_live_rules();
  sys_start date:=coalesce((rules->>'system_start_date')::date,sd);
  today_local date:=timezone(coalesce(rules->>'timezone','Asia/Dubai'),now())::date;
begin perform goya_private.check_capability(p_token,'attendance',null);
  sess:=public.require_session(p_token,false);
  ed:=least(ed,today_local);
  if ed<sd then return jsonb_build_object('server_now',now(),'rows','[]'::jsonb,'rules',rules); end if;
  return jsonb_build_object('server_now',now(),'rules',rules,'rows',coalesce((
    with dates as (
      select g::date operational_date from generate_series(greatest(sd,sys_start),ed,interval '1 day') g
      union select d.operational_date from public.attendance_live_days d where d.staff_id=sess.staff_id and d.operational_date between sd and ed and coalesce(d.is_deleted,false)=false
      union select x.operational_date from public.attendance_live_sessions x where x.staff_id=sess.staff_id and x.operational_date between sd and ed and coalesce(x.is_deleted,false)=false
    )
    select jsonb_agg(to_jsonb(q) order by q.operational_date desc) from (
      select z.operational_date,coalesce(d.break_taken,true) break_taken,coalesce(d.split_shift_allowed,false) split_shift_allowed,
        case when exists(select 1 from public.attendance_live_sessions sx where sx.staff_id=sess.staff_id and sx.operational_date=z.operational_date and coalesce(sx.is_deleted,false)=false)
             then coalesce(nullif(d.classification,'Day Off - Pending Review'),'Duty') else coalesce(d.classification,'Day Off - Pending Review') end classification,
        d.classification_note,d.ot_policy,d.scheduled_start,coalesce(d.late_minutes,0) late_minutes,
        coalesce((select jsonb_agg(to_jsonb(x) order by x.check_in_at,x.created_at) from public.attendance_live_sessions x
          where x.staff_id=sess.staff_id and x.operational_date=z.operational_date and coalesce(x.is_deleted,false)=false),'[]'::jsonb) sessions
      from dates z left join public.attendance_live_days d on d.staff_id=sess.staff_id and d.operational_date=z.operational_date and coalesce(d.is_deleted,false)=false
      where goya_private.employed_on(sess.staff_id,z.operational_date)
    ) q
  ),'[]'::jsonb));
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_attendance_submit(p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; v_id uuid;
begin perform goya_private.check_capability(p_token,'attendance',null);
 sess:=public.require_session(p_token,false);
 select id into a_id from goya_private.branch_attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then
   insert into public.attendance_staff(portal_staff_id,name,employment_type,active)
   select id,name,'Full Time',active from goya_private.branch_staff_effective where id=sess.staff_id returning id into a_id;
 end if;
 -- Replace only an existing Pending request for the same day; Approved history is preserved.
 delete from public.attendance_staff_submissions where attendance_staff_id=a_id and operational_date=p_operational_date and status='Pending';
 insert into public.attendance_staff_submissions(attendance_staff_id,portal_staff_id,operational_date,punch_in,punch_out,break_taken,day_off,note,status)
 values(a_id,sess.staff_id,p_operational_date,case when p_day_off then null else p_punch_in end,case when p_day_off then null else p_punch_out end,coalesce(p_break_taken,true),coalesce(p_day_off,false),p_note,'Pending') returning id into v_id;
 return v_id;
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_attendance_month(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; sd date; ed date;
begin perform goya_private.check_capability(p_token,'attendance',null);
 sess:=public.require_session(p_token,false);
 select id into a_id from goya_private.branch_attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then return jsonb_build_object('records','[]'::jsonb,'submissions','[]'::jsonb); end if;
 sd:=date_trunc('month',p_month)::date;ed:=(sd+interval '1 month')::date;
 return jsonb_build_object(
  'records',coalesce((select jsonb_agg(to_jsonb(r) order by r.operational_date) from public.attendance_records r where r.attendance_staff_id=a_id and r.operational_date>=sd and r.operational_date<ed),'[]'::jsonb),
  'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.operational_date,s.submitted_at desc) from public.attendance_staff_submissions s where s.attendance_staff_id=a_id and s.operational_date>=sd and s.operational_date<ed),'[]'::jsonb)
 );
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_attendance_submit_v2(p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; v_id uuid;
begin perform goya_private.check_capability(p_token,'attendance',null);
 sess:=public.require_session(p_token,false);
 select id into a_id from goya_private.branch_attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then insert into public.attendance_staff(portal_staff_id,name,employment_type,active) select id,name,'Full Time',active from goya_private.branch_staff_effective where id=sess.staff_id returning id into a_id; end if;
 delete from public.attendance_staff_submissions where attendance_staff_id=a_id and operational_date=p_operational_date and status='Pending';
 insert into public.attendance_staff_submissions(attendance_staff_id,portal_staff_id,operational_date,punch_in,punch_out,break_taken,day_off,note,status,split_shift,shift2_in,shift2_out)
 values(a_id,sess.staff_id,p_operational_date,case when p_day_off then null else p_punch_in end,case when p_day_off then null else p_punch_out end,coalesce(p_break_taken,true),coalesce(p_day_off,false),p_note,'Pending',case when p_day_off then false else coalesce(p_split_shift,false) end,case when p_day_off then null else p_shift2_in end,case when p_day_off then null else p_shift2_out end) returning id into v_id;
 return v_id;
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_attendance_submit_v10(p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; v_id uuid;
begin perform goya_private.check_capability(p_token,'attendance',null);
 sess:=public.require_session(p_token,false);
 select id into a_id from goya_private.branch_attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then
   insert into public.attendance_staff(portal_staff_id,name,employment_type,active)
   select id,name,'Full Time',active from goya_private.branch_staff_effective where id=sess.staff_id returning id into a_id;
 end if;
 -- Re-submit replaces only the current not-finalized submission for that staff/date.
 delete from public.attendance_staff_submissions
 where attendance_staff_id=a_id and operational_date=p_operational_date and status in ('Pending','Submitted');
 insert into public.attendance_staff_submissions(attendance_staff_id,portal_staff_id,operational_date,punch_in,punch_out,break_taken,day_off,note,status,split_shift,shift2_in,shift2_out)
 values(a_id,sess.staff_id,p_operational_date,case when p_day_off then null else p_punch_in end,case when p_day_off then null else p_punch_out end,
   coalesce(p_break_taken,true),coalesce(p_day_off,false),p_note,'Submitted',
   case when p_day_off then false else coalesce(p_split_shift,false) end,
   case when p_day_off then null else p_shift2_in end,case when p_day_off then null else p_shift2_out end)
 returning id into v_id;
 return v_id;
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_attendance_month_v10(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; sd date; ed date;
begin perform goya_private.check_capability(p_token,'attendance',null);
 sess:=public.require_session(p_token,false);
 select id into a_id from goya_private.branch_attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then return jsonb_build_object('records','[]'::jsonb,'submissions','[]'::jsonb); end if;
 sd:=date_trunc('month',p_month)::date; ed:=(sd+interval '1 month')::date;
 return jsonb_build_object(
   'records',coalesce((select jsonb_agg(to_jsonb(r) order by r.operational_date) from public.attendance_records r where r.attendance_staff_id=a_id and r.operational_date>=sd and r.operational_date<ed),'[]'::jsonb),
   'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.operational_date,s.submitted_at desc) from public.attendance_staff_submissions s where s.attendance_staff_id=a_id and s.operational_date>=sd and s.operational_date<ed),'[]'::jsonb)
 );
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_attendance_month_v11(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; sd date; ed date; a public.attendance_staff; rules jsonb;
begin perform goya_private.check_capability(p_token,'attendance',null);
 sess:=public.require_session(p_token,false);
 select * into a from goya_private.branch_attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a.id is null then return jsonb_build_object('records','[]'::jsonb,'submissions','[]'::jsonb,'staff','{}'::jsonb); end if;
 a_id:=a.id; sd:=date_trunc('month',p_month)::date; ed:=(sd+interval '1 month')::date;
 select coalesce(value,'{}'::jsonb) into rules from public.attendance_settings where key='rules';
 return jsonb_build_object(
   'staff',to_jsonb(a) || jsonb_build_object('late_grace_minutes',coalesce((rules->>'late_grace_minutes')::int,15)),
   'records',coalesce((select jsonb_agg(to_jsonb(r) order by r.operational_date) from public.attendance_records r where r.attendance_staff_id=a_id and r.operational_date>=sd and r.operational_date<ed),'[]'::jsonb),
   'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.operational_date,s.submitted_at desc) from public.attendance_staff_submissions s where s.attendance_staff_id=a_id and s.operational_date>=sd and s.operational_date<ed),'[]'::jsonb)
 );
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_attendance_submit_v12(p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; v_id uuid; cur_month date;
begin perform goya_private.check_capability(p_token,'attendance',null);
 sess:=public.require_session(p_token,false);
 cur_month:=date_trunc('month',(now() at time zone 'Asia/Dubai')::date)::date;
 if date_trunc('month',p_operational_date)::date<>cur_month then
   raise exception 'Previous month attendance is locked for staff editing.';
 end if;
 select id into a_id from goya_private.branch_attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then
   insert into public.attendance_staff(portal_staff_id,name,employment_type,active)
   select id,name,'Full Time',active from goya_private.branch_staff_effective where id=sess.staff_id returning id into a_id;
 end if;
 delete from public.attendance_staff_submissions
 where attendance_staff_id=a_id and operational_date=p_operational_date and status in ('Pending','Submitted');
 insert into public.attendance_staff_submissions(attendance_staff_id,portal_staff_id,operational_date,punch_in,punch_out,break_taken,day_off,note,status,split_shift,shift2_in,shift2_out)
 values(a_id,sess.staff_id,p_operational_date,case when p_day_off then null else p_punch_in end,case when p_day_off then null else p_punch_out end,
   coalesce(p_break_taken,true),coalesce(p_day_off,false),p_note,'Submitted',case when p_day_off then false else coalesce(p_split_shift,false) end,
   case when p_day_off then null else p_shift2_in end,case when p_day_off then null else p_shift2_out end)
 returning id into v_id;
 return v_id;
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_attendance_month_v12(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; sd date; ed date; a public.attendance_staff; rules jsonb;
begin perform goya_private.check_capability(p_token,'attendance',null);
 sess:=public.require_session(p_token,false);
 select * into a from goya_private.branch_attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a.id is null then return jsonb_build_object('records','[]'::jsonb,'submissions','[]'::jsonb,'staff','{}'::jsonb); end if;
 a_id:=a.id; sd:=date_trunc('month',p_month)::date; ed:=(sd+interval '1 month')::date;
 select coalesce(value,'{}'::jsonb) into rules from public.attendance_settings where key='rules';
 return jsonb_build_object(
   'staff',to_jsonb(a) || jsonb_build_object(
      'late_grace_minutes',coalesce((rules->>'late_grace_minutes')::int,15),
      'shift_start_times',coalesce(rules->'shift_start_times',jsonb_build_array(coalesce(rules->>'operational_start','08:00')))
   ),
   'records',coalesce((select jsonb_agg(to_jsonb(r) order by r.operational_date) from public.attendance_records r where goya_private.employed_on(sess.staff_id,r.operational_date) and r.attendance_staff_id=a_id and r.operational_date>=sd and r.operational_date<ed),'[]'::jsonb),
   'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.operational_date,s.submitted_at desc) from public.attendance_staff_submissions s where goya_private.employed_on(sess.staff_id,s.operational_date) and s.attendance_staff_id=a_id and s.operational_date>=sd and s.operational_date<ed),'[]'::jsonb)
 );
end $function$
;
CREATE OR REPLACE FUNCTION public.goya_staff_history_page(p_token text, p_kind text DEFAULT 'orders'::text, p_month date DEFAULT CURRENT_DATE, p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare lo timestamptz:=date_trunc('month',p_month)::timestamp at time zone 'Asia/Dubai';hi timestamptz:=(date_trunc('month',p_month)+interval '1 month')::timestamp at time zone 'Asia/Dubai';tab text;col text;total bigint;pagev int;rowsv jsonb;q text;sectionv text;
begin perform goya_private.check_capability(p_token,case p_kind when 'orders' then 'order' else p_kind end);
 perform public.require_session(p_token,false);
 if p_kind='orders' then return public.goya_orders_page(p_token,false,coalesce(p_filters,'{}')||jsonb_build_object('month',p_month),p_page);end if;
 if p_kind='inventory' then
  q:=lower(trim(coalesce(p_filters->>'search','')));sectionv:=trim(coalesce(p_filters->>'section',''));
  select count(*) into total from public.inventory_counts i where i.counted_at>=lo and i.counted_at<hi
   and (q='' or strpos(lower(coalesce(i.item_name,'')),q)>0 or strpos(lower(coalesce(i.sku,'')),q)>0)
   and (sectionv='' or i.section=sectionv);
  pagev:=least(greatest(coalesce(p_page,1),1),greatest(1,ceil(total/30.0)::int));
  select coalesce(jsonb_agg(to_jsonb(x) order by x.counted_at desc,x.id desc),'[]'::jsonb) into rowsv from
   (select i.* from public.inventory_counts i where i.counted_at>=lo and i.counted_at<hi
    and (q='' or strpos(lower(coalesce(i.item_name,'')),q)>0 or strpos(lower(coalesce(i.sku,'')),q)>0)
    and (sectionv='' or i.section=sectionv) order by i.counted_at desc,i.id desc limit 30 offset (pagev-1)::bigint*30)x;
  return jsonb_build_object('rows',rowsv,'total',total,'page',pagev,'page_size',30);
 end if;
 case p_kind when 'production' then tab:='production_batches';col:='created_at';when 'wastage' then tab:='wastage_entries';col:='created_at';else raise exception 'Invalid history kind';end case;
 execute format('select count(*) from public.%I where %I>=$1 and %I<$2',tab,col,col) into total using lo,hi;
 pagev:=least(greatest(coalesce(p_page,1),1),greatest(1,ceil(total/30.0)::int));
 execute format('select coalesce(jsonb_agg(to_jsonb(x) order by x.%I desc,x.id desc),''[]''::jsonb) from (select * from public.%I where %I>=$1 and %I<$2 order by %I desc,id desc limit 30 offset $3)x',col,tab,col,col,col) into rowsv using lo,hi,(pagev-1)::bigint*30;
 return jsonb_build_object('rows',rowsv,'total',total,'page',pagev,'page_size',30);
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_draft_save(p_token text, p_kind text, p_items jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  k text := lower(trim(p_kind));
begin perform goya_private.check_capability(p_token,case p_kind when 'orders' then 'order' when 'order' then 'order' else p_kind end);
  sess := public.require_session(p_token,false);
  if k not in ('order','production','wastage') then
    raise exception 'Invalid draft type';
  end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array' then
    raise exception 'Invalid draft payload';
  end if;
  insert into public.staff_drafts(staff_id,draft_type,items,updated_at)
  values(sess.staff_id,k,coalesce(p_items,'[]'::jsonb),now())
  on conflict(branch_id,staff_id,draft_type)
  do update set items=excluded.items,updated_at=now();
  return true;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.staff_draft_clear(p_token text, p_kind text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  k text := lower(trim(p_kind));
begin perform goya_private.check_capability(p_token,case p_kind when 'orders' then 'order' when 'order' then 'order' else p_kind end);
  sess := public.require_session(p_token,false);
  if k not in ('order','production','wastage') then
    raise exception 'Invalid draft type';
  end if;
  delete from public.staff_drafts
  where staff_id=sess.staff_id and draft_type=k;
  return true;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.goya_portal_duplicate_check(p_token text, p_kind text, p_items jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.app_sessions;s public.staff; cutoff timestamptz:=now()-interval '10 minutes';
begin perform goya_private.check_capability(p_token,case p_kind when 'orders' then 'order' when 'order' then 'order' else p_kind end);
 a:=public.require_session(p_token,false);select * into s from goya_private.branch_staff_effective where id=a.staff_id and active;
 if s.id is null then raise exception 'Unauthorized';end if;
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>500 then raise exception 'Invalid submission';end if;
 if p_kind='equipment' then
  return exists(select 1 from goya_private.equipment_reports r where r.staff_id=s.id and r.created_at>=cutoff
   and r.item_name=btrim(p_items->0->>'item_name') and r.quantity=btrim(coalesce(p_items->0->>'quantity',''))
   and r.details=btrim(p_items->0->>'details') and r.section=coalesce(p_items->0->>'section','') and r.incident_date=(p_items->0->>'incident_date')::date);
 elsif p_kind='orders' then
  if not s.can_order then raise exception 'Order access disabled';end if;
  return exists(select 1 from public.order_groups g where g.submitted_by=s.id and g.created_at>=cutoff and
   (select jsonb_agg(jsonb_build_array(btrim(o.name),btrim(o.sku),o.quantity,btrim(o.unit),coalesce(o.supplier,''),coalesce(o.notes,'')) order by btrim(o.name),btrim(o.sku),o.quantity,btrim(o.unit),coalesce(o.supplier,''),coalesce(o.notes,'')) from public.orders o where o.order_group_id=g.id)=
   (select jsonb_agg(jsonb_build_array(btrim(i->>'name'),btrim(i->>'sku'),(i->>'quantity')::numeric,btrim(i->>'unit'),coalesce(i->>'supplier',''),coalesce(i->>'notes','')) order by btrim(i->>'name'),btrim(i->>'sku'),(i->>'quantity')::numeric,btrim(i->>'unit'),coalesce(i->>'supplier',''),coalesce(i->>'notes','')) from jsonb_array_elements(p_items)i));
 elsif p_kind in ('production','wastage') then
  if (p_kind='production' and not s.can_production) or (p_kind='wastage' and not s.can_wastage) then raise exception 'Access disabled';end if;
  return exists(with recent as (
   select batch_group_id gid,name,sku,quantity,unit,storage_quantity,ingredients_quantity,''::text reason from public.production_batches where p_kind='production' and logged_by=s.name and created_at>=cutoff
   union all select wastage_group_id,name,sku,quantity,unit,storage_quantity,ingredients_quantity,coalesce(reason,'') from public.wastage_entries where p_kind='wastage' and logged_by=s.name and created_at>=cutoff),
   grouped as(select gid,jsonb_agg(jsonb_build_array(btrim(name),btrim(sku),quantity,btrim(unit),storage_quantity,ingredients_quantity,reason) order by btrim(name),btrim(sku),quantity,btrim(unit),storage_quantity,ingredients_quantity,reason) items from recent group by gid)
   select 1 from grouped where items=(select jsonb_agg(jsonb_build_array(btrim(i->>'name'),btrim(i->>'sku'),(i->>'quantity')::numeric,btrim(i->>'unit'),nullif(i->>'storage_quantity','')::numeric,nullif(i->>'ingredients_quantity','')::numeric,case when p_kind='wastage' then btrim(coalesce(i->>'reason','')) else '' end) order by btrim(i->>'name'),btrim(i->>'sku'),(i->>'quantity')::numeric,btrim(i->>'unit'),nullif(i->>'storage_quantity','')::numeric,nullif(i->>'ingredients_quantity','')::numeric,case when p_kind='wastage' then btrim(coalesce(i->>'reason','')) else '' end) from jsonb_array_elements(p_items)i));
 else raise exception 'Invalid submission type';end if;
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_bootstrap(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions;s public.staff;
begin
  sess:=public.require_session(p_token,false);select * into s from goya_private.branch_staff_effective where id=sess.staff_id;
  return jsonb_build_object(
    'access',goya_private.branch_access(sess.staff_id),'master_items',(select coalesce(jsonb_agg(to_jsonb(x) order by lower(x.name)),'[]'::jsonb) from public.master_items x where x.active=true and x.items_type in(select jsonb_array_elements_text(goya_private.branch_access(sess.staff_id)->'sections'))),
    'internal_items',(select coalesce(jsonb_agg(to_jsonb(x) order by lower(x.name)),'[]'::jsonb) from public.internal_items x where x.active=true and x.items_type in(select jsonb_array_elements_text(goya_private.branch_access(sess.staff_id)->'sections'))),
    'suppliers',(select coalesce(jsonb_agg(to_jsonb(x) order by lower(x.name)),'[]'::jsonb) from public.suppliers x where x.active=true),
    'info_pages',(select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.title),'[]'::jsonb) from public.info_pages x where x.active=true),
    'inventory_sessions',(select coalesce(jsonb_agg(to_jsonb(v) order by v.month desc),'[]'::jsonb) from public.inventory_sessions v where v.active=true and s.sections && v.sections and (s.id=any(v.assigned_staff_ids) or (coalesce(array_length(v.assigned_staff_ids,1),0)=0 and s.can_inventory)))
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.goya_staff_dashboard(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare sess public.app_sessions; current_day jsonb; month_start date;
begin
 sess:=public.require_session(p_token,false);
 current_day:=case when (goya_private.branch_access(sess.staff_id)->>'attendance')::boolean then public.staff_live_attendance_status(p_token) else jsonb_build_object('sessions','[]'::jsonb,'rules','{}'::jsonb,'day',null) end;
 month_start:=date_trunc('month',timezone('Asia/Dubai',now()))::date;
 return jsonb_build_object('server_now',now(),'today',current_day,'month',month_start,
 'attendance',case when (goya_private.branch_access(sess.staff_id)->>'attendance')::boolean then public.staff_live_attendance_history(p_token,month_start) else '[]'::jsonb end,
 'legacy',case when (goya_private.branch_access(sess.staff_id)->>'attendance')::boolean then public.staff_attendance_month_v12(p_token,month_start) else '{}'::jsonb end,
 'notices',(select coalesce(jsonb_agg(to_jsonb(n) order by n.important desc,n.published_at desc),'[]'::jsonb) from goya_private.notices n where active and published_at<=now() and (expires_at is null or expires_at>now())),
 'orders',jsonb_build_object('Pending',(select count(*) from public.orders where (goya_private.branch_access(sess.staff_id)->>'order')::boolean and status='Pending'),'Ordered',(select count(*) from public.orders where (goya_private.branch_access(sess.staff_id)->>'order')::boolean and status='Ordered'),'Received',(select count(*) from public.orders where (goya_private.branch_access(sess.staff_id)->>'order')::boolean and status='Received' and created_at>=month_start),'Not Received',(select count(*) from public.orders where (goya_private.branch_access(sess.staff_id)->>'order')::boolean and status='Not Received' and created_at>=month_start)),
 'operations',jsonb_build_object('production',(select count(*) from public.production_batches where (goya_private.branch_access(sess.staff_id)->>'production')::boolean and created_at>=month_start),'wastage',(select count(*) from public.wastage_entries where (goya_private.branch_access(sess.staff_id)->>'wastage')::boolean and created_at>=month_start)),
 'push_public_key',(select public_key from goya_private.push_config where id));
end $function$
;
CREATE OR REPLACE FUNCTION public.goya_roster_save(p_token text, p_week date, p_expected integer, p_schedule jsonb, p_publish boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare next_revision integer; member record; day jsonb; segment jsonb; previous_end integer; start_min integer; end_min integer;
  snapshot jsonb; leave_day record; approval_actor text;
begin
  perform public.require_session(p_token,true);
  approval_actor:=p_schedule->>'approval_actor';p_schedule:=p_schedule-'approval_actor';
  if p_publish then
   perform 1 from goya_private.branch_staff where id::text in(select key from jsonb_each(p_schedule->'staff'))
    or id in(select staff_id from goya_private.roster_off_charges where charged and off_date between p_week and p_week+6) order by id for update;
  end if;
  if p_week is null or p_schedule is null or p_expected is null or p_publish is null
    or extract(isodow from p_week)<>1 or jsonb_typeof(p_schedule->'staff') is distinct from 'object'
    or jsonb_typeof(p_schedule->'notes') is distinct from 'string'
    or length(p_schedule->>'notes')>2000 or octet_length(p_schedule::text)>262144 then
    raise exception 'Invalid roster';
  end if;
  for member in select * from jsonb_each(p_schedule->'staff') loop
    if not exists(select 1 from goya_private.branch_staff s where s.id::text=member.key and (not p_publish or s.active))
      or jsonb_typeof(member.value) is distinct from 'array' then raise exception 'Invalid roster staff'; end if;
    if jsonb_array_length(member.value)<>7 then raise exception 'Enter all seven days'; end if;
    for day in select value from jsonb_array_elements(member.value) loop
      if day='null'::jsonb then continue; end if;
      if jsonb_typeof(day) is distinct from 'object'
        or coalesce(day->>'kind','') not in ('Shift','Event','Weekly Off','Annual Leave','Sick Leave','Other Leave')
        or jsonb_typeof(day->'segments') is distinct from 'array' then raise exception 'Invalid roster day'; end if;
      if day ? 'off_source' and (day->>'kind'<>'Weekly Off' or coalesce(day->>'off_source','') not in ('balance','advance')) then raise exception 'Invalid Paid Off source';end if;
      if day ? 'label' and (day->>'kind'<>'Shift' or jsonb_typeof(day->'label') is distinct from 'string'
        or length(btrim(day->>'label')) not between 1 and 60 or day->>'label' ~ '[[:cntrl:]]') then
        raise exception 'Enter a custom shift name of 1–60 characters';
      end if;
      if length(coalesce(day->>'note',''))>500 then raise exception 'Shift note is too long'; end if;
      if day->>'kind'='Event' then
 if jsonb_array_length(day->'segments')<>0 or not exists(select 1 from goya_private.branches b join goya_private.branch_members m on m.branch_id=b.id where b.id=nullif(day->>'event_branch','')::uuid and b.id<>goya_private.current_branch() and b.kind='event' and b.archived_at is null and m.staff_id=member.key::uuid and (goya_private.branch_access(m.staff_id,b.id)->>'schedule')::boolean) then raise exception 'Choose an Event branch with schedule access for this staff';end if;
 elsif day->>'kind'='Shift' then
        if jsonb_array_length(day->'segments') not between 1 and 2 then raise exception 'A shift needs one or two time blocks'; end if;
        previous_end := -1;
        for segment in select value from jsonb_array_elements(day->'segments') loop
          if coalesce(segment->>'start','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
            or coalesce(segment->>'end','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
            or coalesce(segment->>'break','') !~ '^[0-9]{1,3}$' then raise exception 'Invalid shift time'; end if;
          start_min := extract(epoch from (segment->>'start')::time)::integer/60;
          end_min := extract(epoch from (segment->>'end')::time)::integer/60;
          if end_min<start_min then end_min := end_min+1440; end if;
          if start_min<previous_end or end_min<=start_min or (segment->>'break')::integer>=end_min-start_min then
            raise exception 'Shift blocks overlap or break exceeds the shift';
          end if;
          previous_end := end_min;
        end loop;
      elsif jsonb_array_length(day->'segments')<>0 then raise exception 'Off or leave days cannot contain a shift'; end if;
    end loop;
  end loop;
  snapshot := p_schedule;
  if p_publish then
    for leave_day in
      select r.staff_id::text as staff_id,case when r.kind in ('Pending Off','Advance Off') then 'Weekly Off' when r.kind='Emergency Leave' then 'Other Leave' else r.kind end as kind,r.kind as request_kind,d as day_index
      from goya_private.staff_leave_requests r join goya_private.branch_staff s on s.id=r.staff_id and s.active
      cross join generate_series(0,6) as dates(d)
      where r.kind<>'Resignation' and r.state='Approved' and p_week+d between r.approved_from and r.approved_to
      order by r.staff_id,d
    loop
      if not ((snapshot->'staff') ? leave_day.staff_id) then
        snapshot := jsonb_set(snapshot,array['staff',leave_day.staff_id],'[null,null,null,null,null,null,null]');
      end if;
      snapshot := jsonb_set(snapshot,array['staff',leave_day.staff_id,leave_day.day_index::text],
        jsonb_build_object('kind',leave_day.kind,'segments','[]'::jsonb,'note','')||case when leave_day.request_kind in ('Pending Off','Advance Off') then jsonb_build_object('off_source','request') else '{}'::jsonb end);
    end loop;
  end if;
  if p_publish then
    for member in select * from jsonb_each(snapshot->'staff') loop
      for start_min in 0..6 loop
        if not goya_private.employed_on(member.key::uuid,p_week+start_min) then
          snapshot:=jsonb_set(snapshot,array['staff',member.key,start_min::text],'null'::jsonb);
        end if;
      end loop;
    end loop;
  end if;
  if p_publish then perform goya_private.validate_branch_roster(goya_private.current_branch(),p_week,snapshot);end if;
  if p_publish and not exists(select 1 from jsonb_each(snapshot->'staff') m
    cross join lateral jsonb_array_elements(m.value) as days(value) where days.value<>'null'::jsonb) then
    raise exception 'Add at least one shift or day status before publishing';
  end if;
  if p_expected=0 then
    insert into goya_private.roster_weeks(week_start,draft) values(p_week,p_schedule)
      on conflict do nothing returning revision into next_revision;
  else
    update goya_private.roster_weeks set draft=p_schedule,revision=revision+1 where week_start=p_week and revision=p_expected
      returning revision into next_revision;
  end if;
  if next_revision is null then raise exception 'This roster changed. Reload before saving.'; end if;
  if p_publish then
    perform goya_private.reconcile_roster_off(p_token,p_week,snapshot,next_revision,approval_actor);
    insert into goya_private.roster_publications(week_start,revision,schedule) values(p_week,next_revision,snapshot);
    update goya_private.roster_weeks set published_revision=next_revision where week_start=p_week;
  end if;
  return next_revision;
end $function$
;
CREATE OR REPLACE FUNCTION public.goya_roster_admin_week(p_token text, p_week date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.require_session(p_token,true);
  return jsonb_build_object(
    'draft',(select to_jsonb(w)||jsonb_build_object('published_staff',p.schedule->'staff')
      from goya_private.roster_weeks w left join goya_private.roster_publications p
      on p.week_start=w.week_start and p.revision=w.published_revision where w.week_start=p_week),
    'event_targets',coalesce((select jsonb_object_agg(s.id::text,(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',b.name) order by b.name),'[]') from goya_private.branches b join goya_private.branch_members m on m.branch_id=b.id where m.staff_id=s.id and b.kind='event' and b.id<>goya_private.current_branch() and b.archived_at is null and (goya_private.branch_access(s.id,b.id)->>'schedule')::boolean)) from goya_private.branch_staff s),'{}'), 'off_balances',public.goya_management_balances(p_token),'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'employee_code',hp.employee_code,'sections',s.sections,'roster_group',hp.roster_group,'eligible_days',(select jsonb_agg(goya_private.employed_on(s.id,p_week+i) order by i) from generate_series(0,6) i),'joining_date',hp.joining_date,'last_day',coalesce(hp.last_day,(select r.last_working_day from goya_private.staff_resignations r where r.staff_id=s.id and r.cancelled_at is null))) order by s.name,s.id)
      from goya_private.branch_staff s left join goya_private.staff_hr_profiles hp on hp.staff_id=s.id where (hp.joining_date is null or hp.joining_date<=p_week+6) and s.active and (goya_private.branch_access(s.id)->>'schedule')::boolean and not exists(select 1 from goya_private.staff_resignations x where x.staff_id=s.id and x.cancelled_at is null and x.last_working_day<p_week)),'[]'::jsonb),
    'approved_leave',public.goya_hr_week_leave(p_token,p_week),
    'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.revision desc) from
      (select revision,published_at from goya_private.roster_publications where week_start=p_week order by revision desc limit 30) h),'[]'::jsonb)
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_history(p_token text, p_month date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  start_d date;
  end_d date;
begin
  -- A valid staff session is still required, but records are no longer
  -- filtered by the logged-in staff member.
  sess := public.require_session(p_token,false);
  start_d := date_trunc('month',p_month)::date;
  end_d := (start_d + interval '1 month')::date;

  return (select coalesce(jsonb_object_agg(k,v),'{}'::jsonb) from jsonb_each(jsonb_build_object(
    'orders',(
      select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb)
      from (
        select o.id,g.order_no,o.name,o.sku,o.quantity,o.unit,o.supplier,
               o.status,o.received_date,o.logged_by,o.notes,o.created_at
        from public.orders o
        join public.order_groups g on g.id=o.order_group_id
        where o.created_at>=start_d and o.created_at<end_d
      ) q
    ),
    'production',(
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
      from public.production_batches x
      where x.created_at>=start_d and x.created_at<end_d
    ),
    'wastage',(
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
      from public.wastage_entries x
      where x.created_at>=start_d and x.created_at<end_d
    ),
    'inventory',(
      select coalesce(jsonb_agg(to_jsonb(x) order by x.counted_at desc),'[]'::jsonb)
      from public.inventory_counts x
      where x.counted_at>=start_d and x.counted_at<end_d
    )
  )) entries(k,v) where coalesce((goya_private.branch_access(sess.staff_id)->>case k when 'orders' then 'order' else k end)::boolean,false));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.staff_draft_get(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
begin
  sess := public.require_session(p_token,false);
  return (select coalesce(jsonb_object_agg(k,v),'{}'::jsonb) from jsonb_each(jsonb_build_object(
    'order',coalesce((select items from public.staff_drafts where staff_id=sess.staff_id and draft_type='order'),'[]'::jsonb),
    'production',coalesce((select items from public.staff_drafts where staff_id=sess.staff_id and draft_type='production'),'[]'::jsonb),
    'wastage',coalesce((select items from public.staff_drafts where staff_id=sess.staff_id and draft_type='wastage'),'[]'::jsonb)
  )) entries(k,v) where coalesce((goya_private.branch_access(sess.staff_id)->>case k when 'orders' then 'order' else k end)::boolean,false));
end;
$function$
;
CREATE OR REPLACE FUNCTION goya_private.validate_branch_roster(p_branch uuid, p_week date, p_schedule jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare conflict_name text;begin
 with incoming as(select member.key employee,p_week+day.ordinality::int-1 as d,segment.value seg from jsonb_each(p_schedule->'staff') member cross join lateral jsonb_array_elements(member.value) with ordinality day(value,ordinality) cross join lateral jsonb_array_elements(day.value->'segments') segment where day.value->>'kind'='Shift' and coalesce(day.value->>'label','')<>'EVENT'),
 existing as(select member.key employee,p.week_start+day.ordinality::int-1 as d,segment.value seg,b.name from goya_private.roster_publications p join goya_private.roster_weeks w on (w.branch_id,w.week_start,w.published_revision)=(p.branch_id,p.week_start,p.revision) join goya_private.branches b on b.id=p.branch_id cross join lateral jsonb_each(p.schedule->'staff') member cross join lateral jsonb_array_elements(member.value) with ordinality day(value,ordinality) cross join lateral jsonb_array_elements(day.value->'segments') segment where p.branch_id<>p_branch and p.week_start between p_week-7 and p_week+7 and day.value->>'kind'='Shift' and coalesce(day.value->>'label','')<>'EVENT')
 select e.name into conflict_name from incoming i join existing e on e.employee=i.employee where tsrange(i.d+(i.seg->>'start')::time,i.d+(i.seg->>'end')::time+case when i.seg->>'end'<i.seg->>'start' then interval '1 day' else interval '0' end,'[)') && tsrange(e.d+(e.seg->>'start')::time,e.d+(e.seg->>'end')::time+case when e.seg->>'end'<e.seg->>'start' then interval '1 day' else interval '0' end,'[)') limit 1;
 if conflict_name is not null then raise exception 'A staff shift overlaps the published roster at %. Adjust the duty time before publishing.',conflict_name;end if;end$function$
;
CREATE OR REPLACE FUNCTION public.goya_branch_save(p_token text, p_row jsonb, p_expected integer DEFAULT 0)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare sess public.app_sessions;b uuid;previous jsonb;oldrev integer;member uuid;begin
 select * into sess from public.app_sessions where token=p_token and expires_at>now() and is_admin;
 if sess.token is null then raise exception 'Management access required';end if;
 if jsonb_typeof(p_row) is distinct from 'object' or length(btrim(coalesce(p_row->>'name',''))) not between 1 and 100 or coalesce(p_row->>'kind','') not in('branch','event') or length(coalesce(p_row->>'address',''))>1000 or jsonb_typeof(p_row->'members') is distinct from 'array' then raise exception 'Enter a branch name, type and valid staff list';end if;
 b:=coalesce(nullif(p_row->>'id','')::uuid,gen_random_uuid());
 perform 1 from public.staff where id in(select staff_id from goya_private.branch_members where branch_id=b) or id in(select value::uuid from jsonb_array_elements_text(p_row->'members')) order by id for update;perform pg_advisory_xact_lock(hashtext(b::text));
 select to_jsonb(x),revision into previous,oldrev from goya_private.branches x where id=b for update;
 if coalesce(oldrev,0)<>p_expected then raise exception 'Branch changed on another device. Reload before saving';end if;
 if b='00000000-0000-0000-0000-000000000001' and (p_row->>'archived')::boolean then raise exception 'The original GOYA branch must remain available';end if;
 for member in select value::uuid from jsonb_array_elements_text(p_row->'members') loop if not exists(select 1 from public.staff where id=member) then raise exception 'Unknown staff member';end if;end loop;
 insert into goya_private.branches(id,name,kind,address,starts_on,ends_on,archived_at) values(b,btrim(p_row->>'name'),p_row->>'kind',btrim(coalesce(p_row->>'address','')),nullif(p_row->>'starts_on','')::date,nullif(p_row->>'ends_on','')::date,case when coalesce((p_row->>'archived')::boolean,false) then now() end)
 on conflict(id) do update set name=excluded.name,kind=excluded.kind,address=excluded.address,starts_on=excluded.starts_on,ends_on=excluded.ends_on,archived_at=case when excluded.archived_at is not null then coalesce(branches.archived_at,excluded.archived_at) end,revision=branches.revision+1;
 insert into goya_private.staff_access_versions(staff_id,revision) select s.id,1 from public.staff s where (s.id in(select staff_id from goya_private.branch_members where branch_id=b)) is distinct from (s.id in(select value::uuid from jsonb_array_elements_text(p_row->'members'))) on conflict(staff_id) do update set revision=staff_access_versions.revision+1; -- Membership changes do not remove any operational records or employee history.
 delete from goya_private.branch_members where branch_id=b and not(staff_id in(select value::uuid from jsonb_array_elements_text(p_row->'members')));
 insert into goya_private.branch_members(branch_id,staff_id) select b,value::uuid from jsonb_array_elements_text(p_row->'members') on conflict do nothing;
 if previous is null then
 insert into public.attendance_settings(key,value,branch_id) select key,value,b from public.attendance_settings where branch_id='00000000-0000-0000-0000-000000000001' and key<>'management_share';
 -- New locations start with no inherited GPS/IP allowlist; management must configure their own workplace.
 update public.attendance_settings set value=value||jsonb_build_object('locations','[]'::jsonb,'approved_public_ips','[]'::jsonb) where branch_id=b and key='live_rules';
 insert into public.settings(key,value,branch_id) select key,value,b from public.settings where branch_id='00000000-0000-0000-0000-000000000001';end if;
 insert into goya_private.branch_audit(branch_id,before_data,after_data) select b,previous,to_jsonb(x)||jsonb_build_object('members',p_row->'members') from goya_private.branches x where id=b;
 return b;end$function$
;
CREATE OR REPLACE FUNCTION goya_private.inventory_shared_open(p_token text, p_session_id uuid, p_section text)
 RETURNS goya_private.inventory_shared_sheets
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.app_sessions;s public.staff;v public.inventory_sessions;h goya_private.inventory_shared_sheets;
begin
 a:=public.require_session(p_token,false);
 select * into s from goya_private.branch_staff_effective where id=a.staff_id and active for share;
 if s.id is null then raise exception 'Staff is inactive or unauthorized';end if;
 select * into v from public.inventory_sessions where id=p_session_id for share;
 if v.id is null or not v.shared_count or not v.active or not(p_section=any(v.sections)) or not(p_section=any(s.sections))
 or not(s.id=any(v.assigned_staff_ids) or (cardinality(v.assigned_staff_ids)=0 and s.can_inventory)) then raise exception 'Inventory section is not assigned to this staff';end if;
 if not exists(select 1 from goya_private.inventory_shared_sheets where session_id=v.id and section=p_section) then
  if exists(select sku from (select sku from public.master_items where active and lower(items_type)=lower(p_section) union all select sku from public.internal_items where active and lower(items_type)=lower(p_section))q group by sku having count(*)>1) then raise exception 'Duplicate item SKU in this section. Ask Admin to correct it before starting the sheet.';end if;
  insert into goya_private.inventory_shared_sheets(session_id,section,sheet_name,counting_date)
  values(v.id,p_section,coalesce(nullif(v.title,''),'Inventory Count')||' — '||p_section||' — '||to_char(coalesce(v.counting_date,timezone('Asia/Dubai',now())::date),'DD Mon YYYY'),coalesce(v.counting_date,timezone('Asia/Dubai',now())::date)) on conflict(session_id,section) do nothing;
 end if;
 select * into h from goya_private.inventory_shared_sheets where session_id=v.id and section=p_section for update;
 -- Catalog snapshot is taken once, so item-master edits cannot silently remove count entries.
 if not h.initialized then
  insert into goya_private.inventory_shared_lines(sheet_id,sku,item_name,source,storage_unit,ingredient_unit)
  select h.id,sku,name,'Master',storage_unit,ingredient_unit from public.master_items where active and lower(items_type)=lower(p_section)
  union all select h.id,sku,name,'Internal',storage_unit,ingredient_unit from public.internal_items where active and lower(items_type)=lower(p_section);
  update goya_private.inventory_shared_sheets set initialized=true where id=h.id;
 end if;
 return h;
end $function$
;

do $preserve$ declare r record;n bigint;h text;begin for r in select * from goya_access_preservation loop
execute format('select count(*),md5(coalesce(string_agg(md5((to_jsonb(x)-''permissions'')::text),'''' order by md5((to_jsonb(x)-''permissions'')::text)),'''')) from %I.%I x',r.schema_name,r.table_name) into n,h;
if n<>r.row_count or h is distinct from r.fingerprint then raise exception 'Data preservation check failed for %.% — entire migration rolled back',r.schema_name,r.table_name;end if;end loop;end $preserve$;
notify pgrst,'reload schema';commit;
