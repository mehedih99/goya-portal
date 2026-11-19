begin;
set local lock_timeout='5s';

create table goya_private.staff_off_balances (
 staff_id uuid primary key references public.staff(id) on delete restrict,
 balance integer not null check (balance between -36500 and 36500),
 revision integer not null default 1,
 updated_at timestamptz not null default clock_timestamp()
);
create table goya_private.staff_management_decisions (
 id bigint generated always as identity primary key,
 request_id uuid not null references goya_private.staff_leave_requests(id) on delete restrict,
 actor text not null, session_ref text not null, note text not null default '',
 before_data jsonb not null, after_data jsonb not null,
 created_at timestamptz not null default clock_timestamp()
);
create table goya_private.staff_resignations (
 staff_id uuid primary key references public.staff(id) on delete restrict,
 last_working_day date not null, note text not null default '',actor text not null,
 updated_at timestamptz not null default clock_timestamp(),
 applied_at timestamptz,cancelled_at timestamptz
);
alter table goya_private.staff_off_balances enable row level security;
alter table goya_private.staff_management_decisions enable row level security;
alter table goya_private.staff_resignations enable row level security;
revoke all on goya_private.staff_off_balances,goya_private.staff_management_decisions,goya_private.staff_resignations from public,anon,authenticated;

alter table goya_private.staff_leave_requests drop constraint staff_leave_requests_kind_check;
alter table goya_private.staff_leave_requests add constraint staff_leave_requests_kind_check check
 (kind in ('Annual Leave','Sick Leave','Other Leave','Cancelled Off','Attendance Note','Pending Off','Advance Off','Emergency Leave','Resignation'));

