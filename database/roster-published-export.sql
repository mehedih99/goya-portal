-- Read-only export of the current published roster, never the draft.
create function public.goya_roster_published_export(p_token text, p_week date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare publication goya_private.roster_publications;
begin
  perform public.require_session(p_token,true);
  if p_week is null or extract(isodow from p_week)<>1 then raise exception 'Choose a valid roster week'; end if;
  select p.* into publication from goya_private.roster_weeks w
    join goya_private.roster_publications p on p.week_start=w.week_start and p.revision=w.published_revision
    where w.week_start=p_week;
  if not found then raise exception 'Publish this roster before downloading the PDF'; end if;
  return jsonb_build_object('week',publication.week_start,'revision',publication.revision,
    'published_at',publication.published_at,'schedule',publication.schedule,
    'staff',coalesce((select jsonb_agg(jsonb_build_object('id',m.key,'name',coalesce(s.name,'Former staff'),
      'roster_group',hp.roster_group) order by s.name,m.key)
      from jsonb_each(publication.schedule->'staff') m
      left join public.staff s on s.id::text=m.key
      left join goya_private.staff_hr_profiles hp on hp.staff_id=s.id),'[]'::jsonb));
end $$;
revoke all on function public.goya_roster_published_export(text,date) from public;
grant execute on function public.goya_roster_published_export(text,date) to anon,authenticated;
