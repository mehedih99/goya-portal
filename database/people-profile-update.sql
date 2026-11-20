begin;
alter table goya_private.staff_hr_profiles
 add column if not exists mobile text not null default '',
 add column if not exists email text not null default '',
 add column if not exists address text not null default '',
 add column if not exists nationality text not null default '',
 add column if not exists date_of_birth date,
 add column if not exists employment_type text not null default '',
 add column if not exists probation_end date,
 add column if not exists emergency_name text not null default '',
 add column if not exists emergency_relationship text not null default '',
 add column if not exists emergency_phone text not null default '';
alter table goya_private.staff_document_versions add column if not exists expires_on date;
alter table goya_private.staff_document_versions drop constraint staff_document_versions_category_check;
alter table goya_private.staff_document_versions add constraint staff_document_versions_category_check check(
 (category in ('emirates-id','contract','food-safety','health-card','work-permit','residence-visa','health-insurance','pic-certificate','occupational-health-card','noc','profile-photo') and custom_title is null)
 or (category ~ '^custom-[a-f0-9-]{36}$' and custom_title is not null and length(btrim(custom_title)) between 1 and 100));
alter table goya_private.staff_document_versions add constraint staff_document_profile_photo_type check(category<>'profile-photo' or mime_type in ('image/jpeg','image/png'));

create or replace function goya_private.employed_on(employee uuid,day date) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.staff s left join goya_private.staff_hr_profiles p on p.staff_id=s.id
 left join goya_private.staff_resignations r on r.staff_id=s.id and r.cancelled_at is null
 where s.id=employee and (p.joining_date is null or day>=p.joining_date)
 and (coalesce(p.last_day,r.last_working_day) is null or day<=coalesce(p.last_day,r.last_working_day))
 and not exists(select 1 from goya_private.staff_hr_audit a where a.staff_id=employee and a.event='Rejoined'
 and day>(a.details->>'last_day')::date and day<(a.details->>'rejoined_on')::date));
$$;
revoke all on function goya_private.employed_on(uuid,date) from public,anon,authenticated;
create or replace function goya_private.employment_note(employee uuid,day date) returns text
language sql stable security definer set search_path='' as $$
 select concat_ws(' · ',case when p.joining_date=day or exists(select 1 from goya_private.staff_hr_audit a where a.staff_id=employee and a.event='Rejoined' and a.details->>'rejoined_on'=day::text) then 'Joining Day' end,
 case when coalesce(p.last_day,r.last_working_day)=day then 'Resigned' end)
 from goya_private.staff_hr_profiles p left join goya_private.staff_resignations r on r.staff_id=p.staff_id and r.cancelled_at is null where p.staff_id=employee;
$$;
revoke all on function goya_private.employment_note(uuid,date) from public,anon,authenticated;

