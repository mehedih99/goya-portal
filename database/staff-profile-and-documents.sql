begin;

create sequence goya_private.staff_employee_number;
create unique index staff_hr_employee_code_unique
  on goya_private.staff_hr_profiles (employee_code) where btrim(employee_code) <> '';

create function goya_private.assign_staff_employee_code()
returns trigger language plpgsql security definer set search_path='' as $$
declare employee_number text;
begin
  new.branch := 'GOYA';
  if tg_op = 'UPDATE' and btrim(old.employee_code) <> '' then
    new.employee_code := old.employee_code;
  end if;
  if btrim(new.employee_code) = '' then
    loop
      employee_number := nextval('goya_private.staff_employee_number')::text;
      new.employee_code := 'GY-' || lpad(employee_number, greatest(3, length(employee_number)), '0');
      exit when not exists (select 1 from goya_private.staff_hr_profiles where employee_code=new.employee_code);
    end loop;
  end if;
  return new;
end $$;
revoke all on function goya_private.assign_staff_employee_code() from public,anon,authenticated;
create trigger assign_staff_employee_code before insert or update on goya_private.staff_hr_profiles
for each row execute function goya_private.assign_staff_employee_code();

update goya_private.staff_hr_profiles set branch='GOYA'
  where branch <> 'GOYA' or btrim(employee_code)='';
insert into goya_private.staff_hr_profiles(staff_id)
select s.id from public.staff s
where not exists (select 1 from goya_private.staff_hr_profiles p where p.staff_id=s.id)
order by s.name,s.id;

create function goya_private.allow_unused_staff_deletion()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if exists (select 1 from goya_private.staff_hr_audit where staff_id=old.id)
     or exists (select 1 from goya_private.staff_hr_profiles where staff_id=old.id
       and (joining_date is not null or last_day is not null or position<>'' or manager_notes<>'')) then
    raise exception 'This staff member has employment history. Use Inactive or record their last working day.';
  end if;
  delete from goya_private.staff_hr_profiles where staff_id=old.id;
  return old;
end $$;
revoke all on function goya_private.allow_unused_staff_deletion() from public,anon,authenticated;
create trigger allow_unused_staff_deletion before delete on public.staff
for each row execute function goya_private.allow_unused_staff_deletion();

