CREATE OR REPLACE FUNCTION public.admin_export_dataset(p_token text, p_dataset text, p_month date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare sd date;ed date;
begin
  perform public.require_session(p_token,true);if p_month is not null then sd:=date_trunc('month',p_month)::date;ed:=(sd+interval '1 month')::date;end if;
  case p_dataset
    when 'orders' then return coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (select g.order_no,o.name,o.sku,o.quantity,o.unit,o.supplier,o.status,o.received_date,o.logged_by,o.notes,o.created_at from public.orders o join public.order_groups g on g.id=o.order_group_id where p_month is null or (o.created_at>=sd and o.created_at<ed))q),'[]'::jsonb);
    when 'production' then return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.production_batches x where p_month is null or (x.created_at>=sd and x.created_at<ed)),'[]'::jsonb);
    when 'wastage' then return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.wastage_entries x where p_month is null or (x.created_at>=sd and x.created_at<ed)),'[]'::jsonb);
    when 'inventory' then return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.inventory_counts x where p_month is null or (x.created_at>=sd and x.created_at<ed)),'[]'::jsonb);
    when 'complaints' then return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.complaint_feedback x where p_month is null or (x.created_at>=sd and x.created_at<ed)),'[]'::jsonb);
    when 'master_items' then return coalesce((select jsonb_agg(to_jsonb(x) order by lower(x.name)) from public.master_items x),'[]'::jsonb);
    when 'internal_items' then return coalesce((select jsonb_agg(to_jsonb(x) order by lower(x.name)) from public.internal_items x),'[]'::jsonb);
    when 'staff' then return coalesce((select jsonb_agg(jsonb_build_object('name',x.name,'pin',x.pin_code,'active',x.active,'orders',x.can_order,'production',x.can_production,'wastage',x.can_wastage,'inventory',x.can_inventory,'sections',array_to_string(x.sections,', ')) order by lower(x.name)) from public.staff x),'[]'::jsonb);
    when 'suppliers' then return coalesce((select jsonb_agg(to_jsonb(x) order by lower(x.name)) from public.suppliers x),'[]'::jsonb);
    when 'equipment' then return coalesce((select jsonb_agg(to_jsonb(q) order by q."Submitted at" desc) from
      (select incident_date as "Incident date",item_name as "Item",quantity as "Quantity",section as "Section",staff_name as "Reported by",details as "Reason / details",status as "Status",admin_note as "Resolution / admin note",created_at as "Submitted at",updated_at as "Updated at"
       from goya_private.equipment_reports where p_month is null or (incident_date>=sd and incident_date<ed))q),'[]'::jsonb);
    else raise exception 'Invalid dataset';
  end case;
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
    'off_balances',public.goya_management_balances(p_token),'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'employee_code',hp.employee_code,'sections',s.sections,'roster_group',hp.roster_group,'eligible_days',(select jsonb_agg(goya_private.employed_on(s.id,p_week+i) order by i) from generate_series(0,6) i),'joining_date',hp.joining_date,'last_day',coalesce(hp.last_day,(select r.last_working_day from goya_private.staff_resignations r where r.staff_id=s.id and r.cancelled_at is null))) order by s.name,s.id)
      from public.staff s left join goya_private.staff_hr_profiles hp on hp.staff_id=s.id where (hp.joining_date is null or hp.joining_date<=p_week+6) and s.active and not exists(select 1 from goya_private.staff_resignations x where x.staff_id=s.id and x.cancelled_at is null and x.last_working_day<p_week)),'[]'::jsonb),
    'approved_leave',public.goya_hr_week_leave(p_token,p_week),
    'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.revision desc) from
      (select revision,published_at from goya_private.roster_publications where week_start=p_week order by revision desc limit 30) h),'[]'::jsonb)
  );
end $function$
;
-- Additive read-only endpoints. No existing request, document or roster records are modified.
create or replace function public.goya_portal_staff_alerts(p_token text)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare employee uuid; today date:=(now() at time zone 'Asia/Dubai')::date;
begin
 employee:=(public.require_session(p_token,false)).staff_id;
 if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized'; end if;
 return jsonb_build_object('staff_id',employee,'today',today,
  'requests',coalesce((select jsonb_agg(to_jsonb(q) order by q.updated_at desc) from
   (select id,kind,state,requested_from,requested_to,approved_from,approved_to,review_note,updated_at
    from goya_private.staff_leave_requests where staff_id=employee and state in ('Approved','Declined') order by updated_at desc limit 100)q),'[]'::jsonb),
  'documents',coalesce((select jsonb_agg(to_jsonb(q) order by q.expires_on) from
   (select id,category,custom_title,expires_on,expires_on-today as days_left from
    (select d.*,row_number() over(partition by category order by uploaded_at desc,id desc) rn
     from goya_private.staff_document_versions d where staff_id=employee and uploaded_at is not null)d
    where rn=1 and expires_on<=today+30)q),'[]'::jsonb));
