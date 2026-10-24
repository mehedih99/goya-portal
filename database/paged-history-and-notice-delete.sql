-- Additive APIs; original history/export functions remain compatible.
create function public.goya_orders_page(p_token text,p_admin boolean default false,p_filters jsonb default '{}',p_page integer default 1) returns jsonb language plpgsql security definer set search_path='' as $$
declare f jsonb:=coalesce(p_filters,'{}'); lo timestamptz; hi timestamptz; od date:=nullif(f->>'order_date','')::date; rd date:=nullif(f->>'received_date','')::date;
 st text:=nullif(f->>'status',''); sp text:=nullif(f->>'supplier',''); q text:=lower(nullif(trim(f->>'search'),'')); all_dates boolean:=coalesce((f->>'all_dates')::boolean,false);
 total bigint; counts jsonb; rowsv jsonb; pagev integer; monthv date;
begin
 perform public.require_session(p_token,p_admin);
 if p_admin then lo:=nullif(f->>'from','')::timestamptz;hi:=nullif(f->>'to','')::timestamptz;
 else
  if all_dates and coalesce(st,'') not in ('Pending','Ordered') then raise exception 'All-date staff history is limited to open orders';end if;
  if not all_dates then monthv:=date_trunc('month',coalesce(nullif(f->>'month','')::date,timezone('Asia/Dubai',now())::date))::date;lo:=monthv::timestamp at time zone 'Asia/Dubai';hi:=(monthv+interval '1 month')::timestamp at time zone 'Asia/Dubai';end if;
 end if;
 if lo is not null and hi is not null and hi<=lo then raise exception 'End date must be after start date';end if;
 with base as (
 select o.status from public.orders o join public.order_groups g on g.id=o.order_group_id
 where (lo is null or o.created_at>=lo) and (hi is null or o.created_at<hi)
 and (not all_dates or p_admin or o.status in ('Pending','Ordered'))
 and (sp is null or coalesce(o.supplier,'')=sp)
 and (q is null or position(q in lower(coalesce(o.name,'')))>0 or position(q in lower(coalesce(o.sku,'')))>0)
 and (od is null or (o.created_at>=od::timestamp at time zone 'Asia/Dubai' and o.created_at<(od+1)::timestamp at time zone 'Asia/Dubai'))
 and (rd is null or o.received_date=rd)
 ) select count(*) filter(where st is null or status=st),jsonb_build_object('Pending',count(*) filter(where status='Pending'),'Ordered',count(*) filter(where status='Ordered'),'Received',count(*) filter(where status='Received'),'Not Received',count(*) filter(where status='Not Received')) into total,counts from base;
 pagev:=least(greatest(coalesce(p_page,1),1),greatest(1,ceil(total/30.0)::integer));
 select coalesce(jsonb_agg(x.rowv order by x.created_at desc,x.id desc),'[]') into rowsv from (
 select o.id,o.created_at,case when p_admin then to_jsonb(o)||jsonb_build_object('order_no',g.order_no,'submitted_at',g.submitted_at,'group_notes',g.notes)
 else jsonb_build_object('id',o.id,'order_no',g.order_no,'name',o.name,'sku',o.sku,'quantity',o.quantity,'unit',o.unit,'supplier',o.supplier,'status',o.status,'received_date',o.received_date,'logged_by',o.logged_by,'notes',o.notes,'created_at',o.created_at) end rowv
 from public.orders o join public.order_groups g on g.id=o.order_group_id
 where (lo is null or o.created_at>=lo) and (hi is null or o.created_at<hi)
 and (st is null or o.status=st) and (not all_dates or p_admin or o.status in ('Pending','Ordered'))
 and (sp is null or coalesce(o.supplier,'')=sp)
 and (q is null or position(q in lower(coalesce(o.name,'')))>0 or position(q in lower(coalesce(o.sku,'')))>0)
 and (od is null or (o.created_at>=od::timestamp at time zone 'Asia/Dubai' and o.created_at<(od+1)::timestamp at time zone 'Asia/Dubai'))
 and (rd is null or o.received_date=rd)
 order by o.created_at desc,o.id desc limit 30 offset ((pagev-1)::bigint*30)
 )x;
 return jsonb_build_object('rows',rowsv,'total',total,'counts',counts,'page',pagev,'page_size',30);
end $$;
revoke all on function public.goya_orders_page(text,boolean,jsonb,integer) from public;
grant execute on function public.goya_orders_page(text,boolean,jsonb,integer) to anon,authenticated;

