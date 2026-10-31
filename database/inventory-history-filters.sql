-- Read-only filtering. Existing visibility, time boundaries and non-inventory paths stay unchanged.
create or replace function public.goya_staff_history_page(p_token text,p_kind text default 'orders',p_month date default current_date,p_filters jsonb default '{}',p_page integer default 1) returns jsonb language plpgsql security definer set search_path='' as $$
declare lo timestamptz:=date_trunc('month',p_month)::timestamp at time zone 'Asia/Dubai';hi timestamptz:=(date_trunc('month',p_month)+interval '1 month')::timestamp at time zone 'Asia/Dubai';tab text;col text;total bigint;pagev int;rowsv jsonb;q text;sectionv text;
begin
 perform public.require_session(p_token,false);
 if p_kind='orders' then return public.goya_orders_page(p_token,false,coalesce(p_filters,'{}')||jsonb_build_object('month',p_month),p_page);end if;
 if p_kind='inventory' then
  q:=lower(trim(coalesce(p_filters->>'search','')));sectionv:=trim(coalesce(p_filters->>'section',''));
  select count(*) into total from public.inventory_counts i where i.counted_at>=lo and i.counted_at<hi
   and (q='' or strpos(lower(coalesce(i.item_name,'')),q)>0 or strpos(lower(coalesce(i.sku,'')),q)>0)
   and (sectionv='' or i.section=sectionv);
  pagev:=least(greatest(coalesce(p_page,1),1),greatest(1,ceil(total/30.0)::int));
  select coalesce(jsonb_agg(to_jsonb(x) order by x.counted_at desc,x.id desc),'[]'::jsonb) into rowsv from
   (select i.* from public.inventory_counts i where i.counted_at>=lo and i.counted_at<hi
    and (q='' or strpos(lower(coalesce(i.item_name,'')),q)>0 or strpos(lower(coalesce(i.sku,'')),q)>0)
    and (sectionv='' or i.section=sectionv) order by i.counted_at desc,i.id desc limit 30 offset (pagev-1)::bigint*30)x;
  return jsonb_build_object('rows',rowsv,'total',total,'page',pagev,'page_size',30);
 end if;
 case p_kind when 'production' then tab:='production_batches';col:='created_at';when 'wastage' then tab:='wastage_entries';col:='created_at';else raise exception 'Invalid history kind';end case;
 execute format('select count(*) from public.%I where %I>=$1 and %I<$2',tab,col,col) into total using lo,hi;
 pagev:=least(greatest(coalesce(p_page,1),1),greatest(1,ceil(total/30.0)::int));
 execute format('select coalesce(jsonb_agg(to_jsonb(x) order by x.%I desc,x.id desc),''[]''::jsonb) from (select * from public.%I where %I>=$1 and %I<$2 order by %I desc,id desc limit 30 offset $3)x',col,tab,col,col,col) into rowsv using lo,hi,(pagev-1)::bigint*30;
 return jsonb_build_object('rows',rowsv,'total',total,'page',pagev,'page_size',30);
end $$;
