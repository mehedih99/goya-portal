-- Optional roster feature. Existing attendance tables and functions are unchanged.
begin;

create table goya_private.roster_weeks (
  week_start date primary key check (extract(isodow from week_start)=1),
  draft jsonb not null,
  revision integer not null default 1,
  published_revision integer,
  check (jsonb_typeof(draft)='object' and octet_length(draft::text)<=262144)
);

create table goya_private.roster_publications (
  week_start date not null references goya_private.roster_weeks(week_start),
  revision integer not null,
  schedule jsonb not null,
  published_at timestamptz not null default now(),
  primary key (week_start,revision)
);

alter table goya_private.roster_weeks enable row level security;
alter table goya_private.roster_publications enable row level security;
revoke all on goya_private.roster_weeks,goya_private.roster_publications from public,anon,authenticated;

create function public.goya_roster_admin_week(p_token text,p_week date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  perform public.require_session(p_token,true);
  return jsonb_build_object(
    'draft',(select to_jsonb(w)||jsonb_build_object('published_staff',p.schedule->'staff')
      from goya_private.roster_weeks w left join goya_private.roster_publications p
      on p.week_start=w.week_start and p.revision=w.published_revision where w.week_start=p_week),
    'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name,s.id)
      from public.staff s where s.active),'[]'::jsonb),
    'approved_leave',public.goya_hr_week_leave(p_token,p_week),
    'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.revision desc) from
      (select revision,published_at from goya_private.roster_publications where week_start=p_week order by revision desc limit 30) h),'[]'::jsonb)
  );
end $$;

create function public.goya_roster_save(p_token text,p_week date,p_expected integer,p_schedule jsonb,p_publish boolean)
returns integer language plpgsql security definer set search_path='' as $$
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
      select r.staff_id::text as staff_id,r.kind,d as day_index
      from goya_private.staff_leave_requests r join public.staff s on s.id=r.staff_id and s.active
      cross join generate_series(0,6) as dates(d)
      where r.state='Approved' and p_week+d between r.approved_from and r.approved_to
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
end $$;

create function public.goya_roster_my_week(p_token text,p_week date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_staff_id uuid;
begin
  v_staff_id := (public.require_session(p_token,false)).staff_id;
  if not exists(select 1 from public.staff s where s.id=v_staff_id and s.active) then
    raise exception using message='Not authorized',errcode='28000';
  end if;
  return jsonb_build_object('week',(select jsonb_build_object(
      'days',p.schedule->'staff'->v_staff_id::text,'notes',p.schedule->>'notes','published_at',p.published_at)
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
end $$;

revoke execute on function public.goya_roster_admin_week(text,date),public.goya_roster_save(text,date,integer,jsonb,boolean),
  public.goya_roster_my_week(text,date) from public;
grant execute on function public.goya_roster_admin_week(text,date),public.goya_roster_save(text,date,integer,jsonb,boolean),
  public.goya_roster_my_week(text,date) to anon,authenticated;

commit;
