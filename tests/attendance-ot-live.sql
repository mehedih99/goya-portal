-- Only disposable fixtures; rollback also undoes temporary switches on real open-day policies.
begin;
do $$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();ta text:='qa-ot-'||gen_random_uuid();tb text:='qa-ot-'||gen_random_uuid();ad text:='qa-ot-'||gen_random_uuid();od date:=public.attendance_live_operational_date(now());r jsonb;d jsonb;original_out timestamptz;denied boolean:=false;
begin
 insert into public.staff(id,name,pin_hash,active) values(a,'QA closed OT','not-a-login-hash',true),(b,'QA open OT','not-a-login-hash',true);
 insert into public.app_sessions(token,staff_id,is_admin,expires_at) values(ta,a,false,now()+interval '5 minutes'),(tb,b,false,now()+interval '5 minutes'),(ad,null,true,now()+interval '5 minutes');
 insert into public.attendance_live_days(staff_id,operational_date,break_taken) values(a,od,false),(a,od-1,false),(b,od,false);
 insert into public.attendance_live_sessions(staff_id,operational_date,session_no,check_in_at,check_out_at) values(a,od,1,(od+time '08:00') at time zone 'Asia/Dubai',(od+time '16:31') at time zone 'Asia/Dubai'),(b,od,1,now()-interval '1 hour',null);
 select check_out_at into original_out from public.attendance_live_sessions where staff_id=a and operational_date=od;
 r:=public.attendance_live_admin_save_settings(ad,'{"overtime_enabled":false}');assert (r->>'overtime_enabled')::boolean=false;
 assert (select (ot_policy->>'enabled')::boolean=false from public.attendance_live_days where staff_id=b and operational_date=od);
 assert (select (ot_policy->>'enabled')::boolean=true from public.attendance_live_days where staff_id=a and operational_date=od),'Closed duty changed';
 assert (select ot_policy is null from public.attendance_live_days where staff_id=a and operational_date=od-1),'Pre-policy day changed';
 r:=public.attendance_live_admin_history(ad,od,od,b);assert (r->'rows'->0->'ot_policy'->>'enabled')::boolean=false;
 r:=public.staff_live_attendance_history(tb,od);assert exists(select 1 from jsonb_array_elements(r->'rows')q where q->>'operational_date'=od::text and (q->'ot_policy'->>'enabled')::boolean=false);
 update public.attendance_live_sessions set check_out_at=now() where staff_id=b;
 perform public.attendance_live_admin_save_settings(ad,'{"overtime_enabled":true}');
 assert (select (ot_policy->>'enabled')::boolean=false from public.attendance_live_days where staff_id=b and operational_date=od),'Completed disabled day changed after enabling';
 insert into public.attendance_live_days(staff_id,operational_date) values(b,od+1);
 assert (select (ot_policy->>'enabled')::boolean=true from public.attendance_live_days where staff_id=b and operational_date=od+1);
 begin perform public.attendance_live_admin_save_settings(ta,'{"overtime_enabled":false}');exception when others then denied:=true;end;assert denied,'Staff changed Admin OT switch';
 assert (select check_out_at=original_out from public.attendance_live_sessions where staff_id=a and operational_date=od),'Raw checkout changed';
 assert not has_function_privilege('anon','goya_private.current_ot_policy()','execute');
end $$;
rollback;
select 'PASS live OT: snapshots, immediate Off for open duty, closed/history preservation, API payloads, future On, permission guard, unchanged punches; all fixtures rolled back' result;
