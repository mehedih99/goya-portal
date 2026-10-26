-- Production verification: all fixture rows and changes are rolled back.
begin;
do $$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();v uuid;h jsonb;r jsonb;tab text:='QA-'||gen_random_uuid()::text;ta text:='qa-'||gen_random_uuid();tb text:='qa-'||gen_random_uuid();ad text:='qa-'||gen_random_uuid();fails boolean;
begin
 insert into public.staff(id,name,pin_hash,active,can_inventory,sections) values(a,'QA morning','not-a-login-hash',true,true,array[tab]),(b,'QA evening','not-a-login-hash',true,true,array[tab]);
 insert into public.app_sessions(token,staff_id,is_admin,expires_at) values(ta,a,false,now()+interval '5 minutes'),(tb,b,false,now()+interval '5 minutes'),(ad,null,true,now()+interval '5 minutes');
 insert into public.master_items(name,sku,storage_unit,ingredient_unit,items_type) values('QA item one',tab||'-1','PCS','GRAM',tab),('QA item two',tab||'-2','L','ML',tab);
 r:=public.admin_inventory_save_session(ad,jsonb_build_object('month','2026-10-01','title','QA rollback sheet','counting_date','2026-10-26','active',true,'sections',jsonb_build_array(tab),'assigned_staff_ids',jsonb_build_array(a,b)));v:=(r->>'id')::uuid;
 h:=public.inventory_work(ta,v,tab);assert (h->>'shared')::boolean and jsonb_array_length(h->'items')=2;
 r:=public.goya_inventory_shared_save(ta,v,tab,1,jsonb_build_array(jsonb_build_object('sku',tab||'-1','version',0,'storage_quantity',0,'ingredients_quantity',10)));assert (r->>'ok')::boolean;
 r:=public.goya_inventory_shared_save(tb,v,tab,1,jsonb_build_array(jsonb_build_object('sku',tab||'-2','version',0,'storage_quantity',2,'ingredients_quantity',100)));assert (r->>'ok')::boolean;
 r:=public.goya_inventory_shared_save(tb,v,tab,1,jsonb_build_array(jsonb_build_object('sku',tab||'-1','version',0,'storage_quantity',99,'ingredients_quantity',99)));assert r->>'reason'='conflict';
 h:=public.inventory_work(tb,v,tab);assert (h->'items'->0->>'storage_quantity')::numeric=0;
 r:=public.goya_inventory_shared_submit(ta,v,tab,1,(h->>'version')::bigint);assert (r->>'ok')::boolean;
 r:=public.goya_inventory_shared_submit(tb,v,tab,1,(h->>'version')::bigint);assert (r->>'already_submitted')::boolean;
 assert (select count(*)=2 from public.inventory_counts where session_id=v);
 perform public.goya_admin_inventory_reopen(ad,v,tab);
 r:=public.goya_inventory_shared_save(tb,v,tab,1,jsonb_build_array(jsonb_build_object('sku',tab||'-1','version',1,'storage_quantity',99,'ingredients_quantity',99)));assert r->>'reason'='reopened';
 h:=public.inventory_work(ta,v,tab);assert (h->>'generation')::bigint=2;
 r:=public.goya_inventory_shared_save(tb,v,tab,2,jsonb_build_array(jsonb_build_object('sku',tab||'-1','version',1,'storage_quantity',3,'ingredients_quantity',30)));assert (r->>'ok')::boolean;
 h:=r->'sheet';perform public.goya_inventory_shared_submit(tb,v,tab,2,(h->>'version')::bigint);
 assert (select count(*)=2 from public.inventory_counts where session_id=v);
 r:=public.goya_inventory_shared_history(ad,v,tab);assert jsonb_array_length(r->'submissions')=2;
 fails:=false;begin perform public.inventory_save_draft(ta,v,tab,'[]');exception when others then fails:=true;end;assert fails;
 fails:=false;begin delete from public.inventory_counts where session_id=v;exception when others then fails:=true;end;assert fails;
 update public.staff set active=false where id=b;
 fails:=false;begin perform public.goya_inventory_shared_work(tb,v,tab);exception when others then fails:=true;end;assert fails;
 assert not has_table_privilege('anon','goya_private.inventory_shared_lines','select');
 assert not has_function_privilege('anon','goya_private.inventory_shared_open(text,uuid,text)','execute');
 assert has_function_privilege('anon','public.goya_inventory_shared_save(text,uuid,text,bigint,jsonb)','execute');
end $$;
rollback;
select 'PASS: live PostgreSQL shared save/conflict/final/reopen/history/auth; fixtures rolled back' result;