create or replace function public.goya_people_save_staff(p_token text,p_row jsonb,p_profile jsonb,p_expected timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare employee uuid:=nullif(p_row->>'id','')::uuid; previous goya_private.staff_hr_profiles; saved jsonb;
begin
 perform public.require_session(p_token,true);
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
 update goya_private.staff_hr_profiles set mobile=left(coalesce(p_profile->>'mobile',mobile),60),email=left(coalesce(p_profile->>'email',email),254),address=left(coalesce(p_profile->>'address',address),1000),
 nationality=left(coalesce(p_profile->>'nationality',nationality),100),date_of_birth=nullif(p_profile->>'date_of_birth','')::date,
 employment_type=left(coalesce(p_profile->>'employment_type',employment_type),80),probation_end=nullif(p_profile->>'probation_end','')::date,
 emergency_name=left(coalesce(p_profile->>'emergency_name',emergency_name),120),emergency_relationship=left(coalesce(p_profile->>'emergency_relationship',emergency_relationship),80),
 emergency_phone=left(coalesce(p_profile->>'emergency_phone',emergency_phone),60) where staff_id=employee;
 return jsonb_build_object('id',employee,'profile',(select to_jsonb(p) from goya_private.staff_hr_profiles p where p.staff_id=employee));
end $$;
revoke all on function public.goya_people_save_staff(text,jsonb,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function public.goya_people_save_staff(text,jsonb,jsonb,timestamptz) to anon,authenticated;

create or replace function public.goya_people_document_expiry(p_token text,p_id uuid,p_staff uuid,p_expires date) returns void
language plpgsql security definer set search_path='' as $$
declare employee uuid:=goya_private.document_staff(p_token,p_staff);
begin
 update goya_private.staff_document_versions set expires_on=p_expires where id=p_id and staff_id=employee;
 if not found then raise exception 'Document not found'; end if;
end $$;
revoke all on function public.goya_people_document_expiry(text,uuid,uuid,date) from public,anon,authenticated;
grant execute on function public.goya_people_document_expiry(text,uuid,uuid,date) to anon,authenticated;

create or replace function public.goya_people_email_draft(p_token text,p_request uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare employee uuid:=(public.require_session(p_token,false)).staff_id; request goya_private.staff_leave_requests; recipients jsonb;
begin
 select * into request from goya_private.staff_leave_requests where id=p_request and staff_id=employee and kind in ('Annual Leave','Resignation') and state not in ('Withdrawn','Declined');
 if not found then raise exception 'Request is not available for email'; end if;
 if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized'; end if;
 recipients:=public.goya_hr_worker_email_settings();
 return jsonb_build_object('owner',recipients->>'owner_email','hr',recipients->>'hr_email','manager',recipients->>'manager_email',
 'staff',(select jsonb_build_object('name',s.name,'code',p.employee_code,'position',p.position,'mobile',p.mobile) from public.staff s left join goya_private.staff_hr_profiles p on p.staff_id=s.id where s.id=employee),
 'request',to_jsonb(request)-'drive_file_id'-'review_note'-'staff_id');
end $$;
revoke all on function public.goya_people_email_draft(text,uuid) from public,anon,authenticated;
grant execute on function public.goya_people_email_draft(text,uuid) to anon,authenticated;
CREATE OR REPLACE FUNCTION public.goya_hr_documents(p_token text, p_staff uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := goya_private.document_staff(p_token,p_staff);
begin
  return (with versions as (
    select d.id,d.category,d.file_name,d.mime_type,d.byte_size,d.uploaded_at,d.custom_title,d.expires_on,
      row_number() over (partition by d.category order by d.uploaded_at desc,d.id desc) as version_rank
    from goya_private.staff_document_versions d where d.staff_id=employee and d.uploaded_at is not null)
  select coalesce(jsonb_agg(to_jsonb(v) order by v.category,v.version_rank),'[]'::jsonb)
  from versions v where p_staff is not null or v.version_rank=1);
end
$function$;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_history(p_token text, p_start date, p_end date, p_staff_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rules jsonb:=public.attendance_live_rules();
  sys_start date:=coalesce((rules->>'system_start_date')::date,p_start);
  e date:=least(p_end,timezone(coalesce(rules->>'timezone','Asia/Dubai'),now())::date);
begin
  perform public.require_session(p_token,true);
  if p_start is null or p_end is null or p_end<p_start then raise exception 'Invalid date range'; end if;
  if e<p_start then return jsonb_build_object('server_now',now(),'rules',rules,'rows','[]'::jsonb); end if;
  return jsonb_build_object('server_now',now(),'rules',rules,'rows',coalesce((
    with base as (
      select s.id staff_id,s.name staff_name,s.sections,g::date operational_date from public.staff s cross join generate_series(greatest(p_start,sys_start),e,interval '1 day') g where (s.active=true or exists(select 1 from goya_private.staff_hr_profiles hp where hp.staff_id=s.id and hp.last_day is not null)) and (p_staff_id is null or s.id=p_staff_id)
      union select s.id,s.name,s.sections,d.operational_date from public.staff s join public.attendance_live_days d on d.staff_id=s.id where (s.active=true or exists(select 1 from goya_private.staff_hr_profiles hp where hp.staff_id=s.id and hp.last_day is not null)) and (p_staff_id is null or s.id=p_staff_id) and d.operational_date between p_start and e and coalesce(d.is_deleted,false)=false
      union select s.id,s.name,s.sections,x.operational_date from public.staff s join public.attendance_live_sessions x on x.staff_id=s.id where (s.active=true or exists(select 1 from goya_private.staff_hr_profiles hp where hp.staff_id=s.id and hp.last_day is not null)) and (p_staff_id is null or s.id=p_staff_id) and x.operational_date between p_start and e and coalesce(x.is_deleted,false)=false
    )
    select jsonb_agg(to_jsonb(q) order by q.operational_date desc,q.staff_name) from (
      select b.operational_date,b.staff_id,b.staff_name,b.sections,(select st.active from public.staff st where st.id=b.staff_id) staff_active,coalesce(d.break_taken,true) break_taken,coalesce(d.split_shift_allowed,false) split_shift_allowed,
        case when exists(select 1 from public.attendance_live_sessions sx where sx.staff_id=b.staff_id and sx.operational_date=b.operational_date and coalesce(sx.is_deleted,false)=false)
             then coalesce(nullif(d.classification,'Day Off - Pending Review'),'Duty') else coalesce(d.classification,'Day Off - Pending Review') end classification,
        d.classification_note,goya_private.employment_note(b.staff_id,b.operational_date) employment_note,d.ot_policy,d.scheduled_start,coalesce(d.late_minutes,0) late_minutes,
        coalesce((select jsonb_agg(to_jsonb(x) order by x.check_in_at,x.created_at) from public.attendance_live_sessions x
          where x.staff_id=b.staff_id and x.operational_date=b.operational_date and coalesce(x.is_deleted,false)=false),'[]'::jsonb) sessions
      from base b left join public.attendance_live_days d on d.staff_id=b.staff_id and d.operational_date=b.operational_date and coalesce(d.is_deleted,false)=false
      where goya_private.employed_on(b.staff_id,b.operational_date)
    ) q
  ),'[]'::jsonb));
end $function$;
CREATE OR REPLACE FUNCTION public.attendance_legacy_admin_history(p_token text, p_start date, p_end date, p_staff_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.require_session(p_token,true);
  if p_start is null or p_end is null or p_end < p_start then
    raise exception 'Invalid date range';
  end if;

  return jsonb_build_object(
    'rows', coalesce((
      with candidates as (
        select a.id attendance_staff_id, a.portal_staff_id staff_id, s.name staff_name, r.operational_date
          from public.attendance_staff a
          join public.staff s on s.id=a.portal_staff_id
          join public.attendance_records r on r.attendance_staff_id=a.id
         where r.operational_date between p_start and p_end
           and (p_staff_id is null or a.portal_staff_id=p_staff_id)
        union
        select a.id, a.portal_staff_id, s.name, x.operational_date
          from public.attendance_staff a
          join public.staff s on s.id=a.portal_staff_id
          join public.attendance_staff_submissions x on x.attendance_staff_id=a.id
         where x.operational_date between p_start and p_end
           and (p_staff_id is null or a.portal_staff_id=p_staff_id)
      )
      select jsonb_agg(jsonb_build_object(
        'staff_id',c.staff_id,
        'staff_name',c.staff_name,'staff_active',(select st.active from public.staff st where st.id=c.staff_id),'employment_note',goya_private.employment_note(c.staff_id,c.operational_date),
        'operational_date',c.operational_date,
        'record',(select to_jsonb(r) from public.attendance_records r
                  where r.attendance_staff_id=c.attendance_staff_id and r.operational_date=c.operational_date
                  limit 1),
        'submission',(select to_jsonb(x) from public.attendance_staff_submissions x
                      where x.attendance_staff_id=c.attendance_staff_id and x.operational_date=c.operational_date
                      order by x.submitted_at desc nulls last limit 1)
      ) order by c.operational_date desc,c.staff_name)
      from candidates c where goya_private.employed_on(c.staff_id,c.operational_date)
    ),'[]'::jsonb)
  );
end $function$;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_dashboard(p_token text, p_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d date:=coalesce(p_date,public.attendance_live_operational_date(now())); begin
  perform public.require_session(p_token,true);
  return jsonb_build_object(
    'server_now',now(),'operational_date',d,'rules',public.attendance_live_rules(),
    'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'sections',s.sections,'active',s.active) order by s.name) from public.staff s where s.active=true and goya_private.employed_on(s.id,d)),'[]'::jsonb),
    'days',coalesce((select jsonb_agg(to_jsonb(x)) from public.attendance_live_days x where x.operational_date=d and goya_private.employed_on(x.staff_id,d) and coalesce(x.is_deleted,false)=false),'[]'::jsonb),
    'sessions',coalesce((select jsonb_agg(to_jsonb(x) order by x.staff_id,x.session_no) from public.attendance_live_sessions x where x.operational_date=d and goya_private.employed_on(x.staff_id,d) and coalesce(x.is_deleted,false)=false),'[]'::jsonb)
  );
end $function$;
CREATE OR REPLACE FUNCTION public.attendance_live_public_dashboard(p_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  d date:=coalesce(p_date,public.attendance_live_operational_date(now()));
  rules jsonb:=public.attendance_live_rules();
begin
  return jsonb_build_object(
    'server_now',now(),
    'operational_date',d,
    'rules',jsonb_build_object(
      'duty_presence_minutes',coalesce((rules->>'duty_presence_minutes')::int,540),
      'regular_net_minutes',coalesce((rules->>'regular_net_minutes')::int,480),
      'break_minutes',coalesce((rules->>'break_minutes')::int,60),
      'timezone',coalesce(rules->>'timezone','Asia/Dubai')
    ),
    'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name)
                      from public.staff s where s.active=true and goya_private.employed_on(s.id,d)),'[]'::jsonb),
    'days',coalesce((select jsonb_agg(jsonb_build_object(
                       'staff_id',x.staff_id,'operational_date',x.operational_date,
                       'break_taken',x.break_taken,'classification',x.classification,
                       'ot_policy',x.ot_policy,'scheduled_start',x.scheduled_start,'late_minutes',x.late_minutes))
                      from public.attendance_live_days x
                      where x.operational_date=d and goya_private.employed_on(x.staff_id,d) and coalesce(x.is_deleted,false)=false),'[]'::jsonb),
    'sessions',coalesce((select jsonb_agg(jsonb_build_object(
                           'id',x.id,'staff_id',x.staff_id,'operational_date',x.operational_date,
                           'session_no',x.session_no,'check_in_at',x.check_in_at,'check_out_at',x.check_out_at,
                           'check_in_verified',x.check_in_verified,'check_out_verified',x.check_out_verified)
                         order by x.staff_id,x.session_no)
                        from public.attendance_live_sessions x
                        where x.operational_date=d and goya_private.employed_on(x.staff_id,d) and coalesce(x.is_deleted,false)=false),'[]'::jsonb)
  );
end $function$;
CREATE OR REPLACE FUNCTION public.attendance_live_management_dashboard(p_key text, p_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  d date:=coalesce(p_date,public.attendance_live_operational_date(now()));
  rules jsonb:=public.attendance_live_rules();
begin
  if not public.attendance_live_management_validate(p_key) then
    raise exception 'Invalid or expired management link';
  end if;
  return jsonb_build_object(
    'server_now',now(),
    'operational_date',d,
    'rules',jsonb_build_object(
      'duty_presence_minutes',coalesce((rules->>'duty_presence_minutes')::int,540),
      'regular_net_minutes',coalesce((rules->>'regular_net_minutes')::int,480),
      'break_minutes',coalesce((rules->>'break_minutes')::int,60),
      'timezone',coalesce(rules->>'timezone','Asia/Dubai')
    ),
    'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name)
                      from public.staff s where s.active=true and goya_private.employed_on(s.id,d)),'[]'::jsonb),
    'days',coalesce((select jsonb_agg(jsonb_build_object(
                       'staff_id',x.staff_id,'operational_date',x.operational_date,
                       'break_taken',x.break_taken,'classification',x.classification,
                       'classification_note',x.classification_note,'ot_policy',x.ot_policy,'scheduled_start',x.scheduled_start,
                       'late_minutes',x.late_minutes))
                      from public.attendance_live_days x
                      where x.operational_date=d and goya_private.employed_on(x.staff_id,d) and coalesce(x.is_deleted,false)=false),'[]'::jsonb),
    'sessions',coalesce((select jsonb_agg(jsonb_build_object(
                           'id',x.id,'staff_id',x.staff_id,'operational_date',x.operational_date,
                           'session_no',x.session_no,'check_in_at',x.check_in_at,'check_out_at',x.check_out_at,
                           'check_in_verified',x.check_in_verified,'check_out_verified',x.check_out_verified)
                         order by x.staff_id,x.session_no)
                        from public.attendance_live_sessions x
                        where x.operational_date=d and goya_private.employed_on(x.staff_id,d) and coalesce(x.is_deleted,false)=false),'[]'::jsonb)
  );
end $function$;
CREATE OR REPLACE FUNCTION public.attendance_live_public_month(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sd date:=date_trunc('month',p_month)::date;
  ed date:=(date_trunc('month',p_month)+interval '1 month - 1 day')::date;
  rules jsonb:=public.attendance_live_rules();
  today_local date:=timezone(coalesce(rules->>'timezone','Asia/Dubai'),now())::date;
  sys_start date:=coalesce((rules->>'system_start_date')::date,sd);
begin
  if p_month is null then raise exception 'Month is required'; end if;
  sd:=greatest(sd,sys_start);
  ed:=least(ed,today_local);
  if ed<sd then return jsonb_build_object('server_now',now(),'rules',rules,'rows','[]'::jsonb); end if;
  return jsonb_build_object(
    'server_now',now(),
    'rules',jsonb_build_object(
      'duty_presence_minutes',coalesce((rules->>'duty_presence_minutes')::int,540),
      'regular_net_minutes',coalesce((rules->>'regular_net_minutes')::int,480),
      'break_minutes',coalesce((rules->>'break_minutes')::int,60),
      'timezone',coalesce(rules->>'timezone','Asia/Dubai')
    ),
    'rows',coalesce((
      select jsonb_agg(to_jsonb(q) order by q.operational_date desc,q.staff_name)
      from (
        select g::date operational_date,s.id staff_id,s.name staff_name,
          coalesce(d.break_taken,true) break_taken,
          case when exists(select 1 from public.attendance_live_sessions sx
                           where sx.staff_id=s.id and sx.operational_date=g::date and coalesce(sx.is_deleted,false)=false)
               then coalesce(nullif(d.classification,'Day Off - Pending Review'),'Duty')
               else coalesce(d.classification,'Day Off - Pending Review') end classification,
          d.ot_policy,d.scheduled_start,coalesce(d.late_minutes,0) late_minutes,
          coalesce((select jsonb_agg(jsonb_build_object(
                     'session_no',x.session_no,'check_in_at',x.check_in_at,'check_out_at',x.check_out_at,
                     'check_in_verified',x.check_in_verified,'check_out_verified',x.check_out_verified)
                     order by x.session_no)
                    from public.attendance_live_sessions x
                    where x.staff_id=s.id and x.operational_date=g::date and coalesce(x.is_deleted,false)=false),'[]'::jsonb) sessions
        from public.staff s
        cross join generate_series(sd,ed,interval '1 day') g
        left join public.attendance_live_days d
          on d.staff_id=s.id and d.operational_date=g::date and coalesce(d.is_deleted,false)=false
        where (s.active=true or exists(select 1 from goya_private.staff_hr_profiles hp where hp.staff_id=s.id and hp.last_day is not null)) and goya_private.employed_on(s.id,g::date)
      ) q
    ),'[]'::jsonb)
  );
end $function$;
CREATE OR REPLACE FUNCTION public.attendance_live_management_month(p_key text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sd date:=date_trunc('month',p_month)::date;
  ed date:=(date_trunc('month',p_month)+interval '1 month - 1 day')::date;
  rules jsonb:=public.attendance_live_rules();
  today_local date:=timezone(coalesce(rules->>'timezone','Asia/Dubai'),now())::date;
  sys_start date:=coalesce((rules->>'system_start_date')::date,sd);
begin
  if not public.attendance_live_management_validate(p_key) then
    raise exception 'Invalid or expired management link';
  end if;
  sd:=greatest(sd,sys_start);
  ed:=least(ed,today_local);
  if ed<sd then return jsonb_build_object('server_now',now(),'rows','[]'::jsonb); end if;

  return jsonb_build_object(
    'server_now',now(),
    'rules',jsonb_build_object(
      'duty_presence_minutes',coalesce((rules->>'duty_presence_minutes')::int,540),
      'regular_net_minutes',coalesce((rules->>'regular_net_minutes')::int,480),
      'break_minutes',coalesce((rules->>'break_minutes')::int,60)
    ),
    'rows',coalesce((
      select jsonb_agg(to_jsonb(q) order by q.operational_date desc,q.staff_name)
      from (
        select g::date operational_date,s.id staff_id,s.name staff_name,
          coalesce(d.break_taken,true) break_taken,
          case when exists(select 1 from public.attendance_live_sessions sx
                           where sx.staff_id=s.id and sx.operational_date=g::date and coalesce(sx.is_deleted,false)=false)
               then coalesce(nullif(d.classification,'Day Off - Pending Review'),'Duty')
               else coalesce(d.classification,'Day Off - Pending Review') end classification,
          d.ot_policy,d.scheduled_start,coalesce(d.late_minutes,0) late_minutes,
          coalesce((select jsonb_agg(jsonb_build_object(
                     'session_no',x.session_no,'check_in_at',x.check_in_at,'check_out_at',x.check_out_at,
                     'check_in_verified',x.check_in_verified,'check_out_verified',x.check_out_verified)
                     order by x.session_no)
                    from public.attendance_live_sessions x
                    where x.staff_id=s.id and x.operational_date=g::date and coalesce(x.is_deleted,false)=false),'[]'::jsonb) sessions
        from public.staff s
        cross join generate_series(sd,ed,interval '1 day') g
        left join public.attendance_live_days d
          on d.staff_id=s.id and d.operational_date=g::date and coalesce(d.is_deleted,false)=false
        where (s.active=true or exists(select 1 from goya_private.staff_hr_profiles hp where hp.staff_id=s.id and hp.last_day is not null)) and goya_private.employed_on(s.id,g::date)
      ) q
    ),'[]'::jsonb)
  );
end $function$;
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
    'off_balances',public.goya_management_balances(p_token),'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'sections',s.sections,'eligible_days',(select jsonb_agg(goya_private.employed_on(s.id,p_week+i) order by i) from generate_series(0,6) i),'joining_date',hp.joining_date,'last_day',coalesce(hp.last_day,(select r.last_working_day from goya_private.staff_resignations r where r.staff_id=s.id and r.cancelled_at is null))) order by s.name,s.id)
      from public.staff s left join goya_private.staff_hr_profiles hp on hp.staff_id=s.id where (hp.joining_date is null or hp.joining_date<=p_week+6) and s.active and not exists(select 1 from goya_private.staff_resignations x where x.staff_id=s.id and x.cancelled_at is null and x.last_working_day<p_week)),'[]'::jsonb),
    'approved_leave',public.goya_hr_week_leave(p_token,p_week),
    'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.revision desc) from
      (select revision,published_at from goya_private.roster_publications where week_start=p_week order by revision desc limit 30) h),'[]'::jsonb)
  );
end $function$;
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
  if p_publish then
    for member in select * from jsonb_each(snapshot->'staff') loop
      for start_min in 0..6 loop
        if not goya_private.employed_on(member.key::uuid,p_week+start_min) then
          snapshot:=jsonb_set(snapshot,array['staff',member.key,start_min::text],'null'::jsonb);
        end if;
      end loop;
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
end $function$;
CREATE OR REPLACE FUNCTION public.goya_roster_my_week(p_token text, p_week date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_staff_id uuid;
begin
  v_staff_id := (public.require_session(p_token,false)).staff_id;
  if not exists(select 1 from public.staff s where s.id=v_staff_id and s.active) then
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
end $function$;
CREATE OR REPLACE FUNCTION public.goya_management_profiles(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.require_session(p_token,true);
 return coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'active',s.active,'sections',s.sections,'profile',to_jsonb(p),
 'off_balance',goya_private.off_snapshot(s.id),'resignation',to_jsonb(r),
 'history',coalesce((select jsonb_agg(to_jsonb(a) order by a.id desc) from goya_private.staff_hr_audit a where a.staff_id=s.id),'[]'::jsonb)) order by s.active desc,s.name)
 from public.staff s left join goya_private.staff_hr_profiles p on p.staff_id=s.id
 left join goya_private.staff_resignations r on r.staff_id=s.id),'[]'::jsonb);
