begin;
set local lock_timeout = '5s';

alter table goya_private.staff_document_versions add column custom_title text;
alter table goya_private.staff_document_versions
  drop constraint staff_document_versions_category_check,
  add constraint staff_document_versions_category_check check (
    (category in ('emirates-id','contract','food-safety','health-card','work-permit','residence-visa','health-insurance','pic-certificate')
      and custom_title is null)
    or (category ~ '^custom-[a-f0-9-]{36}$' and custom_title is not null and length(btrim(custom_title)) between 1 and 100)
  );

create function public.goya_hr_document_reserve_v2(p_token text,p_id uuid,p_category text,p_name text,
  p_type text,p_size integer,p_sha text,p_staff uuid,p_title text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare employee uuid := goya_private.document_staff(p_token,p_staff);
  folder text;
  version goya_private.staff_document_versions;
begin
  if p_category like 'custom-%' and p_staff is null then raise exception 'Unauthorized'; end if;
  select employee_code into folder from goya_private.staff_hr_profiles where staff_id=employee;
  if folder is null or folder !~ '^GY-[0-9]{3,}$' then
    folder := left(coalesce(nullif(regexp_replace(folder,'[^A-Za-z0-9_-]','-','g'),''),'Staff'),80)
      ||'--'||employee::text;
  end if;
  insert into goya_private.staff_document_versions(id,staff_id,category,file_name,mime_type,byte_size,sha256,folder_key,custom_title)
    values(p_id,employee,p_category,p_name,p_type,p_size,p_sha,folder,p_title)
    on conflict(id) do nothing;
  select * into version from goya_private.staff_document_versions where id=p_id and staff_id=employee;
  if not found or (version.category,version.file_name,version.mime_type,version.byte_size,version.sha256,version.custom_title)
    is distinct from (p_category,p_name,p_type,p_size,p_sha,p_title) then
    raise exception 'Upload ID already used';
  end if;
  return jsonb_build_object('folder',version.folder_key,'complete',version.uploaded_at is not null);
end $$;

create function public.goya_hr_document_complete_v2(p_token text,p_id uuid,p_drive text,p_staff uuid)
returns void language plpgsql security definer set search_path='' as $$
declare employee uuid := goya_private.document_staff(p_token,p_staff);
begin
  perform 1 from public.staff where id=employee and (active or p_staff is not null) for update;
  if not found then raise exception 'Unauthorized'; end if;
  update goya_private.staff_document_versions
    set drive_file_id=p_drive,uploaded_at=coalesce(uploaded_at,clock_timestamp())
    where id=p_id and staff_id=employee and (drive_file_id is null or drive_file_id=p_drive)
      and p_drive is not null;
  if not found then raise exception 'Upload is unavailable'; end if;
end $$;

create or replace function public.goya_hr_documents(p_token text,p_staff uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare employee uuid := goya_private.document_staff(p_token,p_staff);
begin
  return (with versions as (
    select d.id,d.category,d.file_name,d.mime_type,d.byte_size,d.uploaded_at,d.custom_title,
      row_number() over (partition by d.category order by d.uploaded_at desc,d.id desc) as version_rank
    from goya_private.staff_document_versions d where d.staff_id=employee and d.uploaded_at is not null)
  select coalesce(jsonb_agg(to_jsonb(v) order by v.category,v.version_rank),'[]'::jsonb)
  from versions v where p_staff is not null or v.version_rank=1);
end
$$;


revoke all on function public.goya_hr_document_reserve_v2(text,uuid,text,text,text,integer,text,uuid,text),
  public.goya_hr_document_complete_v2(text,uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.goya_hr_document_reserve_v2(text,uuid,text,text,text,integer,text,uuid,text),
  public.goya_hr_document_complete_v2(text,uuid,text,uuid) to service_role;

create table goya_private.staff_annual_history (
  id uuid primary key,
  staff_id uuid not null references public.staff(id) on delete restrict,
  source_id uuid unique references goya_private.staff_leave_requests(id) on delete restrict,
  service_year date not null,
  leave_from date,
  leave_to date,
  note text not null default '' check (length(note)<=2000),
  updated_at timestamptz not null default clock_timestamp(),
  check ((leave_from is null and leave_to is null) or
         (leave_from is not null and leave_to is not null and leave_to >= leave_from))
);
create index staff_annual_history_staff on goya_private.staff_annual_history(staff_id,service_year desc);
alter table goya_private.staff_annual_history enable row level security;
revoke all on goya_private.staff_annual_history from public,anon,authenticated;

create function public.goya_hr_annual_history(p_token text,p_staff uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare employee uuid := goya_private.document_staff(p_token,p_staff);
begin
  return (select coalesce(jsonb_agg(to_jsonb(h)-'staff_id' order by h.service_year desc,h.leave_from desc nulls last,h.id),'[]')
    from goya_private.staff_annual_history h where h.staff_id=employee);
end $$;

create function public.goya_hr_admin_annual_sources(p_token text,p_staff uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  perform public.require_session(p_token,true);
  return (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'leave_from',r.approved_from,
    'leave_to',r.approved_to,'note',r.review_note) order by r.approved_from desc),'[]')
    from goya_private.staff_leave_requests r
    where r.staff_id=p_staff and r.kind='Annual Leave' and r.state='Approved'
      and r.approved_to < (now() at time zone 'Asia/Dubai')::date
      and not exists (select 1 from goya_private.staff_annual_history h where h.source_id=r.id));
end $$;

create function public.goya_hr_save_annual_history(p_token text,p_staff uuid,p_id uuid,p_expected timestamptz,
  p_source uuid,p_year date,p_from date,p_to date,p_note text)
returns uuid language plpgsql security definer set search_path='' as $$
declare joined date;
  today date := (now() at time zone 'Asia/Dubai')::date;
  result uuid;
begin
  perform public.require_session(p_token,true);
  perform 1 from public.staff where id=p_staff for update;
  if not found then raise exception 'Staff record unavailable.'; end if;
  select joining_date into joined from goya_private.staff_hr_profiles where staff_id=p_staff;
  if joined is null then raise exception 'Add a joining date in Staff Management first.'; end if;
  if p_year is null or p_year < joined or p_year > today or
     p_year <> (joined + make_interval(years=>extract(year from p_year)::int-extract(year from joined)::int))::date
  then raise exception 'Choose a valid service year.'; end if;
  if (p_from is null) <> (p_to is null) or p_to < p_from or p_from < joined or p_to >= today
     or (p_from is null and (joined + make_interval(years=>extract(year from p_year)::int-extract(year from joined)::int+1))::date > today)
  then raise exception 'Enter both past leave dates, or leave dates blank for an earlier service year.'; end if;
  if p_source is not null and not exists (select 1 from goya_private.staff_leave_requests r
    where r.id=p_source and r.staff_id=p_staff and r.kind='Annual Leave' and r.state='Approved' and r.approved_to < today)
  then raise exception 'This annual leave record is unavailable.'; end if;
  if p_expected is null then
    insert into goya_private.staff_annual_history(id,staff_id,source_id,service_year,leave_from,leave_to,note)
      values(p_id,p_staff,p_source,p_year,p_from,p_to,coalesce(p_note,''))
      on conflict do nothing returning id into result;
    if result is null then
      select id into result from goya_private.staff_annual_history h where h.id=p_id and h.staff_id=p_staff
      and (h.source_id,h.service_year,h.leave_from,h.leave_to,h.note)
        is not distinct from (p_source,p_year,p_from,p_to,coalesce(p_note,''));
    end if;
  else
    update goya_private.staff_annual_history h set service_year=p_year,leave_from=p_from,leave_to=p_to,
      note=coalesce(p_note,''),updated_at=clock_timestamp() where h.id=p_id and h.staff_id=p_staff
      and h.updated_at=p_expected returning id into result;
  end if;
  if result is null then raise exception 'The record changed. Reopen the staff card and try again.'; end if;
  return result;
end $$;

revoke all on function public.goya_hr_annual_history(text,uuid),public.goya_hr_admin_annual_sources(text,uuid),
  public.goya_hr_save_annual_history(text,uuid,uuid,timestamptz,uuid,date,date,date,text) from public,anon,authenticated;
grant execute on function public.goya_hr_annual_history(text,uuid),public.goya_hr_admin_annual_sources(text,uuid),
  public.goya_hr_save_annual_history(text,uuid,uuid,timestamptz,uuid,date,date,date,text) to anon,authenticated;
commit;
