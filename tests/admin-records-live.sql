-- Test real submission functions using disposable fixtures. Everything is rolled back.
begin;
do $$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();v uuid;h jsonb;r jsonb;eq uuid;req uuid:=gen_random_uuid();
 tab text:='QA-'||gen_random_uuid()::text;ta text:='qa-'||gen_random_uuid();tb text:='qa-'||gen_random_uuid();ad text:='qa-'||gen_random_uuid();gid uuid;n bigint;baseline bigint;fails boolean;note_id bigint;
begin
 insert into public.staff(id,name,pin_hash,active,can_order,can_production,can_wastage,can_inventory,sections) values(a,tab,'not-a-login-hash',true,true,true,true,true,array[tab]),(b,tab||'-other','not-a-login-hash',true,true,true,true,true,array[tab]);
 insert into public.app_sessions(token,staff_id,is_admin,expires_at) values(ta,a,false,now()+interval '5 minutes'),(tb,b,false,now()+interval '5 minutes'),(ad,null,true,now()+interval '5 minutes');
 select count(*) into baseline from goya_private.admin_notifications;
 r:=public.submit_order(ta,null,jsonb_build_array(jsonb_build_object('name','QA order one','sku',tab||'-1','quantity',1,'unit','PCS','supplier','QA'),jsonb_build_object('name','QA order two','sku',tab||'-2','quantity',2,'unit','PCS','supplier','QA')));gid:=(r->>'order_group_id')::uuid;
 assert (select count(*)=1 from goya_private.admin_notifications where kind='orders' and event_key=gid::text);
 assert (select count(*)=2 from public.orders where order_group_id=gid);
 r:=public.submit_production(ta,jsonb_build_array(jsonb_build_object('name','QA production','sku',tab,'quantity',1,'unit','PCS','storage_quantity',1)));gid:=(r->>'group_id')::uuid;
 assert (select count(*)=1 from goya_private.admin_notifications where kind='production' and event_key=gid::text);
 r:=public.submit_wastage(ta,jsonb_build_array(jsonb_build_object('name','QA wastage','sku',tab,'quantity',1,'unit','PCS','storage_quantity',1,'reason','QA rollback')));gid:=(r->>'group_id')::uuid;
 assert (select count(*)=1 from goya_private.admin_notifications where kind='wastage' and event_key=gid::text);
 r:=public.submit_complaint_feedback(ta,'Feedback','QA rollback only',true);
 select id into note_id from goya_private.admin_notifications where kind='feedback' and event_key=r->>'id';
 assert note_id is not null;assert (select staff_name='Anonymous' from goya_private.admin_notifications where id=note_id);
 h:=public.goya_admin_notification_detail(ad,note_id,1);assert h#>>'{rows,0,staff_name}'='Anonymous';assert not ((h#>'{rows,0}')?'staff_id');
 r:=public.goya_equipment_submit(ta,req,jsonb_build_object('item_name','QA glass','quantity','2 pieces','details','QA rollback only','section',tab,'incident_date',(now() at time zone 'Asia/Dubai')::date));eq:=(r->>'id')::uuid;
 r:=public.goya_equipment_submit(ta,req,'{}');assert (r->>'id')::uuid=eq;
 assert (select count(*)=1 from goya_private.equipment_reports where id=eq);assert (select count(*)=1 from goya_private.admin_notifications where kind='equipment' and event_key=eq::text);
 perform public.goya_equipment_review(ad,eq,1,'Reviewed','QA reviewed');
 h:=public.goya_equipment_list(ta,(now() at time zone 'Asia/Dubai')::date,1,false);assert (h->>'total')::int=1;assert h#>>'{rows,0,status}'='Reviewed';
 h:=public.goya_equipment_list(tb,(now() at time zone 'Asia/Dubai')::date,1,false);assert (h->>'total')::int=0;
 fails:=false;begin perform public.goya_admin_notifications(ta,1,false);exception when others then fails:=true;end;assert fails;
 fails:=false;begin perform public.goya_equipment_review(ta,eq,2,'Closed','');exception when others then fails:=true;end;assert fails;
 fails:=false;begin perform public.goya_equipment_review(ad,eq,1,'Closed','stale');exception when others then fails:=true;end;assert fails;
 insert into public.master_items(name,sku,storage_unit,ingredient_unit,items_type) values('QA count one',tab||'-1','PCS','GRAM',tab);
 r:=public.admin_inventory_save_session(ad,jsonb_build_object('month',date_trunc('month',now())::date,'title','QA rollback count','counting_date',(now() at time zone 'Asia/Dubai')::date,'active',true,'sections',jsonb_build_array(tab),'assigned_staff_ids',jsonb_build_array(a,b)));v:=(r->>'id')::uuid;
 h:=public.inventory_work(ta,v,tab);
 r:=public.goya_inventory_shared_save(ta,v,tab,1,jsonb_build_array(jsonb_build_object('sku',tab||'-1','version',0,'storage_quantity',0,'ingredients_quantity',10)));assert (r->>'ok')::boolean;
 assert not exists(select 1 from goya_private.admin_notifications where kind='inventory_shared' and staff_name=tab),'Auto Draft must not notify';
 h:=public.inventory_work(tb,v,tab);r:=public.goya_inventory_shared_submit(ta,v,tab,1,(h->>'version')::bigint);assert (r->>'ok')::boolean;
 r:=public.goya_inventory_shared_submit(tb,v,tab,1,(h->>'version')::bigint);assert (r->>'already_submitted')::boolean;
 assert (select count(*)=1 from goya_private.admin_notifications where kind='inventory_shared' and staff_name=tab);
 select id into note_id from goya_private.admin_notifications where kind='inventory_shared' and staff_name=tab;
 h:=public.goya_admin_notification_detail(ad,note_id,1);assert jsonb_array_length(h->'rows')=1;
 -- Legacy final submission path remains operational too.
 insert into public.inventory_sessions(month,title,active,sections,assigned_staff_ids,shared_count) values(date_trunc('month',now())::date,'QA legacy rollback',true,array[tab],array[a],false) returning id into v;
 r:=public.inventory_submit_final(ta,v,tab,jsonb_build_array(jsonb_build_object('item_name','QA count one','sku',tab||'-1','storage_quantity',1,'ingredients_quantity',10)));
 assert (select count(*)=1 from goya_private.admin_notifications where kind='inventory' and source_ref->>'session_id'=v::text);
 assert not has_table_privilege('anon','goya_private.equipment_reports','select');assert not has_table_privilege('authenticated','goya_private.admin_notifications','select');assert not has_function_privilege('anon','goya_private.capture_admin_submission()','execute');
end $$;
rollback;
select 'PASS: live PostgreSQL all submission paths, no draft notifications, idempotent equipment, anonymous feedback, shared final retry, legacy final, staff/admin authorization and stale review protection. All fixtures rolled back.' result;
