-- Defense against any older portal write path creating personal copies of a shared sheet.
create function goya_private.validate_shared_inventory_count() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='UPDATE' and old.shared_sheet_id is not null and new.shared_sheet_id is distinct from old.shared_sheet_id then raise exception 'Shared sheet identity cannot be changed';end if;
 if exists(select 1 from public.inventory_sessions where id=new.session_id and shared_count) then
  if new.shared_sheet_id is null or not exists(select 1 from goya_private.inventory_shared_sheets h where h.id=new.shared_sheet_id and h.session_id=new.session_id and h.section=new.section) then raise exception 'Use the shared inventory sheet; personal copies are not allowed';end if;
 end if;return new;
end $$;
revoke all on function goya_private.validate_shared_inventory_count() from public,anon,authenticated;
create trigger validate_shared_inventory_count before insert or update on public.inventory_counts for each row execute function goya_private.validate_shared_inventory_count();
do $$ declare def text;begin
 if to_regprocedure('public.save_inventory_count(text,uuid,jsonb)') is not null then
 def:=pg_get_functiondef('public.save_inventory_count(text,uuid,jsonb)'::regprocedure);
 if position('  sess:=public.require_session' in def)=0 then raise exception 'Old inventory API changed; inspect before patching';end if;
 def:=replace(def,'  sess:=public.require_session',$guard$  if exists(select 1 from public.inventory_sessions where id=p_session_id and shared_count) then raise exception 'Shared count: refresh your Staff Portal to save safely';end if;
  sess:=public.require_session$guard$);execute def;
 end if;
end $$;
