begin;
set local lock_timeout='5s';
create table goya_private.off_credit_batches(
 id uuid primary key,days integer not null check(days between 1 and 365),effective_on date not null,
 reason text not null,notice text not null,actor text not null,recipients uuid[] not null,
 created_at timestamptz not null default clock_timestamp(),reversed_at timestamptz,reversed_by text,reversal_reason text
);
create table goya_private.off_credit_members(
 batch_id uuid references goya_private.off_credit_batches(id) on delete restrict,
 staff_id uuid references public.staff(id) on delete restrict,applied_at timestamptz,primary key(batch_id,staff_id)
);
create table goya_private.roster_off_charges(
 staff_id uuid references public.staff(id) on delete restrict,off_date date not null,
 mode text not null check(mode in ('balance','advance')),charged boolean not null default true,
 revision integer not null,updated_at timestamptz not null default clock_timestamp(),primary key(staff_id,off_date)
);
create table goya_private.off_balance_events(
 id bigint generated always as identity primary key,staff_id uuid not null references public.staff(id) on delete restrict,
 delta integer not null,balance_after integer not null,effective_on date not null,source text not null,
 source_id text not null,notice text not null,actor text not null,created_at timestamptz not null default clock_timestamp()
);
alter table goya_private.off_credit_batches enable row level security;
alter table goya_private.off_credit_members enable row level security;
alter table goya_private.roster_off_charges enable row level security;
alter table goya_private.off_balance_events enable row level security;
revoke all on goya_private.off_credit_batches,goya_private.off_credit_members,goya_private.roster_off_charges,goya_private.off_balance_events from public,anon,authenticated;
create index off_balance_events_staff_time on goya_private.off_balance_events(staff_id,created_at desc,id desc);

create function goya_private.apply_off_credits(employee uuid) returns void language plpgsql security definer set search_path='' as $$
declare g record;b jsonb;next_balance integer;
begin
 perform 1 from public.staff where id=employee for update;
 for g in select c.id,c.days,c.effective_on,c.notice,c.actor from goya_private.off_credit_members m
 join goya_private.off_credit_batches c on c.id=m.batch_id where m.staff_id=employee and m.applied_at is null
 and c.reversed_at is null and c.effective_on<=(now() at time zone 'Asia/Dubai')::date order by c.effective_on,c.id for update of m loop
  b:=goya_private.off_snapshot(employee);next_balance:=(b->>'balance')::integer+g.days;
  insert into goya_private.staff_off_balances(staff_id,balance) values(employee,next_balance)
  on conflict(staff_id) do update set balance=excluded.balance,revision=staff_off_balances.revision+1,updated_at=clock_timestamp();
  update goya_private.off_credit_members set applied_at=clock_timestamp() where batch_id=g.id and staff_id=employee;
  insert into goya_private.off_balance_events(staff_id,delta,balance_after,effective_on,source,source_id,notice,actor)
  values(employee,g.days,next_balance,g.effective_on,'credit',g.id::text,g.notice,g.actor);
  insert into goya_private.staff_hr_audit(staff_id,event,details) values(employee,'Paid Off credited',jsonb_build_object('days',g.days,'before',b,'after',goya_private.off_snapshot(employee),'actor',g.actor,'batch',g.id));
 end loop;
end $$;
create function goya_private.apply_due_off_credits() returns void language plpgsql security definer set search_path='' as $$
declare employee uuid;begin
 for employee in select distinct m.staff_id from goya_private.off_credit_members m join goya_private.off_credit_batches c on c.id=m.batch_id
 where m.applied_at is null and c.reversed_at is null and c.effective_on<=(now() at time zone 'Asia/Dubai')::date order by m.staff_id loop perform goya_private.apply_off_credits(employee);end loop;
end $$;