end $fn$;
revoke all on function public.goya_portal_staff_alerts(text) from public;
grant execute on function public.goya_portal_staff_alerts(text) to anon,authenticated;

create or replace function public.goya_portal_admin_summary(p_token text)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare today date:=(now() at time zone 'Asia/Dubai')::date;
begin
 perform public.require_session(p_token,true);
 return jsonb_build_object(
  'pending_requests',(select count(*) from goya_private.staff_leave_requests where state='Pending'),
  'unresolved_equipment',(select count(*) from goya_private.equipment_reports where status in ('Pending','Reviewed')),
  'equipment',coalesce((select jsonb_agg(jsonb_build_object('item_name',item_name,'status',status,'staff_name',staff_name,'incident_date',incident_date) order by created_at desc) from goya_private.equipment_reports where status in ('Pending','Reviewed')),'[]'::jsonb),
  'documents',coalesce((select jsonb_agg(to_jsonb(q) order by q.expires_on,q.name) from
   (select d.staff_id,s.name,d.category,d.custom_title,d.expires_on,d.expires_on-today as days_left from
    (select staff_id,category,custom_title,expires_on,row_number() over(partition by staff_id,category order by uploaded_at desc,id desc) rn
     from goya_private.staff_document_versions where uploaded_at is not null)d
    join public.staff s on s.id=d.staff_id and s.active where rn=1 and expires_on<=today+30)q),'[]'::jsonb));
end $fn$;
revoke all on function public.goya_portal_admin_summary(text) from public;
grant execute on function public.goya_portal_admin_summary(text) to anon,authenticated;

create or replace function public.goya_portal_export_summary(p_token text,p_dataset text,p_month date default null)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare total bigint; sd date:=date_trunc('month',p_month)::date; ed date:=(sd+interval '1 month')::date;
begin
 perform public.require_session(p_token,true);
 case p_dataset
 when 'orders' then select count(*) into total from public.orders o join public.order_groups g on g.id=o.order_group_id where p_month is null or (o.created_at>=sd and o.created_at<ed);
 when 'production' then select count(*) into total from public.production_batches where p_month is null or (created_at>=sd and created_at<ed);
 when 'wastage' then select count(*) into total from public.wastage_entries where p_month is null or (created_at>=sd and created_at<ed);
 when 'inventory' then select count(*) into total from public.inventory_counts where p_month is null or (created_at>=sd and created_at<ed);
 when 'complaints' then select count(*) into total from public.complaint_feedback where p_month is null or (created_at>=sd and created_at<ed);
 when 'equipment' then select count(*) into total from goya_private.equipment_reports where p_month is null or (incident_date>=sd and incident_date<ed);
 when 'master_items' then select count(*) into total from public.master_items;
 when 'internal_items' then select count(*) into total from public.internal_items;
 when 'staff' then select count(*) into total from public.staff;
 when 'suppliers' then select count(*) into total from public.suppliers;
 else raise exception 'Invalid dataset'; end case;
 return jsonb_build_object('count',total,'month',case when p_dataset in ('master_items','internal_items','staff','suppliers') then null else sd end);
end $fn$;
revoke all on function public.goya_portal_export_summary(text,text,date) from public;
grant execute on function public.goya_portal_export_summary(text,text,date) to anon,authenticated;

create or replace function public.goya_portal_duplicate_check(p_token text,p_kind text,p_items jsonb)
returns boolean language plpgsql stable security definer set search_path='' as $fn$
declare a public.app_sessions;s public.staff; cutoff timestamptz:=now()-interval '10 minutes';
begin
 a:=public.require_session(p_token,false);select * into s from public.staff where id=a.staff_id and active;
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
end $fn$;
revoke all on function public.goya_portal_duplicate_check(text,text,jsonb) from public;
grant execute on function public.goya_portal_duplicate_check(text,text,jsonb) to anon,authenticated;
