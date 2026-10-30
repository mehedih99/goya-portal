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
    'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'sections',s.sections,'active',s.active) order by s.name) from public.staff s where s.active=true),'[]'::jsonb),
    'days',coalesce((select jsonb_agg(to_jsonb(x)) from public.attendance_live_days x where x.operational_date=d and coalesce(x.is_deleted,false)=false),'[]'::jsonb),
    'sessions',coalesce((select jsonb_agg(to_jsonb(x) order by x.staff_id,x.session_no) from public.attendance_live_sessions x where x.operational_date=d and coalesce(x.is_deleted,false)=false),'[]'::jsonb)
  );
end $function$;

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
      select s.id staff_id,s.name staff_name,s.sections,g::date operational_date from public.staff s cross join generate_series(greatest(p_start,sys_start),e,interval '1 day') g where s.active=true and (p_staff_id is null or s.id=p_staff_id)
      union select s.id,s.name,s.sections,d.operational_date from public.staff s join public.attendance_live_days d on d.staff_id=s.id where s.active=true and (p_staff_id is null or s.id=p_staff_id) and d.operational_date between p_start and e and coalesce(d.is_deleted,false)=false
      union select s.id,s.name,s.sections,x.operational_date from public.staff s join public.attendance_live_sessions x on x.staff_id=s.id where s.active=true and (p_staff_id is null or s.id=p_staff_id) and x.operational_date between p_start and e and coalesce(x.is_deleted,false)=false
    )
    select jsonb_agg(to_jsonb(q) order by q.operational_date desc,q.staff_name) from (
      select b.operational_date,b.staff_id,b.staff_name,b.sections,coalesce(d.break_taken,true) break_taken,coalesce(d.split_shift_allowed,false) split_shift_allowed,
        case when exists(select 1 from public.attendance_live_sessions sx where sx.staff_id=b.staff_id and sx.operational_date=b.operational_date and coalesce(sx.is_deleted,false)=false)
             then coalesce(nullif(d.classification,'Day Off - Pending Review'),'Duty') else coalesce(d.classification,'Day Off - Pending Review') end classification,
        d.classification_note,d.scheduled_start,coalesce(d.late_minutes,0) late_minutes,
        coalesce((select jsonb_agg(to_jsonb(x) order by x.check_in_at,x.created_at) from public.attendance_live_sessions x
          where x.staff_id=b.staff_id and x.operational_date=b.operational_date and coalesce(x.is_deleted,false)=false),'[]'::jsonb) sessions
      from base b left join public.attendance_live_days d on d.staff_id=b.staff_id and d.operational_date=b.operational_date and coalesce(d.is_deleted,false)=false
    ) q
  ),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_live_admin_save_settings(p_token text, p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare oldv jsonb:=public.attendance_live_rules(); newv jsonb; begin
  perform public.require_session(p_token,true);
  newv:=oldv || coalesce(p_value,'{}'::jsonb);
  if coalesce((newv->>'duty_presence_minutes')::int,540)<60 then raise exception 'Duty minutes are invalid'; end if;
  if coalesce((newv->>'regular_net_minutes')::int,480)<60 then raise exception 'Regular net minutes are invalid'; end if;
  insert into public.attendance_settings(key,value,updated_at) values('live_rules',newv,now())
  on conflict(key) do update set value=excluded.value,updated_at=now();
  insert into public.attendance_live_audit(actor_type,action,before_data,after_data) values('admin','UPDATE_LIVE_SETTINGS',oldv,newv);
  return newv;
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
                      from public.staff s where s.active=true),'[]'::jsonb),
    'days',coalesce((select jsonb_agg(jsonb_build_object(
                       'staff_id',x.staff_id,'operational_date',x.operational_date,
                       'break_taken',x.break_taken,'classification',x.classification,
                       'scheduled_start',x.scheduled_start,'late_minutes',x.late_minutes))
                      from public.attendance_live_days x
                      where x.operational_date=d and coalesce(x.is_deleted,false)=false),'[]'::jsonb),
    'sessions',coalesce((select jsonb_agg(jsonb_build_object(
                           'id',x.id,'staff_id',x.staff_id,'operational_date',x.operational_date,
                           'session_no',x.session_no,'check_in_at',x.check_in_at,'check_out_at',x.check_out_at,
                           'check_in_verified',x.check_in_verified,'check_out_verified',x.check_out_verified)
                         order by x.staff_id,x.session_no)
                        from public.attendance_live_sessions x
                        where x.operational_date=d and coalesce(x.is_deleted,false)=false),'[]'::jsonb)
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
          d.scheduled_start,coalesce(d.late_minutes,0) late_minutes,
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
        where s.active=true
      ) q
    ),'[]'::jsonb)
  );
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_live_recalculate_day_internal(p_staff_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  first_in timestamptz;
  sh jsonb;
  d public.attendance_live_days;
begin
  select min(check_in_at) into first_in
  from public.attendance_live_sessions
  where staff_id=p_staff_id and operational_date=p_date and coalesce(is_deleted,false)=false;

  if first_in is null then
    update public.attendance_live_days
       set scheduled_start=null,
           late_minutes=0,
           updated_at=now()
     where staff_id=p_staff_id and operational_date=p_date
     returning * into d;
    return to_jsonb(d);
  end if;

  sh:=public.attendance_live_shift_info(first_in);
  insert into public.attendance_live_days(
    staff_id,operational_date,break_taken,classification,scheduled_start,late_minutes
  ) values(
    p_staff_id,p_date,true,'Duty',nullif(sh->>'scheduled_start','')::time,
    coalesce((sh->>'late_minutes')::int,0)
  )
  on conflict(staff_id,operational_date) do update set
    scheduled_start=excluded.scheduled_start,
    late_minutes=excluded.late_minutes,
    is_deleted=false,
    deleted_at=null,
    deleted_reason=null,
    updated_at=now()
  returning * into d;
  return to_jsonb(d);
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_live_rules()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    coalesce((select value from public.attendance_settings where key='live_rules'),'{}'::jsonb)
    || case
         when exists(
           select 1
           from public.attendance_settings a
           where a.key='rules'
             and jsonb_typeof(a.value)='object'
             and (a.value->>'operational_cutoff') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
         ) then jsonb_build_object(
           'operational_cutoff',
           (select a.value->>'operational_cutoff'
              from public.attendance_settings a
             where a.key='rules'
             limit 1)
         )
         else '{}'::jsonb
       end;
$function$;

CREATE OR REPLACE FUNCTION public.attendance_live_shift_info(p_ts timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rules jsonb:=public.attendance_live_rules();
  tz text:=coalesce(rules->>'timezone','Asia/Dubai');
  grace int:=coalesce((rules->>'late_grace_minutes')::int,15);
  shifts jsonb:=coalesce(rules->'shift_start_times',jsonb_build_array('08:00','09:00','10:00','11:00','12:00','13:00','14:00','15:00','16:00','17:00'));
  lt timestamp:=timezone(tz,p_ts);
  pm int:=extract(hour from lt)::int*60+extract(minute from lt)::int;
  sh text; sm int; dist int; best int:=null; best_dist int:=null; last_shift int:=null; late int:=0;
begin
  for sh in select jsonb_array_elements_text(shifts) loop
    begin
      sm:=split_part(sh,':',1)::int*60+split_part(sh,':',2)::int;
      if last_shift is null or sm>last_shift then last_shift:=sm; end if;
      dist:=abs(pm-sm);
      if best_dist is null or dist<best_dist or (dist=best_dist and sm>best) then best:=sm; best_dist:=dist; end if;
    exception when others then null;
    end;
  end loop;
  if best is null then return jsonb_build_object('scheduled_start',null,'late_minutes',0,'timing_review',true); end if;
  if last_shift is not null and pm>last_shift+60 then
    return jsonb_build_object('scheduled_start',null,'late_minutes',0,'timing_review',true);
  end if;
  if pm-best>grace then late:=pm-best; end if;
  return jsonb_build_object(
    'scheduled_start',lpad((best/60)::text,2,'0')||':'||lpad((best%60)::text,2,'0'),
    'late_minutes',late,
    'timing_review',false
  );
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
        d.classification_note,d.scheduled_start,coalesce(d.late_minutes,0) late_minutes,
        coalesce((select jsonb_agg(to_jsonb(x) order by x.check_in_at,x.created_at) from public.attendance_live_sessions x
          where x.staff_id=sess.staff_id and x.operational_date=z.operational_date and coalesce(x.is_deleted,false)=false),'[]'::jsonb) sessions
      from dates z left join public.attendance_live_days d on d.staff_id=sess.staff_id and d.operational_date=z.operational_date and coalesce(d.is_deleted,false)=false
    ) q
  ),'[]'::jsonb));