create function goya_private.off_snapshot(employee uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb; archived record;
begin
 select to_jsonb(b) into result from goya_private.staff_off_balances b where staff_id=employee;
 if result is not null then return result; end if;
 select pending_off,source_week into archived from goya_private.roster_excel_archive
 where staff_id=employee and pending_off ~ '^[-+]?[0-9]{1,5}$' order by source_week desc,source_row desc limit 1;
 return jsonb_build_object('staff_id',employee,'balance',coalesce(archived.pending_off::integer,0),
  'revision',0,'updated_at',null,'source_week',archived.source_week);
end $$;

create function public.goya_management_balances(p_token text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform public.require_session(p_token,true);
 return coalesce((select jsonb_object_agg(id::text,goya_private.off_snapshot(id)) from public.staff),'{}'::jsonb);
end $$;
create function public.goya_management_save_balance(p_token text,p_staff uuid,p_value integer,p_expected integer,p_reason text,p_actor text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare prior jsonb; result jsonb;
begin
 perform public.require_session(p_token,true);
 if length(btrim(coalesce(p_actor,''))) not between 1 and 100 or length(btrim(coalesce(p_reason,''))) not between 1 and 2000
  or p_value is null or p_value not between -36500 and 36500 then raise exception 'Enter management name, reason and a valid balance'; end if;
 perform 1 from public.staff where id=p_staff for update;
 if not found then raise exception 'Staff not found'; end if;
 prior:=goya_private.off_snapshot(p_staff);
 if (prior->>'revision')::integer is distinct from p_expected then raise exception 'Balance changed. Reload before saving.'; end if;
 insert into goya_private.staff_off_balances(staff_id,balance) values(p_staff,p_value)
 on conflict(staff_id) do update set balance=excluded.balance,revision=staff_off_balances.revision+1,updated_at=clock_timestamp()
 returning to_jsonb(staff_off_balances) into result;
 insert into goya_private.staff_hr_audit(staff_id,event,details) values(p_staff,'Off balance changed',
 jsonb_build_object('before',prior,'after',result,'reason',p_reason,'actor',p_actor,'session_ref',md5(p_token)));
 return result;
end $$;

create function public.goya_management_requests(p_token text,p_month date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform public.require_session(p_token,true);
 return coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('name',s.name,'sections',s.sections,
  'management_history',coalesce((select jsonb_agg(to_jsonb(d)-'session_ref' order by d.id desc)
   from goya_private.staff_management_decisions d where d.request_id=r.id),'[]'::jsonb)) order by r.created_at desc)
 from goya_private.staff_leave_requests r join public.staff s on s.id=r.staff_id
 where p_month is null or (coalesce(r.approved_to,r.requested_to)>=p_month and coalesce(r.approved_from,r.requested_from)<p_month+interval '1 month')),'[]'::jsonb);
end $$;

create function public.goya_management_resignation(p_token text,p_staff uuid,p_day date,p_note text,p_actor text,p_expected timestamptz) returns void
language plpgsql security definer set search_path='' as $$
declare prior goya_private.staff_resignations; joined date;
begin
 perform public.require_session(p_token,true);
 if p_day is null or length(btrim(coalesce(p_actor,''))) not between 1 and 100 or length(coalesce(p_note,''))>4000 then raise exception 'Enter last working day and management name'; end if;
 perform 1 from public.staff where id=p_staff for update;
 if not found then raise exception 'Staff not found'; end if;
 select joining_date into joined from goya_private.staff_hr_profiles where staff_id=p_staff;
 if p_day<joined then raise exception 'Last working day must be on or after joining date'; end if;
 select * into prior from goya_private.staff_resignations where staff_id=p_staff;
 if prior.updated_at is distinct from p_expected then raise exception 'Resignation changed. Reopen profile.'; end if;
 if p_day >= (now() at time zone 'Asia/Dubai')::date and exists(select 1 from goya_private.staff_hr_profiles where staff_id=p_staff and last_day is not null) then raise exception 'Use Rejoin before scheduling a new resignation'; end if;
 insert into goya_private.staff_resignations(staff_id,last_working_day,note,actor) values(p_staff,p_day,coalesce(p_note,''),p_actor)
 on conflict(staff_id) do update set last_working_day=excluded.last_working_day,note=excluded.note,actor=excluded.actor,
 updated_at=clock_timestamp(),cancelled_at=null,applied_at=null;
 insert into goya_private.staff_hr_audit(staff_id,event,details) values(p_staff,'Resignation scheduled',
 jsonb_build_object('before',to_jsonb(prior),'last_day',p_day,'actor',p_actor,'note',p_note,'session_ref',md5(p_token)));
end $$;

create function goya_private.apply_resignations() returns integer
language plpgsql security definer set search_path='' as $$
declare plan record; total integer:=0;
begin
 for plan in select * from goya_private.staff_resignations where applied_at is null and cancelled_at is null
  and last_working_day<(now() at time zone 'Asia/Dubai')::date loop
  perform 1 from public.staff where id=plan.staff_id for update;
  select * into plan from goya_private.staff_resignations where staff_id=plan.staff_id and applied_at is null and cancelled_at is null and last_working_day<(now() at time zone 'Asia/Dubai')::date for update;
  if not found then continue; end if;
  insert into goya_private.staff_hr_profiles(staff_id,last_day) values(plan.staff_id,plan.last_working_day)
  on conflict(staff_id) do update set last_day=excluded.last_day,updated_at=clock_timestamp();
  update public.staff set active=false where id=plan.staff_id;
  update public.app_sessions set expires_at=now() where staff_id=plan.staff_id and not is_admin and expires_at>now();
  update goya_private.staff_resignations set applied_at=clock_timestamp() where staff_id=plan.staff_id;
  insert into goya_private.staff_hr_audit(staff_id,event,details) values(plan.staff_id,'Resignation',
   jsonb_build_object('last_day',plan.last_working_day,'actor',plan.actor,'note',plan.note));
  total:=total+1;
 end loop;
 return total;
end $$;

create function public.goya_management_cancel_resignation(p_token text,p_staff uuid,p_expected timestamptz,p_actor text,p_note text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform public.require_session(p_token,true);
 if length(btrim(coalesce(p_actor,''))) not between 1 and 100 or length(btrim(coalesce(p_note,''))) not between 1 and 2000 then raise exception 'Management name and reason required'; end if;
 perform 1 from public.staff where id=p_staff for update;
 update goya_private.staff_resignations set cancelled_at=clock_timestamp(),updated_at=clock_timestamp()
 where staff_id=p_staff and updated_at=p_expected and applied_at is null and cancelled_at is null;
 if not found then raise exception 'Resignation changed or already effective. Reopen profile.'; end if;
 insert into goya_private.staff_hr_audit(staff_id,event,details) values(p_staff,'Resignation cancelled',jsonb_build_object('actor',p_actor,'note',p_note));
end $$;

create function public.goya_management_rejoin(p_token text,p_staff uuid,p_date date) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform public.goya_hr_rejoin(p_token,p_staff,p_date);
 update goya_private.staff_resignations set cancelled_at=clock_timestamp() where staff_id=p_staff;
end $$;

create function public.goya_management_profiles(p_token text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform public.require_session(p_token,true);
 return coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'active',s.active,'profile',to_jsonb(p),
 'off_balance',goya_private.off_snapshot(s.id),'resignation',to_jsonb(r),
 'history',coalesce((select jsonb_agg(to_jsonb(a) order by a.id desc) from goya_private.staff_hr_audit a where a.staff_id=s.id),'[]'::jsonb)) order by s.active desc,s.name)
 from public.staff s left join goya_private.staff_hr_profiles p on p.staff_id=s.id
 left join goya_private.staff_resignations r on r.staff_id=s.id),'[]'::jsonb);
