-- Reuse the existing staff-visible review_note; private notes remain private.
CREATE OR REPLACE FUNCTION public.goya_management_review(p_token text, p_id uuid, p_expected timestamp with time zone, p_state text, p_from date, p_to date, p_payroll text, p_note text, p_actor text, p_private_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare prior goya_private.staff_leave_requests; after_row goya_private.staff_leave_requests;
 old_days integer:=0; new_days integer:=0; balance jsonb; plan goya_private.staff_resignations;
begin
 perform public.require_session(p_token,true);
 if length(btrim(coalesce(p_actor,''))) not between 1 and 100 or length(coalesce(p_private_note,''))>2000
  or length(coalesce(p_note,''))>2000
  or (p_state='Declined' and length(btrim(coalesce(p_note,'')))=0) then raise exception 'Management name and a staff-visible rejection reason are required (maximum 2000 characters)'; end if;
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
end $function$
;