end $function$;
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
begin
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
end $function$;
CREATE OR REPLACE FUNCTION public.staff_attendance_month_v12(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; sd date; ed date; a public.attendance_staff; rules jsonb;
begin
 sess:=public.require_session(p_token,false);
 select * into a from public.attendance_staff where portal_staff_id=sess.staff_id limit 1;
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
end $function$;
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
begin
  sess := public.require_session(p_token,false);
  select * into s from public.staff where id=sess.staff_id and active=true;
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
  on conflict(staff_id,operational_date) do update set
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
$function$;
CREATE OR REPLACE FUNCTION public.goya_management_report(p_token text, p_staff uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.require_session(p_token,true);
 return jsonb_build_object(
 'attendance',coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('sessions',coalesce((select jsonb_agg(jsonb_build_object('check_in_at',s.check_in_at,'check_out_at',s.check_out_at) order by s.check_in_at) from public.attendance_live_sessions s where s.staff_id=d.staff_id and s.operational_date=d.operational_date and not s.is_deleted),'[]'::jsonb)) order by d.operational_date desc) from public.attendance_live_days d where d.staff_id=p_staff and goya_private.employed_on(d.staff_id,d.operational_date) and not d.is_deleted),'[]'::jsonb),
 'rosters',coalesce((select jsonb_agg(jsonb_build_object('week',r.week_start,'revision',r.revision,'days',r.schedule->'staff'->p_staff::text) order by r.week_start desc,r.revision desc) from goya_private.roster_publications r where r.schedule->'staff' ? p_staff::text),'[]'::jsonb),
 'documents',coalesce((select jsonb_agg(jsonb_build_object('category',d.category,'title',d.custom_title,'file_name',d.file_name,'drive_file_id',d.drive_file_id,'uploaded_at',d.uploaded_at) order by d.uploaded_at desc) from goya_private.staff_document_versions d where d.staff_id=p_staff and d.uploaded_at is not null),'[]'::jsonb),
 'legacy_attendance',coalesce((select jsonb_agg(to_jsonb(a) order by a.operational_date desc) from public.attendance_records a join public.attendance_staff s on s.id=a.attendance_staff_id where s.portal_staff_id=p_staff and goya_private.employed_on(p_staff,a.operational_date)),'[]'::jsonb),
 'archive',coalesce((select jsonb_agg(to_jsonb(a) order by a.source_week desc,a.source_row) from goya_private.roster_excel_archive a where a.staff_id=p_staff),'[]'::jsonb),
 'annual_history',public.goya_hr_annual_history(p_token,p_staff));
