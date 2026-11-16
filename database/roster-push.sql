begin;

create table goya_private.roster_push_deliveries (
  week_start date not null,
  revision integer not null,
  subscription_id uuid not null references goya_private.push_subscriptions(id) on delete cascade,
  staff_id uuid not null,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  sent_at timestamptz,
  attempts integer not null default 0,
  primary key (week_start,revision,subscription_id),
  foreign key (week_start,revision) references goya_private.roster_publications(week_start,revision)
);
alter table goya_private.roster_push_deliveries enable row level security;
revoke all on goya_private.roster_push_deliveries from public,anon,authenticated;

create function goya_private.queue_roster_push()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.week_start+6 < (now() at time zone 'Asia/Dubai')::date then return new; end if;
  insert into goya_private.roster_push_deliveries(week_start,revision,subscription_id,staff_id)
    select new.week_start,new.revision,p.id,p.staff_id from goya_private.push_subscriptions p
    join public.staff s on s.id=p.staff_id and s.active
    where p.active and (new.schedule->'staff') ? p.staff_id::text and exists (
      select 1 from jsonb_array_elements(new.schedule->'staff'->p.staff_id::text) as days(value)
      where days.value <> 'null'::jsonb
    );
  return new;
end $$;
revoke all on function goya_private.queue_roster_push() from public,anon,authenticated;
create trigger queue_roster_push after insert on goya_private.roster_publications
for each row execute function goya_private.queue_roster_push();

create function public.goya_roster_push_claim()
returns jsonb language sql security definer set search_path='' as $$
  with jobs as (
    select d.week_start,d.revision,d.subscription_id,p.subscription
    from goya_private.roster_push_deliveries d
    join goya_private.push_subscriptions p on p.id=d.subscription_id and p.staff_id=d.staff_id and p.active
    join public.staff s on s.id=d.staff_id and s.active
    join goya_private.roster_weeks w on w.week_start=d.week_start and w.published_revision=d.revision
    where d.sent_at is null and d.attempts<3 and d.created_at>now()-interval '1 day'
      and (d.claimed_at is null or d.claimed_at<now()-interval '3 minutes')
    order by d.created_at for update of d skip locked limit 30
  ), claimed as (
    update goya_private.roster_push_deliveries d set claimed_at=now(),attempts=attempts+1 from jobs j
    where (d.week_start,d.revision,d.subscription_id)=(j.week_start,j.revision,j.subscription_id)
    returning j.*
  ) select coalesce(jsonb_agg(to_jsonb(claimed)),'[]'::jsonb) from claimed;
$$;

create function public.goya_roster_push_check(p_week date,p_revision integer,p_subscription uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from goya_private.roster_push_deliveries d
    join goya_private.push_subscriptions p on p.id=d.subscription_id and p.staff_id=d.staff_id and p.active
    join public.staff s on s.id=d.staff_id and s.active
    join goya_private.roster_weeks w on w.week_start=d.week_start and w.published_revision=d.revision
    where (d.week_start,d.revision,d.subscription_id)=(p_week,p_revision,p_subscription) and d.sent_at is null);
$$;

create function public.goya_roster_push_result(p_week date,p_revision integer,p_subscription uuid,p_sent boolean,p_expired boolean)
returns void language sql security definer set search_path='' as $$
  update goya_private.roster_push_deliveries set sent_at=case when p_sent then now() else sent_at end,
    attempts=case when p_expired then 3 else attempts end
    where (week_start,revision,subscription_id)=(p_week,p_revision,p_subscription);
$$;

revoke all on function public.goya_roster_push_claim(),public.goya_roster_push_check(date,integer,uuid),
  public.goya_roster_push_result(date,integer,uuid,boolean,boolean) from public,anon,authenticated;
grant execute on function public.goya_roster_push_claim(),public.goya_roster_push_check(date,integer,uuid),
  public.goya_roster_push_result(date,integer,uuid,boolean,boolean) to service_role;

commit;
