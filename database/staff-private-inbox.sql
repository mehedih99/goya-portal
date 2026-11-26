begin;
set local lock_timeout='5s';
create table goya_private.staff_notifications(
 id bigint generated always as identity primary key,staff_id uuid not null references public.staff(id) on delete restrict,
 event_key text not null,kind text not null,title text not null,body text not null,target jsonb not null default '{}',
 created_at timestamptz not null default clock_timestamp(),read_at timestamptz,unique(staff_id,event_key)
);
create index staff_notifications_staff_id_desc on goya_private.staff_notifications(staff_id,id desc);
create index staff_notifications_unread on goya_private.staff_notifications(staff_id,id) where read_at is null;
create index staff_notifications_request_target on goya_private.staff_notifications(staff_id,(target->>'id')) where kind='request';
create table goya_private.staff_appearance(
 staff_id uuid primary key references public.staff(id) on delete restrict,
 preferences jsonb not null default '{"mode":"auto","accent":"default","text_size":"normal"}',
 revision integer not null default 1,updated_at timestamptz not null default clock_timestamp()
);
alter table goya_private.staff_notifications enable row level security;
alter table goya_private.staff_appearance enable row level security;
revoke all on goya_private.staff_notifications,goya_private.staff_appearance from public,anon,authenticated;

create function goya_private.staff_notice_emit(employee uuid,event_key text,kind text,title text,body text,target jsonb,at_time timestamptz default clock_timestamp()) returns void
language sql security definer set search_path='' as $$
 insert into goya_private.staff_notifications(staff_id,event_key,kind,title,body,target,created_at)
 select employee,event_key,kind,left(title,250),left(body,4000),target,at_time
 where exists(select 1 from public.staff where id=employee)
 and not exists(select 1 from goya_private.staff_notifications n where n.staff_id=$1 and n.event_key=$2)
 on conflict(staff_id,event_key) do nothing;
$$;

create function goya_private.staff_notice_request(r goya_private.staff_leave_requests) returns void
language plpgsql security definer set search_path='' as $$begin
 if r.state not in ('Approved','Declined') then return;end if;
 perform goya_private.staff_notice_emit(r.staff_id,'request:'||r.id||':'||extract(epoch from r.updated_at)::text,'request',r.kind||case when r.state='Declined' then ' — Rejected' else ' — Approved' end,
 coalesce(r.approved_from,r.requested_from)::text||' to '||coalesce(r.approved_to,r.requested_to)::text||case when coalesce(r.review_note,'')<>'' then E'\n'||r.review_note else '' end||E'\nManagement',
 jsonb_build_object('view','request','id',r.id),r.updated_at);
end $$;
create function goya_private.staff_notice_off(r goya_private.off_balance_events) returns void
language plpgsql security definer set search_path='' as $$begin
 perform goya_private.staff_notice_emit(r.staff_id,'off:'||r.id,'balance',case when r.delta>0 then '+' else '' end||r.delta||' Paid Off day(s)',
 r.notice||E'\nBalance after update: '||r.balance_after||E'\nManagement',jsonb_build_object('view','balance','id',r.id),r.created_at);
end $$;
create function goya_private.staff_notice_day(d jsonb) returns text language sql immutable set search_path='' as $$
 select case when d is null or d='null'::jsonb then 'Not scheduled'
 when d->>'off_source'='advance' then 'Advance Off' when d ? 'off_source' then 'Paid Off'
 when d->>'kind'='Shift' then coalesce(nullif(d->>'label','')||' | ','')||coalesce((select string_agg(s->>'start'||'–'||(s->>'end')||case when s->>'end'<s->>'start' then ' (+1 day)' else '' end,' / ' order by i) from jsonb_array_elements(d->'segments') with ordinality t(s,i)),'Shift')
 else coalesce(d->>'kind','Not scheduled') end;
$$;