end $$;

create function public.goya_management_review(p_token text,p_id uuid,p_expected timestamptz,p_state text,p_from date,p_to date,p_payroll text,p_note text,p_actor text,p_private_note text) returns void
language plpgsql security definer set search_path='' as $$
declare prior goya_private.staff_leave_requests; after_row goya_private.staff_leave_requests;
 old_days integer:=0; new_days integer:=0; balance jsonb; plan goya_private.staff_resignations;
begin
 perform public.require_session(p_token,true);
 if length(btrim(coalesce(p_actor,''))) not between 1 and 100 or length(coalesce(p_private_note,''))>2000
  or (p_state='Declined' and length(btrim(coalesce(p_private_note,'')))=0) then raise exception 'Management name and rejection reason are required'; end if;
 select * into prior from goya_private.staff_leave_requests where id=p_id;
 if not found then raise exception 'Request not found'; end if;
 perform 1 from public.staff where id=prior.staff_id for update;
 select * into prior from goya_private.staff_leave_requests where id=p_id for update;
 if prior.state in ('Withdrawn','Recorded') then raise exception 'This request cannot be reviewed'; end if;
 if prior.updated_at is distinct from p_expected then raise exception 'Request changed. Reload before saving.'; end if;
 if prior.kind='Resignation' then
  if p_state not in ('Approved','Declined') or (p_state='Approved' and (p_from is null or p_from is distinct from p_to)) then raise exception 'Choose one last working day'; end if;
  if p_state='Approved' then
   select * into plan from goya_private.staff_resignations where staff_id=prior.staff_id;
   perform public.goya_management_resignation(p_token,prior.staff_id,p_from,p_private_note,p_actor,plan.updated_at);
  elsif prior.state='Approved' then raise exception 'Use Cancel resignation or Rejoin in the staff profile'; end if;
  update goya_private.staff_leave_requests set state=p_state,approved_from=case when p_state='Approved' then p_from end,
   approved_to=case when p_state='Approved' then p_from end,payroll=case when p_state='Approved' then 'Unpaid' end,
   review_note=coalesce(p_note,''),updated_at=clock_timestamp() where id=p_id;
 else
  if prior.kind in ('Pending Off','Advance Off') then
   if prior.state='Approved' then old_days:=prior.approved_to-prior.approved_from+1; end if;
   if p_state='Approved' then new_days:=p_to-p_from+1; end if;
   balance:=goya_private.off_snapshot(prior.staff_id);
   if prior.kind='Pending Off' and new_days>old_days and new_days-old_days>(balance->>'balance')::integer then raise exception 'Not enough pending off. Use Advance Off or correct the balance.'; end if;
  end if;
  perform public.goya_hr_review(p_token,p_id,p_expected,p_state,p_from,p_to,p_payroll,p_note);
  if new_days is distinct from old_days then
   perform public.goya_management_save_balance(p_token,prior.staff_id,(balance->>'balance')::integer+old_days-new_days,
    (balance->>'revision')::integer,'Request '||p_id::text||' · '||p_private_note,p_actor);
  end if;
 end if;
 select * into after_row from goya_private.staff_leave_requests where id=p_id;
 insert into goya_private.staff_management_decisions(request_id,actor,session_ref,note,before_data,after_data)
 values(p_id,p_actor,md5(p_token),coalesce(p_private_note,''),to_jsonb(prior),to_jsonb(after_row));
