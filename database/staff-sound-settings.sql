begin;
set local lock_timeout='5s';
-- Defaults are interpreted without rewriting staff preferences; older clients preserve sound choices.
CREATE OR REPLACE FUNCTION public.goya_staff_appearance_save(p_token text, p_preferences jsonb, p_expected integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid:=(public.require_session(p_token,false)).staff_id;result jsonb;scene text;saved jsonb;sound_notification jsonb;sound_attendance jsonb;volume text;begin
 if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized';end if;
 if jsonb_typeof(p_preferences) is distinct from 'object' or p_preferences->>'mode' is null or p_preferences->>'mode' not in ('auto','light','dark') or p_preferences->>'accent' is null or p_preferences->>'accent' not in ('default','green','blue','purple','brown','teal') or p_preferences->>'text_size' is null or p_preferences->>'text_size' not in ('normal','large') or p_expected is null then raise exception 'Choose a supported theme preset';end if;
 scene:=coalesce(p_preferences->>'background',(select preferences->>'background' from goya_private.staff_appearance where staff_id=employee),'default');
 if scene not in ('default','ocean','forest','lavender','sand') then raise exception 'Choose a supported background preset';end if;
 select preferences into saved from goya_private.staff_appearance where staff_id=employee;
 sound_notification:=coalesce(p_preferences->'notification_sound',saved->'notification_sound','true'::jsonb);
 sound_attendance:=coalesce(p_preferences->'attendance_sound',saved->'attendance_sound','true'::jsonb);
 volume:=coalesce(p_preferences->>'sound_volume',saved->>'sound_volume','35');
 if jsonb_typeof(sound_notification)<>'boolean' or jsonb_typeof(sound_attendance)<>'boolean' or volume !~ '^(100|[0-9]{1,2})$' then raise exception 'Choose valid sound switches and volume (0–100)';end if;
 p_preferences:=jsonb_build_object('mode',p_preferences->>'mode','accent',p_preferences->>'accent','text_size',p_preferences->>'text_size','background',scene,'notification_sound',sound_notification,'attendance_sound',sound_attendance,'sound_volume',volume::integer);
 if p_expected=0 then insert into goya_private.staff_appearance(staff_id,preferences) values(employee,p_preferences) on conflict do nothing returning jsonb_build_object('value',preferences,'revision',revision) into result;
 else update goya_private.staff_appearance set preferences=p_preferences,revision=revision+1,updated_at=clock_timestamp() where staff_id=employee and revision=p_expected returning jsonb_build_object('value',preferences,'revision',revision) into result;end if;
 if result is null then raise exception 'Appearance changed on another device. Reopen Appearance and try again.';end if;return result;
end $function$
;
commit;