create function public.goya_hr_admin_profile(p_token text,p_staff uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  perform public.require_session(p_token,true);
  return (select to_jsonb(p) from goya_private.staff_hr_profiles p where p.staff_id=p_staff);
end $$;

create function public.goya_hr_save_staff(p_token text,p_row jsonb,p_profile jsonb,p_expected timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare employee uuid := nullif(p_row->>'id','')::uuid;
  previous goya_private.staff_hr_profiles;
  cessation date := nullif(p_profile->>'last_day','')::date;
  saved jsonb;
begin
  perform public.require_session(p_token,true);
  if employee is not null then
    perform 1 from public.staff where id=employee for update;
    if not found then raise exception 'Staff member was not found'; end if;
    select * into previous from goya_private.staff_hr_profiles where staff_id=employee;
    if previous.updated_at is distinct from p_expected then
      raise exception 'The employment profile changed. Open it again before saving.';
    end if;
  end if;
  if cessation is not null then
    p_row := p_row || jsonb_build_object('active',false);
  end if;
  saved := public.admin_save_staff(p_token,p_row);
  if employee is null and cessation is null and coalesce(nullif(p_profile->>'joining_date',''),
    nullif(p_profile->>'position',''),nullif(p_profile->>'manager_notes','')) is null then
    insert into goya_private.staff_hr_profiles(staff_id) values((saved->>'id')::uuid);
    return;
  end if;
  perform public.goya_hr_save_profile(p_token,(saved->>'id')::uuid,
    p_profile || jsonb_build_object('employee_code',coalesce(previous.employee_code,''),'branch','GOYA'));
end $$;

alter table goya_private.staff_leave_requests
  drop constraint staff_leave_requests_state_check,
  add constraint staff_leave_requests_state_check check (state in ('Pending','Approved','Declined','Withdrawn'));

create function goya_private.protect_withdrawn_leave()
returns trigger language plpgsql set search_path='' as $$
begin
  if old.state='Withdrawn' and new.state<>'Withdrawn' then
    raise exception 'This request was withdrawn';
  end if;
  return new;
end $$;
revoke all on function goya_private.protect_withdrawn_leave() from public,anon,authenticated;
create trigger protect_withdrawn_leave before update of state on goya_private.staff_leave_requests
for each row execute function goya_private.protect_withdrawn_leave();

create function public.goya_hr_withdraw_request(p_token text,p_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare employee uuid := (public.require_session(p_token,false)).staff_id;
begin
  perform 1 from public.staff where id=employee and active for update;
  if not found then raise exception 'Unauthorized'; end if;
  update goya_private.staff_leave_requests set state='Withdrawn',updated_at=clock_timestamp()
    where id=p_id and staff_id=employee and state='Pending';
  if not found then raise exception 'Only your pending requests can be withdrawn'; end if;
  insert into goya_private.staff_hr_audit(staff_id,event,details)
    values(employee,'Leave withdrawn',jsonb_build_object('request',p_id));
end $$;

create table goya_private.staff_document_versions (
  id uuid primary key,
  staff_id uuid not null references public.staff(id) on delete restrict,
  category text not null check (category in ('emirates-id','contract','food-safety','health-card')),
  file_name text not null check (length(file_name) between 1 and 180),
  mime_type text not null check (mime_type in ('application/pdf','image/jpeg','image/png')),
  byte_size integer not null check (byte_size between 1 and 5000000),
  sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  folder_key text not null,
  drive_file_id text unique check (drive_file_id ~ '^[A-Za-z0-9_-]{10,}$'),
  uploaded_at timestamptz,
  check ((drive_file_id is null) = (uploaded_at is null))
);
create index staff_document_history on goya_private.staff_document_versions(staff_id,category,uploaded_at desc,id desc)
  where uploaded_at is not null;
alter table goya_private.staff_document_versions enable row level security;
revoke all on goya_private.staff_document_versions from public,anon,authenticated;

create function goya_private.document_staff(p_token text,p_staff uuid)
returns uuid language plpgsql stable security definer set search_path='' as $$
declare employee uuid;
begin
  if p_staff is not null then
    perform public.require_session(p_token,true);
    return p_staff;
  end if;
  employee := (public.require_session(p_token,false)).staff_id;
  if not exists (select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized'; end if;
  return employee;
end $$;
revoke all on function goya_private.document_staff(text,uuid) from public,anon,authenticated;

create function public.goya_hr_documents(p_token text,p_staff uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare employee uuid := goya_private.document_staff(p_token,p_staff);
begin
  return (with versions as (
    select d.id,d.category,d.file_name,d.mime_type,d.byte_size,d.uploaded_at,
      row_number() over (partition by d.category order by d.uploaded_at desc,d.id desc) as version_rank
    from goya_private.staff_document_versions d where d.staff_id=employee and d.uploaded_at is not null)
  select coalesce(jsonb_agg(to_jsonb(v) order by v.category,v.version_rank),'[]'::jsonb)
  from versions v where p_staff is not null or v.version_rank=1);
end
$$;

create function public.goya_hr_document_reserve(p_token text,p_id uuid,p_category text,p_name text,
  p_type text,p_size integer,p_sha text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare employee uuid := goya_private.document_staff(p_token,null);
  folder text;
  version goya_private.staff_document_versions;
begin
  select employee_code into folder from goya_private.staff_hr_profiles where staff_id=employee;
  if folder is null or folder !~ '^GY-[0-9]{3,}$' then
    folder := left(coalesce(nullif(regexp_replace(folder,'[^A-Za-z0-9_-]','-','g'),''),'Staff'),80)
      ||'--'||employee::text;
  end if;
  insert into goya_private.staff_document_versions(id,staff_id,category,file_name,mime_type,byte_size,sha256,folder_key)
    values(p_id,employee,p_category,p_name,p_type,p_size,p_sha,folder)
    on conflict(id) do nothing;
  select * into version from goya_private.staff_document_versions where id=p_id and staff_id=employee;
  if not found or (version.category,version.file_name,version.mime_type,version.byte_size,version.sha256)
    is distinct from (p_category,p_name,p_type,p_size,p_sha) then
    raise exception 'Upload ID already used';
  end if;
  return jsonb_build_object('folder',version.folder_key,'complete',version.uploaded_at is not null);
end $$;

create function public.goya_hr_document_complete(p_token text,p_id uuid,p_drive text)
returns void language plpgsql security definer set search_path='' as $$
declare employee uuid := goya_private.document_staff(p_token,null);
begin
  perform 1 from public.staff where id=employee and active for update;
  if not found then raise exception 'Unauthorized'; end if;
  update goya_private.staff_document_versions
    set drive_file_id=p_drive,uploaded_at=coalesce(uploaded_at,clock_timestamp())
    where id=p_id and staff_id=employee and (drive_file_id is null or drive_file_id=p_drive)
      and p_drive is not null;
  if not found then raise exception 'Upload is unavailable'; end if;
end $$;

create function public.goya_hr_document_private_file(p_token text,p_id uuid,p_staff uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare employee uuid := goya_private.document_staff(p_token,p_staff);
begin
  return (select to_jsonb(d) from goya_private.staff_document_versions d
    where d.id=p_id and d.staff_id=employee and d.uploaded_at is not null
    and (p_staff is not null or not exists (
      select 1 from goya_private.staff_document_versions newer
      where newer.staff_id=employee and newer.category=d.category and newer.uploaded_at is not null
      and (newer.uploaded_at,newer.id)>(d.uploaded_at,d.id))));
end $$;

revoke all on function public.goya_hr_admin_profile(text,uuid),public.goya_hr_save_staff(text,jsonb,jsonb,timestamptz),
  public.goya_hr_withdraw_request(text,uuid),public.goya_hr_documents(text,uuid),
  public.goya_hr_document_reserve(text,uuid,text,text,text,integer,text),
  public.goya_hr_document_complete(text,uuid,text),
  public.goya_hr_document_private_file(text,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.goya_hr_admin_profile(text,uuid),public.goya_hr_save_staff(text,jsonb,jsonb,timestamptz),
  public.goya_hr_withdraw_request(text,uuid),public.goya_hr_documents(text,uuid) to anon,authenticated;
grant execute on function public.goya_hr_document_reserve(text,uuid,text,text,text,integer,text),
  public.goya_hr_document_complete(text,uuid,text),
  public.goya_hr_document_private_file(text,uuid,uuid) to service_role;

commit;