create function public.goya_off_credit(p_token text,p_id uuid,p_staff uuid[],p_days integer,p_date date,p_reason text,p_notice text,p_actor text,p_expected jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare employee uuid;b jsonb;prior goya_private.off_credit_batches;ids uuid[];
begin
 perform public.require_session(p_token,true);
 select array_agg(distinct x order by x) into ids from unnest(p_staff)x;
 if p_id is null or ids is null or cardinality(ids) not between 1 and 500 or p_days is null or p_days not between 1 and 365
 or p_date is null or p_date not between (now() at time zone 'Asia/Dubai')::date-365 and (now() at time zone 'Asia/Dubai')::date+730
 or length(btrim(coalesce(p_actor,''))) not between 1 and 100 or length(btrim(coalesce(p_reason,''))) not between 1 and 500
 or length(btrim(coalesce(p_notice,''))) not between 1 and 1000 then raise exception 'Enter staff, days, effective date, reason, staff notice and management name';end if;
 -- Stable request identity prevents repeat credits after response loss or double-clicks.
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,0));
 select * into prior from goya_private.off_credit_batches where id=p_id;
 if found then
  if prior.recipients is distinct from ids or prior.days<>p_days or prior.effective_on<>p_date or prior.reason<>btrim(p_reason) or prior.notice<>btrim(p_notice) or prior.actor<>btrim(p_actor) then raise exception 'Submission reference already used for different details';end if;
  return jsonb_build_object('id',p_id,'saved',true);
 end if;
 perform 1 from public.staff where id=any(ids) order by id for update;
 foreach employee in array ids loop
  if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Selected staff changed or is inactive. Reload.';end if;
  perform goya_private.apply_off_credits(employee);b:=goya_private.off_snapshot(employee);
  if (p_expected->>employee::text)::integer is distinct from (b->>'revision')::integer then raise exception 'A balance changed. Reopen the preview before applying.';end if;
 end loop;
 insert into goya_private.off_credit_batches(id,days,effective_on,reason,notice,actor,recipients) values(p_id,p_days,p_date,btrim(p_reason),btrim(p_notice),btrim(p_actor),ids);
 insert into goya_private.off_credit_members(batch_id,staff_id) select p_id,x from unnest(ids)x;
 foreach employee in array ids loop perform goya_private.apply_off_credits(employee);end loop;
 return jsonb_build_object('id',p_id,'saved',true);
end $$;

create function public.goya_off_credit_history(p_token text) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin perform public.require_session(p_token,true);
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from
 (select c.*,coalesce((select jsonb_agg(jsonb_build_object('name',s.name,'applied_at',m.applied_at) order by s.name) from goya_private.off_credit_members m join public.staff s on s.id=m.staff_id where m.batch_id=c.id),'[]'::jsonb) members
 from goya_private.off_credit_batches c order by created_at desc limit 100)q),'[]'::jsonb);
end $$;

create function public.goya_off_reverse_credit(p_token text,p_id uuid,p_actor text,p_reason text) returns void language plpgsql security definer set search_path='' as $$
declare c goya_private.off_credit_batches;m record;b jsonb;begin
 perform public.require_session(p_token,true);
 if length(btrim(coalesce(p_actor,''))) not between 1 and 100 or length(btrim(coalesce(p_reason,''))) not between 1 and 500 then raise exception 'Enter management name and correction reason';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,0));select * into c from goya_private.off_credit_batches where id=p_id;
 if not found then raise exception 'Credit not found';end if;if c.reversed_at is not null then return;end if;
 perform 1 from public.staff where id=any(c.recipients) order by id for update;
 for m in select * from goya_private.off_credit_members where batch_id=p_id and applied_at is not null order by staff_id loop
 b:=goya_private.off_snapshot(m.staff_id);
 perform public.goya_management_save_balance(p_token,m.staff_id,(b->>'balance')::integer-c.days,(b->>'revision')::integer,'Bulk credit correction: '||p_reason,p_actor);
 insert into goya_private.off_balance_events(staff_id,delta,balance_after,effective_on,source,source_id,notice,actor)
 values(m.staff_id,-c.days,(b->>'balance')::integer-c.days,(now() at time zone 'Asia/Dubai')::date,'correction',p_id::text,'Paid Off credit corrected: '||p_reason,p_actor);
 end loop;
 update goya_private.off_credit_batches set reversed_at=clock_timestamp(),reversed_by=p_actor,reversal_reason=p_reason where id=p_id;