create function goya_private.staff_notice_events() returns trigger language plpgsql security definer set search_path='' as $$
declare previous jsonb;member record;i integer;before_day jsonb;after_day jsonb;before_value jsonb;after_value jsonb;label text;details text;request_row goya_private.staff_leave_requests;off_row goya_private.off_balance_events;
begin
 if tg_table_name='staff_leave_requests' then
  request_row:=new;
  if tg_op='INSERT' then perform goya_private.staff_notice_request(request_row);
  elsif (new.state,new.approved_from,new.approved_to,new.review_note) is distinct from (old.state,old.approved_from,old.approved_to,old.review_note) then perform goya_private.staff_notice_request(request_row);end if;
 elsif tg_table_name='off_balance_events' then off_row:=new;perform goya_private.staff_notice_off(off_row);
 elsif tg_table_name='staff_document_versions' then
  if new.uploaded_at is null then return new;end if;
  if tg_op='UPDATE' then if old.uploaded_at is not null then return new;end if;end if;
  label:=coalesce(nullif(new.custom_title,''),initcap(replace(new.category,'-',' ')));
  perform goya_private.staff_notice_emit(new.staff_id,'upload:'||new.id,'document','Document available: '||label,'A current version of your '||label||' is available in My Journey.',jsonb_build_object('view','document','id',new.id,'category',new.category),new.uploaded_at);
 elsif tg_table_name='roster_publications' then
  select schedule into previous from goya_private.roster_publications where week_start=new.week_start and revision<new.revision order by revision desc limit 1;
  for member in select s.id from public.staff s where s.active and (new.schedule->'staff' ? s.id::text or previous->'staff' ? s.id::text) loop
   for i in 0..6 loop
    if not goya_private.employed_on(member.id,new.week_start+i) then continue;end if;
    before_day:=previous->'staff'->member.id::text->i;after_day:=new.schedule->'staff'->member.id::text->i;
    if coalesce(before_day,'null') is not distinct from coalesce(after_day,'null') then continue;end if;
    perform goya_private.staff_notice_emit(member.id,'roster:'||new.week_start||':'||new.revision||':'||i,'roster',case when previous is null then 'Your schedule published' else 'Your schedule changed' end||' · '||(new.week_start+i)::text,
     'Before: '||goya_private.staff_notice_day(before_day)||E'\nNow: '||goya_private.staff_notice_day(after_day)||case when coalesce(after_day->>'note','')<>'' then E'\n'||(after_day->>'note') else '' end||E'\nManagement',
     jsonb_build_object('view','roster','week',new.week_start,'date',new.week_start+i),new.published_at);
   end loop;
  end loop;
 elsif tg_table_name='attendance_live_audit' and new.actor_type='admin' then
  before_value:=coalesce(new.before_data->'session',new.before_data,'{}');after_value:=coalesce(new.after_data->'session',new.after_data,'{}');
  details:='Date: '||new.operational_date::text;
  foreach label in array array['check_in_at','check_out_at','classification','break_taken','is_deleted'] loop
   if before_value->label is distinct from after_value->label then
    details:=details||E'\n'||initcap(replace(label,'_',' '))||': '||coalesce(before_value->>label,'—')||' → '||coalesce(after_value->>label,'—');
   end if;
  end loop;
  perform goya_private.staff_notice_emit(new.staff_id,'attendance:'||new.id,'attendance','Attendance updated by Management',details||E'\nManagement',jsonb_build_object('view','attendance','date',new.operational_date),new.created_at);
 end if;
 return new;
exception when others then
 -- Notification failure must never cancel attendance, uploads, requests or publishing.
 raise warning 'Staff notification unavailable (SQLSTATE %)',sqlstate;return new;
