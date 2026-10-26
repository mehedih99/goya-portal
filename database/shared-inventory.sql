-- Additive shared inventory. Existing sessions remain personal; only new sessions default to shared.
alter table public.inventory_sessions add column shared_count boolean not null default false;
alter table public.inventory_sessions alter column shared_count set default true;
alter table public.inventory_sessions add column counting_date date;
create table goya_private.inventory_shared_sheets(
 id uuid primary key default gen_random_uuid(),session_id uuid not null references public.inventory_sessions(id) on delete restrict,
 section text not null,sheet_name text not null,counting_date date not null,version bigint not null default 0,generation bigint not null default 1,
 submitted_at timestamptz,submitted_by uuid references public.staff(id) on delete set null,submitted_name text,
 initialized boolean not null default false,created_at timestamptz not null default now(),unique(session_id,section));
create table goya_private.inventory_shared_lines(
 sheet_id uuid not null references goya_private.inventory_shared_sheets(id) on delete restrict,sku text not null,item_name text not null,source text not null,
 storage_unit text not null,ingredient_unit text not null,storage_quantity numeric,ingredients_quantity numeric,version bigint not null default 0,
 updated_by uuid references public.staff(id) on delete set null,updated_name text,updated_at timestamptz,primary key(sheet_id,sku),
 check(storage_quantity is null or (storage_quantity>=0 and storage_quantity<=1000000000000 and storage_quantity=round(storage_quantity,3))),
 check(ingredients_quantity is null or (ingredients_quantity>=0 and ingredients_quantity<=1000000000000 and ingredients_quantity=round(ingredients_quantity,3))));
create table goya_private.inventory_shared_audit(
 id bigint generated always as identity primary key,sheet_id uuid not null references goya_private.inventory_shared_sheets(id) on delete restrict,
 sku text,event text not null,actor_id uuid references public.staff(id) on delete set null,actor_name text not null,old_values jsonb,new_values jsonb,created_at timestamptz not null default now());
create index inventory_shared_audit_sheet on goya_private.inventory_shared_audit(sheet_id,id desc);
create table goya_private.inventory_shared_finals(
 id uuid primary key default gen_random_uuid(),sheet_id uuid not null references goya_private.inventory_shared_sheets(id) on delete restrict,
 generation bigint not null,version bigint not null,submitted_by uuid references public.staff(id) on delete set null,submitted_name text not null,
 items jsonb not null,submitted_at timestamptz not null default now(),unique(sheet_id,generation));
alter table goya_private.inventory_shared_sheets enable row level security;
alter table goya_private.inventory_shared_lines enable row level security;
alter table goya_private.inventory_shared_audit enable row level security;
alter table goya_private.inventory_shared_finals enable row level security;
revoke all on goya_private.inventory_shared_sheets,goya_private.inventory_shared_lines,goya_private.inventory_shared_audit,goya_private.inventory_shared_finals from public,anon,authenticated;
alter table public.inventory_counts add column shared_sheet_id uuid references goya_private.inventory_shared_sheets(id) on delete restrict;
alter table public.inventory_counts add column sheet_name text;
alter table public.inventory_counts add column counting_date date;
create unique index inventory_counts_shared_item on public.inventory_counts(shared_sheet_id,sku) where shared_sheet_id is not null;

-- Authorization always uses the portal's existing custom PIN session, never Supabase Auth uid.
create function goya_private.inventory_shared_open(p_token text,p_session_id uuid,p_section text)
returns goya_private.inventory_shared_sheets language plpgsql security definer set search_path='' as $$
declare a public.app_sessions;s public.staff;v public.inventory_sessions;h goya_private.inventory_shared_sheets;
begin
 a:=public.require_session(p_token,false);
 select * into s from public.staff where id=a.staff_id and active for share;
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
end $$;
revoke all on function goya_private.inventory_shared_open(text,uuid,text) from public,anon,authenticated;
create function goya_private.inventory_shared_payload(p_sheet uuid) returns jsonb language sql security definer set search_path='' as $$
 select to_jsonb(h)||jsonb_build_object('shared',true,'done',h.submitted_at is not null,
 'items',coalesce((select jsonb_agg(jsonb_build_object('name',l.item_name,'sku',l.sku,'source',l.source,'storage_unit',l.storage_unit,'ingredient_unit',l.ingredient_unit,'storage_quantity',l.storage_quantity,'ingredients_quantity',l.ingredients_quantity,'version',l.version,'updated_name',l.updated_name,'updated_at',l.updated_at) order by lower(l.item_name),l.sku) from goya_private.inventory_shared_lines l where sheet_id=h.id),'[]'::jsonb)) from goya_private.inventory_shared_sheets h where id=p_sheet;
