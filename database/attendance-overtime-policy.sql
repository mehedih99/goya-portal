-- No punches or historical totals are rewritten. Completed pre-rollout days keep legacy OT.
alter table public.attendance_live_days add column ot_policy jsonb;
create function goya_private.current_ot_policy() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('version',1,'enabled',coalesce((r->>'overtime_enabled')::boolean,true),'grace_minutes',30,'early_grace_minutes',30,'regular_minutes',coalesce((r->>'regular_net_minutes')::int,480),'break_minutes',coalesce((r->>'break_minutes')::int,60)) from (select public.attendance_live_rules() r)q;
$$;
revoke all on function goya_private.current_ot_policy() from public,anon,authenticated;
create function goya_private.capture_ot_policy() returns trigger language plpgsql security definer set search_path='' as $$
declare effective date:=nullif(public.attendance_live_rules()->>'ot_policy_effective_date','')::date;
begin
 if effective is null or new.operational_date<effective then return new;end if;
 if new.ot_policy is null then
  if tg_op='INSERT' or exists(select 1 from public.attendance_live_sessions s where s.staff_id=new.staff_id and s.operational_date=new.operational_date and s.check_out_at is null and not coalesce(s.is_deleted,false)) then new.ot_policy:=goya_private.current_ot_policy();end if;
 elsif exists(select 1 from public.attendance_live_sessions s where s.staff_id=new.staff_id and s.operational_date=new.operational_date and s.check_out_at is null and not coalesce(s.is_deleted,false)) then
  new.ot_policy:=new.ot_policy||jsonb_build_object('enabled',coalesce((public.attendance_live_rules()->>'overtime_enabled')::boolean,true));
 end if;
 return new;
end $$;
revoke all on function goya_private.capture_ot_policy() from public,anon,authenticated;
create trigger capture_goya_ot_policy before insert or update on public.attendance_live_days for each row execute function goya_private.capture_ot_policy();
-- Keep switch ON at rollout; company is currently paying OT.
insert into public.attendance_settings(key,value,updated_at) values('live_rules',public.attendance_live_rules()||jsonb_build_object('overtime_enabled',true,'ot_policy_effective_date',public.attendance_live_operational_date(now())),now())
on conflict(key) do update set value=excluded.value,updated_at=excluded.updated_at;
-- Apply the new rule to current open duties only; do not alter completed days.
update public.attendance_live_days d set ot_policy=goya_private.current_ot_policy()
 where d.operational_date>=public.attendance_live_operational_date(now()) and coalesce(d.is_deleted,false)=false
 and exists(select 1 from public.attendance_live_sessions s where s.staff_id=d.staff_id and s.operational_date=d.operational_date and s.check_out_at is null and not coalesce(s.is_deleted,false));
-- Reuse the audited Admin-only settings API. A toggle changes only policy on open duties.
do $$declare def text;fname text;begin
 def:=pg_get_functiondef('public.attendance_live_admin_save_settings(text,jsonb)'::regprocedure);
 if position('  newv:=oldv || coalesce(p_value,' in def)=0 then raise exception 'Settings API changed';end if;
 def:=replace(def,'  newv:=oldv || coalesce(p_value,',$patch$  if p_value ? 'overtime_enabled' and jsonb_typeof(p_value->'overtime_enabled')<>'boolean' then raise exception 'Overtime enabled must be true or false';end if;
  newv:=oldv || coalesce(p_value,$patch$);
 if position('  return newv;' in def)=0 then raise exception 'Settings return changed';end if;
 def:=replace(def,'  return newv;',$patch$  if (oldv->>'overtime_enabled') is distinct from (newv->>'overtime_enabled') then
   update public.attendance_live_days d set ot_policy=d.ot_policy||jsonb_build_object('enabled',coalesce((newv->>'overtime_enabled')::boolean,true))
    where d.ot_policy is not null and not coalesce(d.is_deleted,false) and exists(select 1 from public.attendance_live_sessions s where s.staff_id=d.staff_id and s.operational_date=d.operational_date and s.check_out_at is null and not coalesce(s.is_deleted,false));
  end if;
  return newv;$patch$);execute def;
 foreach fname in array array['staff_live_attendance_history(text,date)','attendance_live_admin_history(text,date,date,uuid)','attendance_live_public_month(date)','attendance_live_management_month(text,date)'] loop
  def:=pg_get_functiondef(('public.'||fname)::regprocedure);
  if position('d.scheduled_start,' in def)=0 then raise exception 'History API changed: %',fname;end if;
  def:=replace(def,'d.scheduled_start,','d.ot_policy,d.scheduled_start,');execute def;
 end loop;
 foreach fname in array array['attendance_live_public_dashboard(date)','attendance_live_management_dashboard(text,date)'] loop
  def:=pg_get_functiondef(('public.'||fname)::regprocedure);
  if position('''scheduled_start'',x.scheduled_start' in def)=0 then raise exception 'Dashboard API changed: %',fname;end if;
  def:=replace(def,'''scheduled_start'',x.scheduled_start','''ot_policy'',x.ot_policy,''scheduled_start'',x.scheduled_start');execute def;
 end loop;
end $$;