end $function$;
CREATE OR REPLACE FUNCTION public.goya_hr_my_journey(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := (public.require_session(p_token,false)).staff_id;
begin
  if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized'; end if;
  return jsonb_build_object('profile',(select jsonb_build_object('joining_date',joining_date,'employee_code',employee_code,
    'position',position,'branch',branch,'mobile',mobile,'email',email,'address',address,'nationality',nationality,'date_of_birth',date_of_birth,'employment_type',employment_type,'probation_end',probation_end,'emergency_name',emergency_name,'emergency_relationship',emergency_relationship,'emergency_phone',emergency_phone) from goya_private.staff_hr_profiles where staff_id=employee),
    'archived_pending_off',(select jsonb_build_object('value',pending_off,'week',source_week)
      from goya_private.roster_excel_archive where staff_id=employee and pending_off<>'' order by source_week desc,source_row desc limit 1),
    'archived_annual_days',coalesce((select jsonb_agg(distinct item->>'date')
      from goya_private.roster_excel_archive a cross join lateral jsonb_array_elements(a.shifts) item
      where a.staff_id=employee and lower(btrim(item->>'value'))='annual leave'),'[]'::jsonb),
    'requests',coalesce((select jsonb_agg(to_jsonb(r)-'drive_file_id'-'staff_id' order by requested_from desc,created_at desc)
      from goya_private.staff_leave_requests r where r.staff_id=employee),'[]'::jsonb));
end $function$;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_classify_day(p_token text, p_staff_id uuid, p_date date, p_classification text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare oldv jsonb; newv public.attendance_live_days; begin
  perform public.require_session(p_token,true);
  if not goya_private.employed_on(p_staff_id,p_date) then raise exception 'The day is outside employment dates'; end if;
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
end $function$;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_manual_action(p_token text, p_staff_id uuid, p_action text, p_at timestamp with time zone, p_break_taken boolean DEFAULT true, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s public.staff; od date; action_name text:=upper(trim(coalesce(p_action,''))); active_count int:=0; next_no int:=1;
  r public.attendance_live_sessions; open_row public.attendance_live_sessions; d public.attendance_live_days; sh jsonb; before_row jsonb;
begin
  perform public.require_session(p_token,true);
  if p_at is null then raise exception 'Attendance date/time is required'; end if;
  select * into s from public.staff where id=p_staff_id;
  if s.id is null then raise exception 'Staff record not found'; end if;
  od:=public.attendance_live_operational_date(p_at);
  perform pg_advisory_xact_lock(hashtext(s.id::text));

  if action_name in ('CHECK_IN','REJOIN') and not goya_private.employed_on(s.id,od) then raise exception 'The day is outside employment dates'; end if;
  if action_name in ('CHECK_IN','REJOIN') then
    select * into open_row from public.attendance_live_sessions
      where staff_id=s.id and check_out_at is null and coalesce(is_deleted,false)=false order by check_in_at desc limit 1;
    if open_row.id is not null then raise exception 'Staff is already checked in'; end if;
    select count(*) into active_count from public.attendance_live_sessions
      where staff_id=s.id and operational_date=od and coalesce(is_deleted,false)=false;
    if action_name='REJOIN' and active_count=0 then raise exception 'No earlier session exists for Rejoin'; end if;
    if action_name='CHECK_IN' and active_count>0 then raise exception 'A session already exists for this operational day. Use Rejoin.'; end if;
    select coalesce(max(session_no),0)+1 into next_no from public.attendance_live_sessions where staff_id=s.id and operational_date=od;
    sh:=public.attendance_live_shift_info(p_at);
    insert into public.attendance_live_sessions(staff_id,operational_date,session_no,check_in_at,check_in_location_name,check_in_verified,is_deleted)
    values(s.id,od,next_no,p_at,'Admin',true,false) returning * into r;
    insert into public.attendance_live_days(staff_id,operational_date,break_taken,classification,scheduled_start,late_minutes,classification_note,is_deleted,deleted_at,deleted_reason)
    values(s.id,od,coalesce(p_break_taken,true),'Duty',nullif(sh->>'scheduled_start','')::time,case when active_count=0 then coalesce((sh->>'late_minutes')::int,0) else 0 end,nullif(trim(coalesce(p_note,'')),''),false,null,null)
    on conflict(staff_id,operational_date) do update set
      break_taken=excluded.break_taken,classification='Duty',is_deleted=false,deleted_at=null,deleted_reason=null,
      classification_note=coalesce(excluded.classification_note,public.attendance_live_days.classification_note),updated_at=now()
    returning * into d;
    perform public.attendance_live_recalculate_day_internal(s.id,od);
    select * into d from public.attendance_live_days where staff_id=s.id and operational_date=od;
    insert into public.attendance_live_audit(staff_id,operational_date,session_id,actor_type,action,after_data)
    values(s.id,od,r.id,'admin','MANUAL_'||action_name,jsonb_build_object('session',to_jsonb(r),'break_taken',p_break_taken,'note',p_note));

  elsif action_name='CHECK_OUT' then
    select * into open_row from public.attendance_live_sessions
      where staff_id=s.id and operational_date=od and check_out_at is null and coalesce(is_deleted,false)=false
      order by check_in_at desc limit 1;
    if open_row.id is null then raise exception 'No active Check In found for this staff on the selected date'; end if;
    if p_at<=open_row.check_in_at then raise exception 'Check Out must be after Check In'; end if;
    before_row:=to_jsonb(open_row);
    update public.attendance_live_sessions set
      check_out_at=p_at,check_out_location_name='Admin',check_out_verified=true,updated_at=now()
      where id=open_row.id returning * into r;
    update public.attendance_live_days set
      break_taken=coalesce(p_break_taken,true),classification='Duty',is_deleted=false,deleted_at=null,deleted_reason=null,
      classification_note=coalesce(nullif(trim(coalesce(p_note,'')),''),classification_note),updated_at=now()
      where staff_id=s.id and operational_date=od returning * into d;
    perform public.attendance_live_recalculate_day_internal(s.id,od);
    select * into d from public.attendance_live_days where staff_id=s.id and operational_date=od;
    insert into public.attendance_live_audit(staff_id,operational_date,session_id,actor_type,action,before_data,after_data)
    values(s.id,od,r.id,'admin','MANUAL_CHECK_OUT',before_row,jsonb_build_object('session',to_jsonb(r),'break_taken',p_break_taken,'note',p_note));
  else
    raise exception 'Invalid manual attendance action';
  end if;

  return jsonb_build_object('ok',true,'action',action_name,'session',to_jsonb(r),'day',to_jsonb(d),'server_now',now());
end $function$;
commit;