end $function$;

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
begin
  sess := public.require_session(p_token,false);
  select * into s from public.staff where id=sess.staff_id;

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
$function$;

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
                      from public.staff s where s.active=true),'[]'::jsonb),
    'days',coalesce((select jsonb_agg(jsonb_build_object(
                       'staff_id',x.staff_id,'operational_date',x.operational_date,
                       'break_taken',x.break_taken,'classification',x.classification,
                       'classification_note',x.classification_note,'scheduled_start',x.scheduled_start,
                       'late_minutes',x.late_minutes))
                      from public.attendance_live_days x
                      where x.operational_date=d and coalesce(x.is_deleted,false)=false),'[]'::jsonb),
    'sessions',coalesce((select jsonb_agg(jsonb_build_object(
                           'id',x.id,'staff_id',x.staff_id,'operational_date',x.operational_date,
                           'session_no',x.session_no,'check_in_at',x.check_in_at,'check_out_at',x.check_out_at,
                           'check_in_verified',x.check_in_verified,'check_out_verified',x.check_out_verified)
                         order by x.staff_id,x.session_no)
                        from public.attendance_live_sessions x
                        where x.operational_date=d and coalesce(x.is_deleted,false)=false),'[]'::jsonb)
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
          d.scheduled_start,coalesce(d.late_minutes,0) late_minutes,
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
        where s.active=true
      ) q
    ),'[]'::jsonb)
  );
end $function$;