end $$;
create trigger staff_notice_request after insert or update on goya_private.staff_leave_requests for each row execute function goya_private.staff_notice_events();
create trigger staff_notice_off after insert on goya_private.off_balance_events for each row execute function goya_private.staff_notice_events();
create trigger staff_notice_document after insert or update on goya_private.staff_document_versions for each row execute function goya_private.staff_notice_events();
create trigger staff_notice_roster after insert on goya_private.roster_publications for each row execute function goya_private.staff_notice_events();
create trigger staff_notice_attendance after insert on public.attendance_live_audit for each row execute function goya_private.staff_notice_events();

create function goya_private.staff_notice_refresh(employee uuid) returns void language plpgsql security definer set search_path='' as $$
declare r record;request_row goya_private.staff_leave_requests;off_row goya_private.off_balance_events;today date:=(now() at time zone 'Asia/Dubai')::date;bucket text;rules jsonb;work_seconds numeric;target_minutes integer;
begin
 for request_row in select * from (select * from goya_private.staff_leave_requests where staff_id=employee and state in ('Approved','Declined') order by updated_at desc limit 200)r order by updated_at loop
  if not exists(select 1 from goya_private.staff_notifications n where n.staff_id=employee and n.kind='request' and n.target->>'id'=request_row.id::text) then perform goya_private.staff_notice_request(request_row);end if;
 end loop;
 for off_row in select * from (select * from goya_private.off_balance_events where staff_id=employee order by id desc limit 200)r order by id loop perform goya_private.staff_notice_off(off_row);end loop;
 for r in select * from (select d.*,row_number() over(partition by category order by uploaded_at desc,id desc) rn from goya_private.staff_document_versions d where staff_id=employee and uploaded_at is not null)d where rn=1 and expires_on<=today+30 loop
  bucket:=case when r.expires_on<today then 'expired' when r.expires_on<=today+7 then '7' when r.expires_on<=today+15 then '15' else '30' end;
  perform goya_private.staff_notice_emit(employee,'document:'||r.id||':'||r.expires_on||':'||bucket,'document','Document expiry reminder',
   coalesce(r.custom_title,initcap(replace(r.category,'-',' ')))||' · '||case when r.expires_on<today then 'Expired on ' when r.expires_on=today then 'Expires today: ' else 'Expires on ' end||r.expires_on::text,
   jsonb_build_object('view','document','id',r.id,'category',r.category));
 end loop;
 rules:=public.attendance_live_rules();
 for r in select d.* from public.attendance_live_days d where d.staff_id=employee and not d.is_deleted and d.operational_date between today-1 and today
 and exists(select 1 from public.attendance_live_sessions s where s.staff_id=employee and s.operational_date=d.operational_date and not s.is_deleted and s.check_out_at is null) loop
  select coalesce(sum(extract(epoch from coalesce(s.check_out_at,now())-s.check_in_at)),0) into work_seconds from public.attendance_live_sessions s where s.staff_id=employee and s.operational_date=r.operational_date and not s.is_deleted;
  target_minutes:=coalesce((r.ot_policy->>'regular_minutes')::int,(rules->>'regular_net_minutes')::int,480)+case when coalesce((rules->>'force_no_break')::boolean,false) or r.break_taken=false then 0 else coalesce((r.ot_policy->>'break_minutes')::int,(rules->>'break_minutes')::int,60) end;
  if work_seconds>=target_minutes*60 then perform goya_private.staff_notice_emit(employee,'checkout:'||r.operational_date,'reminder','Check-out reminder','Your duty target has been reached and you are still checked in. Please check out when your work is finished.',jsonb_build_object('view','attendance','date',r.operational_date));end if;
 end loop;
end $$;
create function goya_private.staff_notice_reminders() returns void language plpgsql security definer set search_path='' as $$declare employee uuid;begin
 for employee in select id from public.staff where active order by id loop perform goya_private.staff_notice_refresh(employee);end loop;
end $$;

