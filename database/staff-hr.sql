begin;

create table goya_private.staff_hr_profiles (
  staff_id uuid primary key references public.staff(id) on delete restrict,
  joining_date date,
  employee_code text not null default '',
  position text not null default '',
  branch text not null default '',
  manager_notes text not null default '',
  last_day date,
  updated_at timestamptz not null default now(),
  check (last_day is null or joining_date is null or last_day >= joining_date)
);

create table goya_private.staff_leave_requests (
  id uuid primary key,
  staff_id uuid not null references public.staff(id) on delete restrict,
  kind text not null check (kind in ('Annual Leave','Sick Leave','Other Leave')),
  requested_from date not null,
  requested_to date not null,
  reason text not null check (length(reason) between 1 and 2000),
  drive_file_id text,
  state text not null default 'Pending' check (state in ('Pending','Approved','Declined')),
  approved_from date,
  approved_to date,
  payroll text check (payroll in ('Paid','Unpaid','Absent')),
  review_note text not null default '',
  email_state text not null default 'Pending' check (email_state in ('Pending','Sent','Needs setup','Failed','Imported')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (requested_to between requested_from and requested_from + 365),
  check (state <> 'Approved' or
    (approved_from is not null and approved_to is not null and approved_to between approved_from and approved_from + 365
      and payroll is not null and payroll in ('Paid','Unpaid'))),
  check (state <> 'Approved' or kind <> 'Sick Leave' or payroll <> 'Paid' or drive_file_id is not null)
);
create index staff_leave_requests_staff on goya_private.staff_leave_requests(staff_id, requested_from);

create table goya_private.staff_leave_uploads (
  request_id uuid primary key,
  staff_id uuid not null references public.staff(id) on delete restrict,
  drive_file_id text not null,
  fingerprint text not null
);

create table goya_private.staff_leave_drive_folders (
  parent_id text not null,
  folder_name text not null,
  drive_id text not null,
  primary key (parent_id,folder_name)
);

create table goya_private.staff_leave_email_settings (
  id boolean primary key default true check (id),
  owner_email text,
  hr_email text,
  revision integer not null default 1
);

create table goya_private.staff_hr_audit (
  id bigint generated always as identity primary key,
  staff_id uuid not null references public.staff(id) on delete restrict,
  event text not null,
  details jsonb not null,
  created_at timestamptz not null default now()
);

create table goya_private.roster_excel_archive (
  source_week date not null,
  source_row integer not null,
  source_name text not null,
  staff_id uuid references public.staff(id) on delete restrict,
  shifts jsonb not null,
  pending_off text not null default '',
  private_remarks text not null default '',
  primary key (source_week,source_row)
);
create index roster_excel_archive_staff on goya_private.roster_excel_archive(staff_id,source_week);

alter table goya_private.staff_hr_profiles enable row level security;
alter table goya_private.staff_leave_requests enable row level security;
alter table goya_private.staff_hr_audit enable row level security;
alter table goya_private.staff_leave_uploads enable row level security;
alter table goya_private.staff_leave_drive_folders enable row level security;
alter table goya_private.staff_leave_email_settings enable row level security;
alter table goya_private.roster_excel_archive enable row level security;
revoke all on goya_private.staff_hr_profiles,goya_private.staff_leave_requests,goya_private.staff_hr_audit,
  goya_private.staff_leave_uploads,goya_private.staff_leave_drive_folders,
  goya_private.staff_leave_email_settings,goya_private.roster_excel_archive
  from public,anon,authenticated;

create function goya_private.prevent_resigned_staff_activation()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.active and exists(select 1 from goya_private.staff_hr_profiles p where p.staff_id=new.id and p.last_day is not null) then
    raise exception 'Rejoin the staff member from Staff Records before activating';
  end if;
  return new;
end $$;
revoke all on function goya_private.prevent_resigned_staff_activation() from public,anon,authenticated;
create trigger prevent_resigned_staff_activation before update of active on public.staff
for each row when (new.active is true and old.active is distinct from new.active)
execute function goya_private.prevent_resigned_staff_activation();

create function public.goya_hr_admin_profiles(p_token text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  perform public.require_session(p_token,true);
  return coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'active',s.active,'profile',to_jsonb(p),
    'history',(select jsonb_agg(jsonb_build_object('event',a.event,'created_at',a.created_at,'details',a.details)
      order by a.id desc) from goya_private.staff_hr_audit a where a.staff_id=s.id and a.event in ('Resignation','Rejoined')))
    order by s.active desc,s.name) from public.staff s
    left join goya_private.staff_hr_profiles p on p.staff_id=s.id),'[]'::jsonb);
