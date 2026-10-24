do $migration$
declare definition text;
begin
 definition:=pg_get_functiondef('public.attendance_live_admin_update_session(text,uuid,timestamptz,timestamptz)'::regprocedure);
 if position('check_in_verified=true' in definition)>0 then raise exception 'Function already changed; inspect before applying'; end if;
 if position('check_out_at=p_check_out,' in definition)=0 then raise exception 'Unexpected function definition'; end if;
 definition:=replace(definition,'check_out_at=p_check_out,','check_out_at=p_check_out,
         check_in_verified=true,
         check_out_verified=case when p_check_out is null then null else true end,');
 execute definition;
end $migration$;