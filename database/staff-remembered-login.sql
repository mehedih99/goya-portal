-- Staff-only opt-in persistence. PINs are never returned or stored in browser storage.
create table goya_private.staff_remembered_sessions (
 session_token text primary key references public.app_sessions(token) on delete cascade,
 staff_id uuid not null references public.staff(id) on delete cascade,created_at timestamptz not null default now()
);
alter table goya_private.staff_remembered_sessions enable row level security;
revoke all on goya_private.staff_remembered_sessions from public,anon,authenticated;
create index remembered_staff_id on goya_private.staff_remembered_sessions(staff_id);

create function public.goya_staff_remember(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare sess public.app_sessions; s public.staff; expiry timestamptz;
begin
 sess:=public.require_session(p_token,false);
 select * into s from public.staff where id=sess.staff_id and active for share;
 if not found then raise exception using message='DEVICE_LOGIN_REQUIRED',errcode='28000';end if;
 update public.app_sessions set expires_at=now()+interval '30 days' where token=p_token and not is_admin and expires_at>now() returning expires_at into expiry;
 if not found then raise exception using message='DEVICE_LOGIN_REQUIRED',errcode='28000';end if;
 insert into goya_private.staff_remembered_sessions(session_token,staff_id)values(p_token,s.id)on conflict(session_token)do nothing;
 return jsonb_build_object('expires_at',expiry);
end $$;
create function public.goya_staff_resume(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
declare sess public.app_sessions; s public.staff; expiry timestamptz;
begin
 select * into sess from public.app_sessions where token=p_token and not is_admin and expires_at>now();
 if not found then raise exception using message='DEVICE_LOGIN_REQUIRED',errcode='28000';end if;
 select * into s from public.staff where id=sess.staff_id and active for share;
 if not found then raise exception using message='DEVICE_LOGIN_REQUIRED',errcode='28000';end if;
 update public.app_sessions a set expires_at=now()+interval '30 days'
 where a.token=p_token and not a.is_admin and a.expires_at>now()
 and exists(select 1 from goya_private.staff_remembered_sessions r where r.session_token=a.token and r.staff_id=s.id)
 returning a.expires_at into expiry;
 if not found then raise exception using message='DEVICE_LOGIN_REQUIRED',errcode='28000';end if;
 return jsonb_build_object('token',p_token,'staff_id',s.id,'name',s.name,'expires_at',expiry,'access',jsonb_build_object('order',s.can_order,'production',s.can_production,'wastage',s.can_wastage,'inventory',s.can_inventory,'sections',s.sections));
end $$;
revoke all on function public.goya_staff_remember(text),public.goya_staff_resume(text) from public;
grant execute on function public.goya_staff_remember(text),public.goya_staff_resume(text) to anon,authenticated;

-- Only saved staff sessions are revoked; existing admin/ordinary session behavior is preserved.
create function goya_private.revoke_remembered_staff() returns trigger language plpgsql security definer set search_path='' as $$
begin
 delete from public.app_sessions a using goya_private.staff_remembered_sessions r where a.token=r.session_token and r.staff_id=new.id and not a.is_admin;
 return new;
end $$;
revoke all on function goya_private.revoke_remembered_staff() from public,anon,authenticated;
create trigger revoke_saved_staff_login after update of active,pin_code on public.staff
 for each row when(old.active is distinct from new.active or old.pin_code is distinct from new.pin_code)
 execute function goya_private.revoke_remembered_staff();