$$;
revoke all on function goya_private.inventory_shared_payload(uuid) from public,anon,authenticated;
create function public.goya_inventory_shared_work(p_token text,p_session_id uuid,p_section text) returns jsonb language plpgsql security definer set search_path='' as $$
declare h goya_private.inventory_shared_sheets;begin h:=goya_private.inventory_shared_open(p_token,p_session_id,p_section);return goya_private.inventory_shared_payload(h.id)||jsonb_build_object('viewer_id',(public.require_session(p_token,false)).staff_id);end $$;
create function public.goya_inventory_shared_save(p_token text,p_session_id uuid,p_section text,p_generation bigint,p_changes jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare h goya_private.inventory_shared_sheets;a public.app_sessions;s public.staff;x jsonb;l goya_private.inventory_shared_lines;sv numeric;iv numeric;conflicts jsonb:='[]';
begin
 h:=goya_private.inventory_shared_open(p_token,p_session_id,p_section);a:=public.require_session(p_token,false);select * into s from public.staff where id=a.staff_id;
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
end $$;
create function public.goya_inventory_shared_submit(p_token text,p_session_id uuid,p_section text,p_generation bigint,p_version bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare h goya_private.inventory_shared_sheets;a public.app_sessions;s public.staff;
begin
 h:=goya_private.inventory_shared_open(p_token,p_session_id,p_section);a:=public.require_session(p_token,false);select * into s from public.staff where id=a.staff_id;
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
end $$;
create function public.goya_admin_inventory_reopen(p_token text,p_session_id uuid,p_section text) returns jsonb language plpgsql security definer set search_path='' as $$
declare h goya_private.inventory_shared_sheets;begin
 perform public.require_session(p_token,true);select * into h from goya_private.inventory_shared_sheets where session_id=p_session_id and section=p_section for update;
 if h.id is null then raise exception 'Shared sheet has not been started';end if;
 if h.submitted_at is null then raise exception 'This sheet is already open';end if;
 update goya_private.inventory_shared_sheets set submitted_at=null,submitted_by=null,submitted_name=null,generation=generation+1,version=version+1 where id=h.id;
 insert into goya_private.inventory_shared_audit(sheet_id,event,actor_name,old_values) values(h.id,'reopen','Admin',jsonb_build_object('generation',h.generation,'submitted_at',h.submitted_at));
 return jsonb_build_object('ok',true);
end $$;
create function public.goya_inventory_shared_history(p_token text,p_session_id uuid,p_section text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.app_sessions;h goya_private.inventory_shared_sheets;begin
 begin a:=public.require_session(p_token,true);select * into h from goya_private.inventory_shared_sheets where session_id=p_session_id and section=p_section;
 exception when others then h:=goya_private.inventory_shared_open(p_token,p_session_id,p_section);end;
 return jsonb_build_object('events',coalesce((select jsonb_agg(to_jsonb(q)) from (select sku,event,actor_name,old_values,new_values,created_at from goya_private.inventory_shared_audit where sheet_id=h.id order by id desc limit 100)q),'[]'::jsonb),
 'submissions',coalesce((select jsonb_agg(to_jsonb(q)) from (select generation,submitted_name,submitted_at,items from goya_private.inventory_shared_finals where sheet_id=h.id order by generation desc)q),'[]'::jsonb));
end $$;
do $$ declare f text;begin
 foreach f in array array['goya_inventory_shared_work(text,uuid,text)','goya_inventory_shared_save(text,uuid,text,bigint,jsonb)','goya_inventory_shared_submit(text,uuid,text,bigint,bigint)','goya_admin_inventory_reopen(text,uuid,text)','goya_inventory_shared_history(text,uuid,text)'] loop
 execute 'revoke all on function public.'||f||' from public';execute 'grant execute on function public.'||f||' to anon,authenticated';end loop;
end $$;

create or replace function public.admin_inventory_save_session(p_token text,p_row jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare x public.inventory_sessions;nid uuid:=nullif(p_row->>'id','')::uuid;begin
 perform public.require_session(p_token,true);
 if nid is null then
  insert into public.inventory_sessions(month,title,notice_text,active,sections,assigned_staff_ids,shared_count,counting_date) values((p_row->>'month')::date,nullif(p_row->>'title',''),nullif(p_row->>'notice_text',''),coalesce((p_row->>'active')::boolean,false),array(select jsonb_array_elements_text(coalesce(p_row->'sections','[]'))),array(select jsonb_array_elements_text(coalesce(p_row->'assigned_staff_ids','[]'))::uuid),true,coalesce(nullif(p_row->>'counting_date','')::date,timezone('Asia/Dubai',now())::date)) returning * into x;
 else
  select * into x from public.inventory_sessions where id=nid for update;if not found then raise exception 'Session not found';end if;
  if exists(select 1 from goya_private.inventory_shared_sheets where session_id=nid) and (coalesce(nullif(p_row->>'counting_date','')::date,x.counting_date) is distinct from x.counting_date or (p_row->>'month')::date is distinct from x.month) then raise exception 'Counting date/month is fixed after a shared sheet starts. Create a new session for a new count.';end if;
  update public.inventory_sessions set month=(p_row->>'month')::date,title=nullif(p_row->>'title',''),notice_text=nullif(p_row->>'notice_text',''),active=coalesce((p_row->>'active')::boolean,active),sections=array(select jsonb_array_elements_text(coalesce(p_row->'sections','[]'))),assigned_staff_ids=array(select jsonb_array_elements_text(coalesce(p_row->'assigned_staff_ids','[]'))::uuid),counting_date=coalesce(nullif(p_row->>'counting_date','')::date,counting_date),updated_at=now() where id=nid returning * into x;
 end if;return to_jsonb(x);
end $$;
-- Preserve original legacy bodies and stop stale clients from submitting personal copies of shared sheets.
do $$ declare def text;fname text;begin
 def:=pg_get_functiondef('public.inventory_work(text,uuid,text)'::regprocedure);
 if position('  sess:=public.require_session' in def)=0 then raise exception 'Legacy inventory API changed';end if;
 def:=replace(def,'  sess:=public.require_session',$guard$  if exists(select 1 from public.inventory_sessions where id=p_session_id and shared_count) then return public.goya_inventory_shared_work(p_token,p_session_id,p_section);end if;
  sess:=public.require_session$guard$);execute def;
 foreach fname in array array['inventory_save_draft(text,uuid,text,jsonb)','inventory_submit_final(text,uuid,text,jsonb)'] loop
 def:=pg_get_functiondef(('public.'||fname)::regprocedure);
 if position('  sess:=public.require_session' in def)=0 then raise exception 'Legacy write API changed';end if;
 def:=replace(def,'  sess:=public.require_session',$guard$  if exists(select 1 from public.inventory_sessions where id=p_session_id and shared_count) then raise exception 'Shared count: refresh your Staff Portal to save or submit safely';end if;
  sess:=public.require_session$guard$);execute def;
 end loop;
 def:=pg_get_functiondef('public.admin_inventory_reset_count(text,uuid,uuid,text)'::regprocedure);
 def:=replace(def,'  perform public.require_session(p_token,true);',$guard$  perform public.require_session(p_token,true);
  if exists(select 1 from public.inventory_sessions where id=p_session_id and shared_count) then return public.goya_admin_inventory_reopen(p_token,p_session_id,p_section);end if;$guard$);execute def;
end $$;
-- Shared report rows are an atomic sheet. Reopen for corrections, rather than deleting fragments.
create function goya_private.protect_shared_count_delete() returns trigger language plpgsql set search_path='' as $$begin if old.shared_sheet_id is not null then raise exception 'Shared sheet counts cannot be partially deleted. Reopen the shared sheet for corrections; previous finals are retained.';end if;return old;end $$;
revoke all on function goya_private.protect_shared_count_delete() from public,anon,authenticated;
create trigger protect_shared_inventory_count before delete on public.inventory_counts for each row execute function goya_private.protect_shared_count_delete();
