CREATE OR REPLACE FUNCTION public.admin_delete_inventory_session(p_token text, p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin perform public.require_session(p_token,true); delete from public.inventory_sessions where id=p_id; return true; end; $function$;

CREATE OR REPLACE FUNCTION public.admin_inventory_counts(p_token text, p_month date DEFAULT CURRENT_DATE, p_section text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform public.require_session(p_token,true);return coalesce((select jsonb_agg(to_jsonb(q) order by q.counted_at desc) from (select c.*,s.month,s.title from public.inventory_counts c join public.inventory_sessions s on s.id=c.session_id where date_trunc('month',s.month)=date_trunc('month',p_month) and (p_section is null or p_section='' or lower(c.section)=lower(p_section)))q),'[]'::jsonb);end $function$;

CREATE OR REPLACE FUNCTION public.admin_inventory_reset_count(p_token text, p_session_id uuid, p_staff_id uuid, p_section text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  deleted_counts integer:=0;
  deleted_drafts integer:=0;
  deleted_submissions integer:=0;
begin
  perform public.require_session(p_token,true);

  if not exists(select 1 from public.inventory_sessions where id=p_session_id) then
    raise exception 'Inventory session not found';
  end if;
  if not exists(select 1 from public.staff where id=p_staff_id) then
    raise exception 'Staff not found';
  end if;
  if coalesce(trim(p_section),'')='' then
    raise exception 'Section is required';
  end if;

  delete from public.inventory_counts
  where session_id=p_session_id
    and staff_id=p_staff_id
    and lower(section)=lower(trim(p_section));
  get diagnostics deleted_counts=row_count;

  delete from public.inventory_drafts
  where session_id=p_session_id
    and staff_id=p_staff_id
    and lower(section)=lower(trim(p_section));
  get diagnostics deleted_drafts=row_count;

  delete from public.inventory_submissions
  where session_id=p_session_id
    and staff_id=p_staff_id
    and lower(section)=lower(trim(p_section));
  get diagnostics deleted_submissions=row_count;

  return jsonb_build_object(
    'ok',true,
    'deleted_counts',deleted_counts,
    'deleted_drafts',deleted_drafts,
    'deleted_submissions',deleted_submissions
  );
end $function$;

CREATE OR REPLACE FUNCTION public.admin_inventory_save_session(p_token text, p_row jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare x public.inventory_sessions;
begin perform public.require_session(p_token,true);if nullif(p_row->>'id','') is null then insert into public.inventory_sessions(month,title,notice_text,active,sections,assigned_staff_ids) values((p_row->>'month')::date,nullif(p_row->>'title',''),nullif(p_row->>'notice_text',''),coalesce((p_row->>'active')::boolean,false),coalesce(array(select jsonb_array_elements_text(coalesce(p_row->'sections','[]'::jsonb))),'{}'),coalesce(array(select (jsonb_array_elements_text(coalesce(p_row->'assigned_staff_ids','[]'::jsonb)))::uuid),'{}')) returning * into x;else update public.inventory_sessions set month=(p_row->>'month')::date,title=nullif(p_row->>'title',''),notice_text=nullif(p_row->>'notice_text',''),active=coalesce((p_row->>'active')::boolean,active),sections=coalesce(array(select jsonb_array_elements_text(coalesce(p_row->'sections','[]'::jsonb))),sections),assigned_staff_ids=coalesce(array(select (jsonb_array_elements_text(coalesce(p_row->'assigned_staff_ids','[]'::jsonb)))::uuid),assigned_staff_ids),updated_at=now() where id=(p_row->>'id')::uuid returning * into x;end if;return to_jsonb(x);end $function$;

CREATE OR REPLACE FUNCTION public.inventory_save_draft(p_token text, p_session_id uuid, p_section text, p_items jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions;s public.staff;
begin
  sess:=public.require_session(p_token,false);select * into s from public.staff where id=sess.staff_id;
  perform public.inventory_work(p_token,p_session_id,p_section);
  if exists(select 1 from public.inventory_submissions where session_id=p_session_id and staff_id=s.id and section=p_section) then raise exception 'This section is already submitted'; end if;
  insert into public.inventory_drafts(session_id,staff_id,section,items,updated_at) values(p_session_id,s.id,p_section,coalesce(p_items,'[]'::jsonb),now()) on conflict(session_id,staff_id,section) do update set items=excluded.items,updated_at=now();
  return true;
end $function$;

CREATE OR REPLACE FUNCTION public.inventory_submit_final(p_token text, p_session_id uuid, p_section text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions;s public.staff;it jsonb;expected int;provided int;n int:=0;
begin
  sess:=public.require_session(p_token,false);select * into s from public.staff where id=sess.staff_id;
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
end $function$;

CREATE OR REPLACE FUNCTION public.inventory_work(p_token text, p_session_id uuid, p_section text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions;s public.staff;subtime timestamptz;draft_items jsonb;allowed boolean;
begin
  sess:=public.require_session(p_token,false);select * into s from public.staff where id=sess.staff_id;
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
end $function$;

CREATE OR REPLACE FUNCTION public.require_session(p_token text, p_admin boolean DEFAULT false)
 RETURNS app_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.app_sessions;
begin
  select * into s from public.app_sessions
  where token = p_token and expires_at > now() and is_admin = p_admin;
  if s.token is null then raise exception 'Session expired or unauthorized'; end if;
  return s;
end;
$function$;

CREATE OR REPLACE FUNCTION public.staff_bootstrap(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions;s public.staff;
begin
  sess:=public.require_session(p_token,false);select * into s from public.staff where id=sess.staff_id;
  return jsonb_build_object(
    'master_items',(select coalesce(jsonb_agg(to_jsonb(x) order by lower(x.name)),'[]'::jsonb) from public.master_items x where x.active=true),
    'internal_items',(select coalesce(jsonb_agg(to_jsonb(x) order by lower(x.name)),'[]'::jsonb) from public.internal_items x where x.active=true),
    'suppliers',(select coalesce(jsonb_agg(to_jsonb(x) order by lower(x.name)),'[]'::jsonb) from public.suppliers x where x.active=true),
    'info_pages',(select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.title),'[]'::jsonb) from public.info_pages x where x.active=true),
    'inventory_sessions',(select coalesce(jsonb_agg(to_jsonb(v) order by v.month desc),'[]'::jsonb) from public.inventory_sessions v where v.active=true and s.sections && v.sections and (s.id=any(v.assigned_staff_ids) or (coalesce(array_length(v.assigned_staff_ids,1),0)=0 and s.can_inventory)))
  );
end $function$;