end $$;

create function public.goya_hr_archive_import(p_token text,p_rows jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare inserted integer;
begin
  perform public.require_session(p_token,true);
  if jsonb_typeof(p_rows) is distinct from 'array' or octet_length(p_rows::text)>800000 then
    raise exception 'Invalid archive data';
  end if;
  insert into goya_private.roster_excel_archive(source_week,source_row,source_name,staff_id,shifts,pending_off,private_remarks)
  select source_week,source_row,source_name,staff_id,shifts,coalesce(pending_off,''),coalesce(private_remarks,'')
    from jsonb_to_recordset(p_rows) as r(source_week date,source_row integer,source_name text,
      staff_id uuid,shifts jsonb,pending_off text,private_remarks text)
  on conflict(source_week,source_row) do update set staff_id=excluded.staff_id
  where roster_excel_archive.staff_id is null and excluded.staff_id is not null
    and roster_excel_archive.source_name=excluded.source_name and roster_excel_archive.shifts=excluded.shifts;
  get diagnostics inserted = row_count;
  return inserted;
end $$;

create function public.goya_hr_archive_read(p_token text,p_admin boolean,p_month date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare sess public.app_sessions := public.require_session(p_token,p_admin);
begin
  if not p_admin and not exists(select 1 from public.staff where id=sess.staff_id and active) then
    raise exception 'Unauthorized';
  end if;
  return coalesce((select jsonb_agg(case when p_admin then to_jsonb(a) else
    jsonb_build_object('source_week',a.source_week,'shifts',a.shifts,'pending_off',a.pending_off) end
    order by a.source_week desc,a.source_row)
    from goya_private.roster_excel_archive a
    where (p_admin or a.staff_id=sess.staff_id) and a.source_week+6>=p_month and a.source_week<p_month+interval '1 month'),'[]'::jsonb);
end $$;

create function public.goya_hr_save_profile(p_token text,p_staff uuid,p_profile jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare previous goya_private.staff_hr_profiles; cessation date := nullif(p_profile->>'last_day','')::date;
begin
  perform public.require_session(p_token,true);
  perform 1 from public.staff where id=p_staff for update;
  if not found then raise exception 'Staff member was not found'; end if;
  select * into previous from goya_private.staff_hr_profiles where staff_id=p_staff;
  if cessation > (now() at time zone 'Asia/Dubai')::date then
    raise exception 'Record resignation on or after the last working day';
  end if;
  if previous.last_day is not null and cessation is null then
    raise exception 'Use the rejoin action to remove resigned status';
  end if;
  insert into goya_private.staff_hr_profiles(staff_id,joining_date,employee_code,position,branch,manager_notes,last_day)
  values(p_staff,nullif(p_profile->>'joining_date','')::date,left(coalesce(p_profile->>'employee_code',''),80),
    left(coalesce(p_profile->>'position',''),120),left(coalesce(p_profile->>'branch',''),120),
    left(coalesce(p_profile->>'manager_notes',''),4000),cessation)
  on conflict(staff_id) do update set joining_date=excluded.joining_date,employee_code=excluded.employee_code,
    position=excluded.position,branch=excluded.branch,manager_notes=excluded.manager_notes,last_day=excluded.last_day,updated_at=now();
  if cessation is not null then
    update public.staff set active=false where id=p_staff and active;
    update public.app_sessions set expires_at=now() where staff_id=p_staff and not is_admin and expires_at>now();
  end if;
  insert into goya_private.staff_hr_audit(staff_id,event,details)
  values(p_staff,case when previous.last_day is distinct from cessation and cessation is not null then 'Resignation' else 'Profile saved' end,
    jsonb_build_object('prior_joining_date',previous.joining_date,'prior_last_day',previous.last_day,'last_day',cessation));
end $$;

create function public.goya_hr_rejoin(p_token text,p_staff uuid,p_date date)
returns void language plpgsql security definer set search_path='' as $$
declare cessation date;
begin
  perform public.require_session(p_token,true);
  perform 1 from public.staff where id=p_staff for update;
  select last_day into cessation from goya_private.staff_hr_profiles where staff_id=p_staff;
  if cessation is null or p_date is null or p_date<=cessation or p_date>(now() at time zone 'Asia/Dubai')::date then
    raise exception 'Enter a rejoin date after the last working day and on or before today';
  end if;
  update goya_private.staff_hr_profiles set last_day=null,updated_at=now() where staff_id=p_staff;
  update public.staff set active=true where id=p_staff;
  insert into goya_private.staff_hr_audit(staff_id,event,details)
    values(p_staff,'Rejoined',jsonb_build_object('last_day',cessation,'rejoined_on',p_date));
end $$;

create function public.goya_hr_my_journey(p_token text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare employee uuid := (public.require_session(p_token,false)).staff_id;
begin
  if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized'; end if;
  return jsonb_build_object('profile',(select jsonb_build_object('joining_date',joining_date,'employee_code',employee_code,
    'position',position,'branch',branch) from goya_private.staff_hr_profiles where staff_id=employee),
    'archived_pending_off',(select jsonb_build_object('value',pending_off,'week',source_week)
      from goya_private.roster_excel_archive where staff_id=employee and pending_off<>'' order by source_week desc,source_row desc limit 1),
    'archived_annual_days',coalesce((select jsonb_agg(distinct item->>'date')
      from goya_private.roster_excel_archive a cross join lateral jsonb_array_elements(a.shifts) item
      where a.staff_id=employee and lower(btrim(item->>'value'))='annual leave'),'[]'::jsonb),
    'requests',coalesce((select jsonb_agg(to_jsonb(r)-'drive_file_id'-'staff_id' order by requested_from desc,created_at desc)
      from goya_private.staff_leave_requests r where r.staff_id=employee),'[]'::jsonb));
end $$;

create function public.goya_hr_admin_requests(p_token text,p_month date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  perform public.require_session(p_token,true);
  return coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('name',s.name) order by r.created_at desc)
    from goya_private.staff_leave_requests r join public.staff s on s.id=r.staff_id
    where p_month is null or (coalesce(approved_to,requested_to)>=p_month
      and coalesce(approved_from,requested_from)<p_month+interval '1 month')),'[]'::jsonb);
end $$;

create function public.goya_hr_review(p_token text,p_id uuid,p_expected timestamptz,p_state text,
  p_from date,p_to date,p_payroll text,p_note text)
returns void language plpgsql security definer set search_path='' as $$
declare previous goya_private.staff_leave_requests;
begin
  perform public.require_session(p_token,true);
  select * into previous from goya_private.staff_leave_requests where id=p_id;
  if p_state is null or p_state not in ('Approved','Declined') or length(coalesce(p_note,''))>2000
    or (p_state='Approved' and (p_from is null or p_to is null or p_to<p_from or p_payroll is null or p_payroll not in ('Paid','Unpaid')))
    or (p_state='Declined' and p_payroll is distinct from 'Absent' and p_payroll is not null)
    or (p_payroll='Absent' and previous.kind<>'Sick Leave') then raise exception 'Invalid leave decision'; end if;
  perform 1 from public.staff where id=previous.staff_id for update;
  if p_state='Approved' and exists(select 1 from goya_private.staff_leave_requests other
    where other.staff_id=previous.staff_id and other.id<>p_id and other.state='Approved'
      and other.approved_from<=p_to and other.approved_to>=p_from) then
    raise exception 'There is already approved leave for part of this period';
  end if;
  update goya_private.staff_leave_requests set state=p_state, approved_from=case when p_state='Approved' then p_from end,
    approved_to=case when p_state='Approved' then p_to end,payroll=p_payroll,review_note=coalesce(p_note,''),updated_at=clock_timestamp()
    where id=p_id and updated_at=p_expected;
  if not found then raise exception 'Request changed. Reload before saving.'; end if;
  insert into goya_private.staff_hr_audit(staff_id,event,details) values(previous.staff_id,'Leave reviewed',
    jsonb_build_object('request',p_id,'prior_state',previous.state,'prior_from',previous.approved_from,'prior_to',previous.approved_to,
      'prior_payroll',previous.payroll,'prior_note',previous.review_note));
end $$;

create function public.goya_hr_week_leave(p_token text,p_week date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  perform public.require_session(p_token,true);
  return coalesce((select jsonb_agg(jsonb_build_object('id',id,'staff_id',staff_id,'kind',kind,
    'from',approved_from,'to',approved_to))
    from goya_private.staff_leave_requests where state='Approved' and approved_from<=p_week+6 and approved_to>=p_week),'[]'::jsonb);
end $$;

create function public.goya_hr_staff_identity(p_token text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare employee uuid := (public.require_session(p_token,false)).staff_id;
begin
  return (select jsonb_build_object('id',id,'name',name) from public.staff where id=employee and active);
end $$;

create function public.goya_hr_record_request(p_staff uuid,p_id uuid,p_kind text,p_from date,p_to date,p_reason text,p_drive text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result goya_private.staff_leave_requests;
begin
  perform 1 from public.staff where id=p_staff and active for share;
  if not found then raise exception 'Unauthorized'; end if;
  insert into goya_private.staff_leave_requests(id,staff_id,kind,requested_from,requested_to,reason,drive_file_id)
  values(p_id,p_staff,p_kind,p_from,p_to,p_reason,p_drive) on conflict(id) do nothing;
  select * into result from goya_private.staff_leave_requests where id=p_id and staff_id=p_staff;
  if not found then raise exception 'Request ID is unavailable'; end if;
  return to_jsonb(result);
end $$;

create function public.goya_hr_email_state(p_id uuid,p_state text)
returns void language sql security definer set search_path='' as $$
  update goya_private.staff_leave_requests set email_state=p_state
  where id=p_id and email_state not in ('Sent','Imported');
$$;

create function public.goya_hr_upload_slot(p_staff uuid,p_id uuid,p_drive text,p_fingerprint text)
returns text language plpgsql security definer set search_path='' as $$
declare slot goya_private.staff_leave_uploads;
begin
  insert into goya_private.staff_leave_uploads(request_id,staff_id,drive_file_id,fingerprint)
    values(p_id,p_staff,p_drive,p_fingerprint) on conflict(request_id) do nothing;
  select * into slot from goya_private.staff_leave_uploads where request_id=p_id;
  if slot.staff_id<>p_staff or slot.fingerprint<>p_fingerprint then raise exception 'Attachment changed. Start a new request.'; end if;
  return slot.drive_file_id;
end $$;

create function public.goya_hr_drive_folder_slot(p_parent text,p_name text,p_candidate text default null)
returns text language plpgsql security definer set search_path='' as $$
begin
  if p_candidate is not null then
    insert into goya_private.staff_leave_drive_folders(parent_id,folder_name,drive_id)
    values(p_parent,p_name,p_candidate) on conflict(parent_id,folder_name) do nothing;
  end if;
  return (select drive_id from goya_private.staff_leave_drive_folders where parent_id=p_parent and folder_name=p_name);
end $$;

create function goya_private.staff_leave_email_recipients()
returns jsonb language sql stable set search_path='' as $$
  select coalesce(
    (select jsonb_build_object('owner_email',owner_email,'hr_email',hr_email,'revision',revision)
      from goya_private.staff_leave_email_settings where id),
    jsonb_build_object('owner_email',null,'hr_email',null,'revision',0)
  );
$$;
revoke all on function goya_private.staff_leave_email_recipients() from public,anon,authenticated;

create function public.goya_hr_admin_email_settings(p_token text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  perform public.require_session(p_token,true);
  return goya_private.staff_leave_email_recipients();
end $$;

create function public.goya_hr_save_email_settings(p_token text,p_owner text,p_hr text,p_expected integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  owner_address text := nullif(btrim(p_owner),'');
  hr_address text := nullif(btrim(p_hr),'');
  address text;
begin
  perform public.require_session(p_token,true);
  foreach address in array array[owner_address,hr_address] loop
    if address is not null and (length(address)>254 or address !~ '^[^[:space:]@<>,;]+@[^[:space:]@<>,;.]+([.][^[:space:]@<>,;.]+)+$') then
      raise exception 'Enter a valid email address for Owner and HR.';
    end if;
  end loop;
  if p_expected=0 then
    insert into goya_private.staff_leave_email_settings(owner_email,hr_email) values(owner_address,hr_address)
      on conflict(id) do nothing;
  else
    update goya_private.staff_leave_email_settings
      set owner_email=owner_address,hr_email=hr_address,revision=revision+1
      where id and revision=p_expected;
  end if;
  if not found then raise exception 'Email settings changed. Reload the settings before saving again.'; end if;
  return goya_private.staff_leave_email_recipients();
end $$;

create function public.goya_hr_worker_email_settings()
returns jsonb language sql stable security definer set search_path='' as $$
  select goya_private.staff_leave_email_recipients() || jsonb_build_object(
    'manager_email',(select nullif(btrim(value->>'email'),'') from public.settings where key='admin')
  );
$$;

revoke execute on function public.goya_hr_admin_profiles(text),public.goya_hr_save_profile(text,uuid,jsonb),
  public.goya_hr_rejoin(text,uuid,date),public.goya_hr_my_journey(text),public.goya_hr_admin_requests(text,date),
  public.goya_hr_review(text,uuid,timestamptz,text,date,date,text,text),public.goya_hr_week_leave(text,date),
  public.goya_hr_staff_identity(text),public.goya_hr_record_request(uuid,uuid,text,date,date,text,text),
  public.goya_hr_email_state(uuid,text),public.goya_hr_upload_slot(uuid,uuid,text,text),
  public.goya_hr_drive_folder_slot(text,text,text),
  public.goya_hr_admin_email_settings(text),public.goya_hr_save_email_settings(text,text,text,integer),
  public.goya_hr_worker_email_settings(),
  public.goya_hr_archive_import(text,jsonb),public.goya_hr_archive_read(text,boolean,date) from public,anon,authenticated;
grant execute on function public.goya_hr_admin_profiles(text),public.goya_hr_save_profile(text,uuid,jsonb),
  public.goya_hr_rejoin(text,uuid,date),public.goya_hr_my_journey(text),public.goya_hr_admin_requests(text,date),
  public.goya_hr_review(text,uuid,timestamptz,text,date,date,text,text),public.goya_hr_week_leave(text,date),
  public.goya_hr_staff_identity(text),public.goya_hr_archive_import(text,jsonb),
  public.goya_hr_archive_read(text,boolean,date),public.goya_hr_admin_email_settings(text),
  public.goya_hr_save_email_settings(text,text,text,integer) to anon,authenticated;
grant execute on function public.goya_hr_record_request(uuid,uuid,text,date,date,text,text),
  public.goya_hr_email_state(uuid,text),public.goya_hr_upload_slot(uuid,uuid,text,text),
  public.goya_hr_drive_folder_slot(text,text,text),public.goya_hr_worker_email_settings() to service_role;

commit;
