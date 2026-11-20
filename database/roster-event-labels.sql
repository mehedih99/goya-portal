begin;
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
      if day ? 'label' and (day->>'kind'<>'Shift' or jsonb_typeof(day->'label') is distinct from 'string'
        or length(btrim(day->>'label')) not between 1 and 60 or day->>'label' ~ '[[:cntrl:]]') then
        raise exception 'Enter a custom shift name of 1–60 characters';
      end if;
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
commit;