end $$;

create function public.goya_management_notice_status(p_token text,p_id uuid,p_active boolean,p_expected timestamptz) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform public.require_session(p_token,true);
 if p_active and exists(select 1 from goya_private.notices where id=p_id and (length(btrim(body))=0 or expires_at<=now())) then raise exception 'Edit the notice content and expiry before publishing'; end if;
 update goya_private.notices set active=p_active,updated_at=clock_timestamp() where id=p_id and deleted_at is null and updated_at=p_expected;
 if not found then raise exception 'Notice changed. Reload before saving.'; end if;
 if not p_active then update goya_private.notice_push_jobs set cancelled_at=coalesce(cancelled_at,now()) where notice_id=p_id; end if;
end $$;

create function public.goya_management_notice_draft(p_token text,p_id uuid,p_title text,p_body text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result goya_private.notices;
begin
 perform public.require_session(p_token,true);
 if length(btrim(coalesce(p_title,'')))=0 then raise exception 'Enter a title for your draft'; end if;
 if p_id is not null then raise exception 'Use Save Notice to update an existing notice'; end if;
 insert into goya_private.notices(title,body,active,published_at,is_draft) values(p_title,coalesce(p_body,''),false,now(),true) returning * into result;
 return to_jsonb(result);
end $$;

revoke all on function goya_private.off_snapshot(uuid),goya_private.apply_resignations() from public,anon,authenticated;
do $$ declare item record; begin
 for item in select oid::regprocedure as signature from pg_proc where pronamespace='public'::regnamespace and proname like 'goya_management_%' loop
 execute 'revoke all on function '||item.signature||' from public,anon,authenticated';
 execute 'grant execute on function '||item.signature||' to anon,authenticated';
 end loop;
end $$;

alter table public.attendance_live_days drop constraint attendance_live_days_classification_chk;
alter table public.attendance_live_days add constraint attendance_live_days_classification_chk check
 (classification in ('Duty','Day Off - Pending Review','Weekly Off','Leave','Annual Leave','Sick Leave','Unpaid Leave','Absent','Public Holiday','Other Approved'));

alter table goya_private.notices add column is_draft boolean not null default false;
create function goya_private.notice_published_state() returns trigger language plpgsql set search_path='' as $$
begin if new.active then new.is_draft:=false; end if;return new;end $$;
create trigger notice_published_state before insert or update on goya_private.notices for each row execute function goya_private.notice_published_state();
revoke all on function goya_private.notice_published_state() from public,anon,authenticated;

create function public.goya_management_journey(p_token text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare employee uuid:=(public.require_session(p_token,false)).staff_id; result jsonb;
begin
 result:=public.goya_hr_my_journey(p_token);
 return result||jsonb_build_object('off_balance',goya_private.off_snapshot(employee));
end $$;
revoke all on function public.goya_management_journey(text) from public,anon,authenticated;
grant execute on function public.goya_management_journey(text) to anon,authenticated;

create function public.goya_management_report(p_token text,p_staff uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 perform public.require_session(p_token,true);
 return jsonb_build_object(
 'attendance',coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('sessions',coalesce((select jsonb_agg(jsonb_build_object('check_in_at',s.check_in_at,'check_out_at',s.check_out_at) order by s.check_in_at) from public.attendance_live_sessions s where s.staff_id=d.staff_id and s.operational_date=d.operational_date and not s.is_deleted),'[]'::jsonb)) order by d.operational_date desc) from public.attendance_live_days d where d.staff_id=p_staff and not d.is_deleted),'[]'::jsonb),
 'rosters',coalesce((select jsonb_agg(jsonb_build_object('week',r.week_start,'revision',r.revision,'days',r.schedule->'staff'->p_staff::text) order by r.week_start desc,r.revision desc) from goya_private.roster_publications r where r.schedule->'staff' ? p_staff::text),'[]'::jsonb),
 'documents',coalesce((select jsonb_agg(jsonb_build_object('category',d.category,'title',d.custom_title,'file_name',d.file_name,'drive_file_id',d.drive_file_id,'uploaded_at',d.uploaded_at) order by d.uploaded_at desc) from goya_private.staff_document_versions d where d.staff_id=p_staff and d.uploaded_at is not null),'[]'::jsonb),
 'legacy_attendance',coalesce((select jsonb_agg(to_jsonb(a) order by a.operational_date desc) from public.attendance_records a join public.attendance_staff s on s.id=a.attendance_staff_id where s.portal_staff_id=p_staff),'[]'::jsonb),
 'archive',coalesce((select jsonb_agg(to_jsonb(a) order by a.source_week desc,a.source_row) from goya_private.roster_excel_archive a where a.staff_id=p_staff),'[]'::jsonb),
 'annual_history',public.goya_hr_annual_history(p_token,p_staff));