end $$;

create function goya_private.reconcile_roster_off(p_token text,p_week date,p_snapshot jsonb,p_revision integer,p_actor text) returns void
language plpgsql security definer set search_path='' as $$
declare employee uuid;b jsonb;day_index integer;d date;want text;old goya_private.roster_off_charges;
 refunds integer;debits integer;normal_debits integer;next_balance integer;changes jsonb;
begin
 for employee in select id from public.staff where id::text in(select key from jsonb_each(p_snapshot->'staff'))
 or id in(select staff_id from goya_private.roster_off_charges where off_date between p_week and p_week+6 and charged) order by id loop
  perform goya_private.apply_off_credits(employee);b:=goya_private.off_snapshot(employee);refunds:=0;debits:=0;normal_debits:=0;changes:='[]';
  for day_index in 0..6 loop
   d:=p_week+day_index;want:=p_snapshot->'staff'->employee::text->day_index->>'off_source';
   select * into old from goya_private.roster_off_charges where staff_id=employee and off_date=d;
   if want in ('balance','advance') and not coalesce(old.charged,false) then
    debits:=debits+1;if want='balance' then normal_debits:=normal_debits+1;end if;
    changes:=changes||jsonb_build_array(jsonb_build_object('date',d,'delta',-1,'mode',want));
   elsif coalesce(old.charged,false) and (want is null or want not in ('balance','advance')) then
    refunds:=refunds+1;changes:=changes||jsonb_build_array(jsonb_build_object('date',d,'delta',1,'mode',old.mode));
   end if;
  end loop;
  if debits+refunds>0 then
   if length(btrim(coalesce(p_actor,''))) not between 1 and 100 then raise exception 'Management name is required for Paid Off publication';end if;
   if normal_debits>0 and (b->>'balance')::integer+refunds<normal_debits then raise exception 'Insufficient Paid Off balance. Choose Advance Off explicitly or correct the balance.';end if;
   next_balance:=(b->>'balance')::integer+refunds-debits;
   perform public.goya_management_save_balance(p_token,employee,next_balance,(b->>'revision')::integer,'Published Paid Off adjustment for week '||p_week,p_actor);
   for day_index in 0..jsonb_array_length(changes)-1 loop
    d:=(changes->day_index->>'date')::date;
    insert into goya_private.roster_off_charges(staff_id,off_date,mode,charged,revision)
    values(employee,d,changes->day_index->>'mode',(changes->day_index->>'delta')::integer=-1,p_revision)
    on conflict(staff_id,off_date) do update set mode=excluded.mode,charged=excluded.charged,revision=excluded.revision,updated_at=clock_timestamp();
    insert into goya_private.off_balance_events(staff_id,delta,balance_after,effective_on,source,source_id,notice,actor)
    values(employee,(changes->day_index->>'delta')::integer,next_balance,d,'roster',p_week::text,
     case when (changes->day_index->>'delta')::integer=-1 then 'Paid Off used for ' else 'Paid Off returned for ' end||d::text,p_actor);
   end loop;
  end if;
 end loop;
end $$;

create function goya_private.release_roster_off(p_token text,p_staff uuid,p_from date,p_to date,p_actor text) returns void
language plpgsql security definer set search_path='' as $$
declare n integer;b jsonb;r record;begin
 select count(*) into n from goya_private.roster_off_charges where staff_id=p_staff and charged and off_date between p_from and p_to;
 if n=0 then return;end if;b:=goya_private.off_snapshot(p_staff);
 perform public.goya_management_save_balance(p_token,p_staff,(b->>'balance')::integer+n,(b->>'revision')::integer,'Paid Off transferred to approved request',p_actor);
 for r in update goya_private.roster_off_charges set charged=false,updated_at=clock_timestamp() where staff_id=p_staff and charged and off_date between p_from and p_to returning off_date loop
 insert into goya_private.off_balance_events(staff_id,delta,balance_after,effective_on,source,source_id,notice,actor)
 values(p_staff,1,(b->>'balance')::integer+n,r.off_date,'request-transfer',r.off_date::text,'Roster Paid Off returned before applying approved leave',p_actor);
 end loop;