create function public.goya_staff_inbox(p_token text,p_before bigint default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare employee uuid:=(public.require_session(p_token,false)).staff_id;settings jsonb;begin
 if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized';end if;
 perform goya_private.staff_notice_refresh(employee);
 select jsonb_build_object('value',preferences,'revision',revision) into settings from goya_private.staff_appearance where staff_id=employee;
 return jsonb_build_object('staff_id',employee,'preferences',coalesce(settings,'{"value":{"mode":"auto","accent":"default","text_size":"normal"},"revision":0}'),
 'unread',(select count(*) from goya_private.staff_notifications where staff_id=employee and read_at is null),
 'max_id',(select max(id) from goya_private.staff_notifications where staff_id=employee),
 'items',coalesce((select jsonb_agg(to_jsonb(q) order by q.id desc) from (select id,event_key,kind,title,body,target,created_at,read_at from goya_private.staff_notifications where staff_id=employee and (p_before is null or id<p_before) order by id desc limit 100)q),'[]'::jsonb));
end $$;
create function public.goya_staff_notice_read(p_token text,p_ids bigint[],p_read boolean,p_through bigint default null) returns void language plpgsql security definer set search_path='' as $$
declare employee uuid:=(public.require_session(p_token,false)).staff_id;begin
 if not exists(select 1 from public.staff where id=employee and active) or p_read is null or coalesce(cardinality(p_ids),0)>200 or (p_through is not null and not p_read) then raise exception 'Invalid notification update';end if;
 update goya_private.staff_notifications set read_at=case when p_read then coalesce(read_at,clock_timestamp()) else null end
 where staff_id=employee and (id=any(p_ids) or (p_through is not null and id<=p_through));
end $$;
create function public.goya_staff_appearance_save(p_token text,p_preferences jsonb,p_expected integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare employee uuid:=(public.require_session(p_token,false)).staff_id;result jsonb;begin
 if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized';end if;
 if jsonb_typeof(p_preferences) is distinct from 'object' or p_preferences->>'mode' is null or p_preferences->>'mode' not in ('auto','light','dark') or p_preferences->>'accent' is null or p_preferences->>'accent' not in ('default','green','blue','purple','brown','teal') or p_preferences->>'text_size' is null or p_preferences->>'text_size' not in ('normal','large') or p_expected is null then raise exception 'Choose a supported theme preset';end if;
 p_preferences:=jsonb_build_object('mode',p_preferences->>'mode','accent',p_preferences->>'accent','text_size',p_preferences->>'text_size');
 if p_expected=0 then insert into goya_private.staff_appearance(staff_id,preferences) values(employee,p_preferences) on conflict do nothing returning jsonb_build_object('value',preferences,'revision',revision) into result;
 else update goya_private.staff_appearance set preferences=p_preferences,revision=revision+1,updated_at=clock_timestamp() where staff_id=employee and revision=p_expected returning jsonb_build_object('value',preferences,'revision',revision) into result;end if;
 if result is null then raise exception 'Appearance changed on another device. Reopen Appearance and try again.';end if;return result;
end $$;
revoke all on function goya_private.staff_notice_emit(uuid,text,text,text,text,jsonb,timestamptz),goya_private.staff_notice_request(goya_private.staff_leave_requests),goya_private.staff_notice_off(goya_private.off_balance_events),goya_private.staff_notice_day(jsonb),goya_private.staff_notice_events(),goya_private.staff_notice_refresh(uuid),goya_private.staff_notice_reminders() from public,anon,authenticated;
revoke all on function public.goya_staff_inbox(text,bigint),public.goya_staff_notice_read(text,bigint[],boolean,bigint),public.goya_staff_appearance_save(text,jsonb,integer) from public;
grant execute on function public.goya_staff_inbox(text,bigint),public.goya_staff_notice_read(text,bigint[],boolean,bigint),public.goya_staff_appearance_save(text,jsonb,integer) to anon,authenticated;
select cron.schedule('goya-private-staff-reminders','*/5 * * * *','select goya_private.staff_notice_reminders()');
commit;
