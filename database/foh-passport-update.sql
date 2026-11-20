begin;
alter table goya_private.staff_hr_profiles add column roster_group text not null default ''
  constraint staff_hr_roster_group_check check (roster_group in ('','FOH','BOH'));
alter table goya_private.staff_document_versions drop constraint staff_document_versions_category_check;
alter table goya_private.staff_document_versions add constraint staff_document_versions_category_check CHECK ((((category = ANY (ARRAY['emirates-id'::text, 'passport'::text, 'contract'::text, 'food-safety'::text, 'health-card'::text, 'work-permit'::text, 'residence-visa'::text, 'health-insurance'::text, 'pic-certificate'::text, 'occupational-health-card'::text, 'noc'::text, 'profile-photo'::text])) AND (custom_title IS NULL)) OR ((category ~ '^custom-[a-f0-9-]{36}$'::text) AND (custom_title IS NOT NULL) AND ((length(btrim(custom_title)) >= 1) AND (length(btrim(custom_title)) <= 100)))));
CREATE OR REPLACE FUNCTION public.goya_people_save_staff(p_token text, p_row jsonb, p_profile jsonb, p_expected timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 update goya_private.staff_hr_profiles set roster_group=coalesce(p_profile->>'roster_group',roster_group),mobile=left(coalesce(p_profile->>'mobile',mobile),60),email=left(coalesce(p_profile->>'email',email),254),address=left(coalesce(p_profile->>'address',address),1000),
 nationality=left(coalesce(p_profile->>'nationality',nationality),100),date_of_birth=nullif(p_profile->>'date_of_birth','')::date,
 employment_type=left(coalesce(p_profile->>'employment_type',employment_type),80),probation_end=nullif(p_profile->>'probation_end','')::date,
 emergency_name=left(coalesce(p_profile->>'emergency_name',emergency_name),120),emergency_relationship=left(coalesce(p_profile->>'emergency_relationship',emergency_relationship),80),
 emergency_phone=left(coalesce(p_profile->>'emergency_phone',emergency_phone),60) where staff_id=employee;
 return jsonb_build_object('id',employee,'profile',(select to_jsonb(p) from goya_private.staff_hr_profiles p where p.staff_id=employee));
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
    'off_balances',public.goya_management_balances(p_token),'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'sections',s.sections,'roster_group',hp.roster_group,'eligible_days',(select jsonb_agg(goya_private.employed_on(s.id,p_week+i) order by i) from generate_series(0,6) i),'joining_date',hp.joining_date,'last_day',coalesce(hp.last_day,(select r.last_working_day from goya_private.staff_resignations r where r.staff_id=s.id and r.cancelled_at is null))) order by s.name,s.id)
      from public.staff s left join goya_private.staff_hr_profiles hp on hp.staff_id=s.id where (hp.joining_date is null or hp.joining_date<=p_week+6) and s.active and not exists(select 1 from goya_private.staff_resignations x where x.staff_id=s.id and x.cancelled_at is null and x.last_working_day<p_week)),'[]'::jsonb),
    'approved_leave',public.goya_hr_week_leave(p_token,p_week),
    'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.revision desc) from
      (select revision,published_at from goya_private.roster_publications where week_start=p_week order by revision desc limit 30) h),'[]'::jsonb)
  );
end $function$;
commit;