end $$;

create function public.goya_off_roster_preview(p_token text,p_week date,p_schedule jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb:='[]';employee record;b jsonb;debits int;refunds int;normal_debits int;begin
 perform public.require_session(p_token,true);
 for employee in select id,name from public.staff where id::text in(select key from jsonb_each(p_schedule->'staff')) or id in(select staff_id from goya_private.roster_off_charges where charged and off_date between p_week and p_week+6) order by id loop
  b:=goya_private.off_snapshot(employee.id);
  select count(*) filter(where want in ('balance','advance') and not charged),count(*) filter(where charged and (want is null or want not in ('balance','advance'))),count(*) filter(where want='balance' and not charged)
  into debits,refunds,normal_debits from (select p_schedule->'staff'->employee.id::text->d->>'off_source' want,coalesce(c.charged,false) charged from generate_series(0,6)d left join goya_private.roster_off_charges c on c.staff_id=employee.id and c.off_date=p_week+d)q;
  result:=result||jsonb_build_array(jsonb_build_object('id',employee.id,'name',employee.name,'balance',(b->>'balance')::int,'debit',debits,'refund',refunds,'projected',(b->>'balance')::int+refunds-debits,'insufficient',normal_debits>0 and (b->>'balance')::int+refunds<normal_debits));
 end loop;return result;
end $$;
revoke all on function public.goya_off_roster_preview(text,date,jsonb) from public;
grant execute on function public.goya_off_roster_preview(text,date,jsonb) to anon,authenticated;

create function public.goya_off_my_events(p_token text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare employee uuid:=(public.require_session(p_token,false)).staff_id;begin
 if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized';end if;
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.id desc) from
 (select id,delta,balance_after,effective_on,notice,created_at,'Management'::text approved_by from goya_private.off_balance_events where staff_id=employee order by id desc limit 100)q),'[]'::jsonb);
end $$;

revoke all on function goya_private.apply_off_credits(uuid),goya_private.apply_due_off_credits(),goya_private.reconcile_roster_off(text,date,jsonb,integer,text),goya_private.release_roster_off(text,uuid,date,date,text) from public,anon,authenticated;
revoke all on function public.goya_off_credit(text,uuid,uuid[],integer,date,text,text,text,jsonb),public.goya_off_credit_history(text),public.goya_off_reverse_credit(text,uuid,text,text),public.goya_off_my_events(text) from public;
grant execute on function public.goya_off_credit(text,uuid,uuid[],integer,date,text,text,text,jsonb),public.goya_off_credit_history(text),public.goya_off_reverse_credit(text,uuid,text,text),public.goya_off_my_events(text) to anon,authenticated;