end $$;
revoke all on function public.goya_management_report(text,uuid) from public,anon,authenticated;
grant execute on function public.goya_management_report(text,uuid) to anon,authenticated;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_classify_day(p_token text, p_staff_id uuid, p_date date, p_classification text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare oldv jsonb; newv public.attendance_live_days; begin
  perform public.require_session(p_token,true);
  if p_classification not in ('Duty','Day Off - Pending Review','Weekly Off','Annual Leave','Leave','Sick Leave','Unpaid Leave','Absent','Public Holiday','Other Approved') then
    raise exception 'Invalid attendance classification';
  end if;
  select to_jsonb(d) into oldv from public.attendance_live_days d where d.staff_id=p_staff_id and d.operational_date=p_date;
  insert into public.attendance_live_days(staff_id,operational_date,classification,classification_note)
  values(p_staff_id,p_date,p_classification,nullif(trim(coalesce(p_note,'')),''))
  on conflict(staff_id,operational_date) do update set classification=excluded.classification,classification_note=excluded.classification_note,is_deleted=false,deleted_at=null,deleted_reason=null,updated_at=now()
  returning * into newv;
  insert into public.attendance_live_audit(staff_id,operational_date,actor_type,action,before_data,after_data)
  values(p_staff_id,p_date,'admin','CLASSIFY_DAY',oldv,to_jsonb(newv));
  return to_jsonb(newv);
end $function$
;
CREATE OR REPLACE FUNCTION public.goya_hr_week_leave(p_token text, p_week date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.require_session(p_token,true);
  return coalesce((select jsonb_agg(jsonb_build_object('id',id,'staff_id',staff_id,'kind',case when kind in ('Pending Off','Advance Off') then 'Weekly Off' when kind='Emergency Leave' then 'Other Leave' else kind end,
    'from',approved_from,'to',approved_to))
    from goya_private.staff_leave_requests where kind<>'Resignation' and state='Approved' and approved_from<=p_week+6 and approved_to>=p_week),'[]'::jsonb);
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
    'off_balances',public.goya_management_balances(p_token),'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'sections',s.sections) order by s.name,s.id)
      from public.staff s where s.active and not exists(select 1 from goya_private.staff_resignations x where x.staff_id=s.id and x.cancelled_at is null and x.last_working_day<p_week)),'[]'::jsonb),
    'approved_leave',public.goya_hr_week_leave(p_token,p_week),
    'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.revision desc) from
      (select revision,published_at from goya_private.roster_publications where week_start=p_week order by revision desc limit 30) h),'[]'::jsonb)
  );
