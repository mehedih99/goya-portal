begin;
do $$
declare sid uuid:=gen_random_uuid();staffid uuid:=gen_random_uuid();tokenv text:='qa-'||gen_random_uuid();prefixv text:='QA-'||gen_random_uuid();r jsonb;denied boolean:=false;
begin
 insert into public.staff(id,name,pin_hash,active,sections) values(staffid,prefixv,'not-a-login-hash',true,array['Bar']);
 insert into public.app_sessions(token,staff_id,is_admin,expires_at) values(tokenv,staffid,false,now()+interval '5 minutes');
 insert into public.inventory_sessions(id,month,title,active,sections,assigned_staff_ids,shared_count) values(sid,'2026-10-01',prefixv,false,array['Bar','Kitchen'],array[staffid],false);
 insert into public.inventory_counts(session_id,staff_id,item_name,sku,section,storage_quantity,ingredients_quantity,counted_by,counted_at)
 select sid,staffid,prefixv||' Coffee '||n,prefixv||'-'||n,case when n%2=0 then 'Bar' else 'Kitchen' end,0,0,prefixv,'2026-10-15T10:00:00Z' from generate_series(1,65)n;
 r:=public.goya_staff_history_page(tokenv,'inventory','2026-10-01',jsonb_build_object('search',prefixv),1);assert (r->>'total')::int=65 and jsonb_array_length(r->'rows')=30;
 r:=public.goya_staff_history_page(tokenv,'inventory','2026-10-01',jsonb_build_object('search',lower(prefixv),'section','Kitchen'),2);assert (r->>'total')::int=33 and jsonb_array_length(r->'rows')=3;
 r:=public.goya_staff_history_page(tokenv,'inventory','2026-10-01',jsonb_build_object('search',prefixv||'-65','section','Kitchen'),1);assert (r->>'total')::int=1;
 r:=public.goya_staff_history_page(tokenv,'inventory','2026-09-01',jsonb_build_object('search',prefixv),1);assert (r->>'total')::int=0;
 r:=public.goya_staff_history_page(tokenv,'inventory','2026-10-01',jsonb_build_object('search',prefixv,'section','Pastry'),9);assert (r->>'total')::int=0 and (r->>'page')::int=1;
 begin perform public.goya_staff_history_page('invalid-qa-token','inventory','2026-10-01','{}',1);exception when others then denied:=true;end;assert denied;
 assert (select count(*)=65 from public.inventory_counts where session_id=sid);
 assert has_function_privilege('anon','public.goya_staff_history_page(text,text,date,jsonb,integer)','execute');
end $$;
rollback;
select 'PASS: live filtered pagination, combined search/section, SKU, month scope, empty result and authorization. All fixtures rolled back.' result;
