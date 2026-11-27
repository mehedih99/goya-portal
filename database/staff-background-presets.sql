begin;
set local lock_timeout='5s';
-- Existing rows remain untouched; older clients retain the saved background.
CREATE OR REPLACE FUNCTION public.goya_staff_appearance_save(p_token text, p_preferences jsonb, p_expected integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid:=(public.require_session(p_token,false)).staff_id;result jsonb;scene text;begin
 if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized';end if;
 if jsonb_typeof(p_preferences) is distinct from 'object' or p_preferences->>'mode' is null or p_preferences->>'mode' not in ('auto','light','dark') or p_preferences->>'accent' is null or p_preferences->>'accent' not in ('default','green','blue','purple','brown','teal') or p_preferences->>'text_size' is null or p_preferences->>'text_size' not in ('normal','large') or p_expected is null then raise exception 'Choose a supported theme preset';end if;
 scene:=coalesce(p_preferences->>'background',(select preferences->>'background' from goya_private.staff_appearance where staff_id=employee),'default');
 if scene not in ('default','ocean','forest','lavender','sand') then raise exception 'Choose a supported background preset';end if;
 p_preferences:=jsonb_build_object('mode',p_preferences->>'mode','accent',p_preferences->>'accent','text_size',p_preferences->>'text_size','background',scene);
 if p_expected=0 then insert into goya_private.staff_appearance(staff_id,preferences) values(employee,p_preferences) on conflict do nothing returning jsonb_build_object('value',preferences,'revision',revision) into result;
 else update goya_private.staff_appearance set preferences=p_preferences,revision=revision+1,updated_at=clock_timestamp() where staff_id=employee and revision=p_expected returning jsonb_build_object('value',preferences,'revision',revision) into result;end if;
 if result is null then raise exception 'Appearance changed on another device. Reopen Appearance and try again.';end if;return result;
end $function$
;
commit;
