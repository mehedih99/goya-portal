begin;
create table goya_private.pnl_reports (
  start_date date not null,
  end_date date not null,
  payload jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (start_date,end_date),
  check (end_date >= start_date and date_trunc('month',start_date::timestamp)=date_trunc('month',end_date::timestamp)),
  check (jsonb_typeof(payload)='object' and octet_length(payload::text)<=262144)
);
alter table goya_private.pnl_reports enable row level security;
revoke all on goya_private.pnl_reports from public, anon, authenticated;
create function public.goya_pnl_history(p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform public.require_session(p_token,true);
  return coalesce((select jsonb_agg(to_jsonb(r) order by start_date desc,end_date desc)
    from goya_private.pnl_reports r),'[]'::jsonb);
end;
$$;
create function public.goya_pnl_save(p_token text,p_start date,p_end date,p_payload jsonb,p_expected timestamptz default null) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  perform public.require_session(p_token,true);
  if p_expected is null then
    insert into goya_private.pnl_reports(start_date,end_date,payload)
    values(p_start,p_end,p_payload) on conflict do nothing;
  else
    update goya_private.pnl_reports set payload=p_payload,updated_at=clock_timestamp()
    where start_date=p_start and end_date=p_end and updated_at=p_expected;
  end if;
  if not found then raise exception 'This period already exists or changed. Reload Report History.'; end if;
  return true;
end;
$$;
create function public.goya_pnl_delete(p_token text,p_start date,p_end date,p_expected timestamptz) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  perform public.require_session(p_token,true);
  delete from goya_private.pnl_reports where start_date=p_start and end_date=p_end and updated_at=p_expected;
  if not found then raise exception 'This report changed. Reload Report History.'; end if;
  return true;
end;
$$;
revoke execute on function public.goya_pnl_history(text), public.goya_pnl_save(text,date,date,jsonb,timestamptz), public.goya_pnl_delete(text,date,date,timestamptz) from public;
grant execute on function public.goya_pnl_history(text), public.goya_pnl_save(text,date,date,jsonb,timestamptz), public.goya_pnl_delete(text,date,date,timestamptz) to anon, authenticated;
commit;