create function public.goya_staff_history_page(p_token text,p_kind text default 'orders',p_month date default current_date,p_filters jsonb default '{}',p_page integer default 1) returns jsonb language plpgsql security definer set search_path='' as $$
declare lo timestamptz:=date_trunc('month',p_month)::timestamp at time zone 'Asia/Dubai';hi timestamptz:=(date_trunc('month',p_month)+interval '1 month')::timestamp at time zone 'Asia/Dubai';tab text;col text;total bigint;pagev int;rowsv jsonb;
begin
 perform public.require_session(p_token,false);
 if p_kind='orders' then return public.goya_orders_page(p_token,false,coalesce(p_filters,'{}')||jsonb_build_object('month',p_month),p_page);end if;
 case p_kind when 'production' then tab:='production_batches';col:='created_at';when 'wastage' then tab:='wastage_entries';col:='created_at';when 'inventory' then tab:='inventory_counts';col:='counted_at';else raise exception 'Invalid history kind';end case;
 -- Identifiers come only from the fixed allow-list above. Visibility matches staff_history.
 execute format('select count(*) from public.%I where %I>=$1 and %I<$2',tab,col,col) into total using lo,hi;
 pagev:=least(greatest(coalesce(p_page,1),1),greatest(1,ceil(total/30.0)::int));
 execute format('select coalesce(jsonb_agg(to_jsonb(x) order by x.%I desc,x.id desc),''[]''::jsonb) from (select * from public.%I where %I>=$1 and %I<$2 order by %I desc,id desc limit 30 offset $3)x',col,tab,col,col,col) into rowsv using lo,hi,(pagev-1)::bigint*30;
 return jsonb_build_object('rows',rowsv,'total',total,'page',pagev,'page_size',30);
end $$;
revoke all on function public.goya_staff_history_page(text,text,date,jsonb,integer) from public;
grant execute on function public.goya_staff_history_page(text,text,date,jsonb,integer) to anon,authenticated;

create function public.goya_admin_order_summary(p_token text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform public.require_session(p_token,true);
 return jsonb_build_object('counts',(select jsonb_build_object('Pending',count(*) filter(where status='Pending'),'Ordered',count(*) filter(where status='Ordered'),'Received',count(*) filter(where status='Received'),'Not Received',count(*) filter(where status='Not Received')) from public.orders),
 'recent',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc),'[]') from (select o.id,o.name,o.supplier,o.status,o.logged_by,o.created_at,g.order_no from public.orders o join public.order_groups g on g.id=o.order_group_id order by o.created_at desc,o.id desc limit 8)x));
end $$;
revoke all on function public.goya_admin_order_summary(text) from public;
grant execute on function public.goya_admin_order_summary(text) to anon,authenticated;

alter table goya_private.notices add column deleted_at timestamptz;
create function public.goya_admin_delete_notice(p_token text,p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform public.require_session(p_token,true);
 update goya_private.notices set active=false,deleted_at=coalesce(deleted_at,now()),updated_at=now() where id=p_id;
 if not found then raise exception 'Notice not found';end if;
 update goya_private.notice_push_jobs set cancelled_at=coalesce(cancelled_at,now()) where notice_id=p_id;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.goya_admin_delete_notice(text,uuid) from public;
grant execute on function public.goya_admin_delete_notice(text,uuid) to anon,authenticated;
do $$ declare definition text;begin
 definition:=pg_get_functiondef('public.goya_admin_notices(text)'::regprocedure);
 if position('on j.notice_id=n.id)' in definition)=0 then raise exception 'Notice list API changed; review before patching';end if;
 definition:=replace(definition,'on j.notice_id=n.id)','on j.notice_id=n.id where n.deleted_at is null)');execute definition;
 definition:=pg_get_functiondef('public.goya_admin_save_notice(text,jsonb)'::regprocedure);
 if position('perform public.require_session(p_token,true);' in definition)=0 then raise exception 'Notice save API changed';end if;
 definition:=replace(definition,'perform public.require_session(p_token,true);',$patch$perform public.require_session(p_token,true);
 if nid is not null and exists(select 1 from goya_private.notices where id=nid and deleted_at is not null) then raise exception 'This notice was deleted. Create a new notice instead.';end if;$patch$);definition:=replace(definition,'where id=nid returning','where id=nid and deleted_at is null returning');execute definition;
end $$;