end $function$
;
select cron.schedule('goya-employment-cessation','* * * * *','select goya_private.apply_resignations()');
CREATE OR REPLACE FUNCTION public.goya_roster_save(p_token text, p_week date, p_expected integer, p_schedule jsonb, p_publish boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare next_revision integer; member record; day jsonb; segment jsonb; previous_end integer; start_min integer; end_min integer;
  snapshot jsonb; leave_day record;
begin
  perform public.require_session(p_token,true);
  if p_week is null or p_schedule is null or p_expected is null or p_publish is null
    or extract(isodow from p_week)<>1 or jsonb_typeof(p_schedule->'staff') is distinct from 'object'
    or jsonb_typeof(p_schedule->'notes') is distinct from 'string'
    or length(p_schedule->>'notes')>2000 or octet_length(p_schedule::text)>262144 then
    raise exception 'Invalid roster';
  end if;
  for member in select * from jsonb_each(p_schedule->'staff') loop
    if not exists(select 1 from public.staff s where s.id::text=member.key and (not p_publish or s.active))
      or jsonb_typeof(member.value) is distinct from 'array' then raise exception 'Invalid roster staff'; end if;
    if jsonb_array_length(member.value)<>7 then raise exception 'Enter all seven days'; end if;
    for day in select value from jsonb_array_elements(member.value) loop
      if day='null'::jsonb then continue; end if;
      if jsonb_typeof(day) is distinct from 'object'
        or coalesce(day->>'kind','') not in ('Shift','Weekly Off','Annual Leave','Sick Leave','Other Leave')
        or jsonb_typeof(day->'segments') is distinct from 'array' then raise exception 'Invalid roster day'; end if;
      if length(coalesce(day->>'note',''))>500 then raise exception 'Shift note is too long'; end if;
      if day->>'kind'='Shift' then
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
      select r.staff_id::text as staff_id,case when r.kind in ('Pending Off','Advance Off') then 'Weekly Off' when r.kind='Emergency Leave' then 'Other Leave' else r.kind end as kind,d as day_index
      from goya_private.staff_leave_requests r join public.staff s on s.id=r.staff_id and s.active
      cross join generate_series(0,6) as dates(d)
      where r.kind<>'Resignation' and r.state='Approved' and p_week+d between r.approved_from and r.approved_to
      order by r.staff_id,d
    loop
      if not ((snapshot->'staff') ? leave_day.staff_id) then
        snapshot := jsonb_set(snapshot,array['staff',leave_day.staff_id],'[null,null,null,null,null,null,null]');
      end if;
      snapshot := jsonb_set(snapshot,array['staff',leave_day.staff_id,leave_day.day_index::text],
        jsonb_build_object('kind',leave_day.kind,'segments','[]'::jsonb,'note',''));
    end loop;
  end if;
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
    insert into goya_private.roster_publications(week_start,revision,schedule) values(p_week,next_revision,snapshot);
    update goya_private.roster_weeks set published_revision=next_revision where week_start=p_week;
  end if;
  return next_revision;
end $function$

;
commit;