CREATE OR REPLACE FUNCTION public.goya_management_save_balance(p_token text, p_staff uuid, p_value integer, p_expected integer, p_reason text, p_actor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare prior jsonb; result jsonb;
begin
 perform public.require_session(p_token,true);
 if length(btrim(coalesce(p_actor,''))) not between 1 and 100 or length(btrim(coalesce(p_reason,''))) not between 1 and 2000
  or p_value is null or p_value not between -36500 and 36500 then raise exception 'Enter management name, reason and a valid balance'; end if;
 perform 1 from public.staff where id=p_staff for update;
 if not found then raise exception 'Staff not found'; end if;
 perform goya_private.apply_off_credits(p_staff);
 prior:=goya_private.off_snapshot(p_staff);
 if (prior->>'revision')::integer is distinct from p_expected then raise exception 'Balance changed. Reload before saving.'; end if;
 insert into goya_private.staff_off_balances(staff_id,balance) values(p_staff,p_value)
 on conflict(staff_id) do update set balance=excluded.balance,revision=staff_off_balances.revision+1,updated_at=clock_timestamp()
 returning to_jsonb(staff_off_balances) into result;
 insert into goya_private.staff_hr_audit(staff_id,event,details) values(p_staff,'Off balance changed',
 jsonb_build_object('before',prior,'after',result,'reason',p_reason,'actor',p_actor,'session_ref',md5(p_token)));
 return result;
end $function$
;
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
 if p_state='Approved' and prior.kind<>'Resignation' then
  perform goya_private.apply_off_credits(prior.staff_id);
  perform goya_private.release_roster_off(p_token,prior.staff_id,p_from,p_to,p_actor);
 end if;
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
CREATE OR REPLACE FUNCTION public.goya_hr_week_leave(p_token text, p_week date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.require_session(p_token,true);
  return coalesce((select jsonb_agg(jsonb_build_object('id',id,'staff_id',staff_id,'kind',case when kind in ('Pending Off','Advance Off') then 'Weekly Off' when kind='Emergency Leave' then 'Other Leave' else kind end,
    'from',approved_from,'to',approved_to,'paid_request',kind in ('Pending Off','Advance Off')))
    from goya_private.staff_leave_requests where kind<>'Resignation' and state='Approved' and approved_from<=p_week+6 and approved_to>=p_week),'[]'::jsonb);
end $function$
;
CREATE OR REPLACE FUNCTION public.goya_roster_save(p_token text, p_week date, p_expected integer, p_schedule jsonb, p_publish boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare next_revision integer; member record; day jsonb; segment jsonb; previous_end integer; start_min integer; end_min integer;
  snapshot jsonb; leave_day record; approval_actor text;
begin
  perform public.require_session(p_token,true);
  approval_actor:=p_schedule->>'approval_actor';p_schedule:=p_schedule-'approval_actor';
  if p_publish then
   perform 1 from public.staff where id::text in(select key from jsonb_each(p_schedule->'staff'))
    or id in(select staff_id from goya_private.roster_off_charges where charged and off_date between p_week and p_week+6) order by id for update;
  end if;
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
      if day ? 'off_source' and (day->>'kind'<>'Weekly Off' or coalesce(day->>'off_source','') not in ('balance','advance')) then raise exception 'Invalid Paid Off source';end if;
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
      select r.staff_id::text as staff_id,case when r.kind in ('Pending Off','Advance Off') then 'Weekly Off' when r.kind='Emergency Leave' then 'Other Leave' else r.kind end as kind,r.kind as request_kind,d as day_index
      from goya_private.staff_leave_requests r join public.staff s on s.id=r.staff_id and s.active
      cross join generate_series(0,6) as dates(d)
      where r.kind<>'Resignation' and r.state='Approved' and p_week+d between r.approved_from and r.approved_to
      order by r.staff_id,d
    loop
      if not ((snapshot->'staff') ? leave_day.staff_id) then
        snapshot := jsonb_set(snapshot,array['staff',leave_day.staff_id],'[null,null,null,null,null,null,null]');
      end if;
      snapshot := jsonb_set(snapshot,array['staff',leave_day.staff_id,leave_day.day_index::text],
        jsonb_build_object('kind',leave_day.kind,'segments','[]'::jsonb,'note','')||case when leave_day.request_kind in ('Pending Off','Advance Off') then jsonb_build_object('off_source','request') else '{}'::jsonb end);
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
    perform goya_private.reconcile_roster_off(p_token,p_week,snapshot,next_revision,approval_actor);
    insert into goya_private.roster_publications(week_start,revision,schedule) values(p_week,next_revision,snapshot);
    update goya_private.roster_weeks set published_revision=next_revision where week_start=p_week;
  end if;
  return next_revision;
end $function$
;
select cron.schedule('goya-paid-off-credits','* * * * *','select goya_private.apply_due_off_credits()');
commit;
