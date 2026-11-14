(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const form = $('editor');
  const sources = {
    sales: ['Sales by Branch','https://console.foodics.com/reports/sales-by-branch'],
    stock: ['Inventory Control','https://console.foodics.com/reports/inventory-control'],
    payments: ['Payments','https://console.foodics.com/reports/payments'],
    suppliers: ['Suppliers','https://bi.foodics.com/home/dashboards/suppliers'],
    types: ['Order Type','https://console.foodics.com/reports/sales-by-branch?group_by=order_type'],
  };
  const partners = ['Talabat','Keeta','Noon Food','Deliveroo'];
  const processors = ['Network POS','Qlub','Beanz'];
  const costs = ['Salary and overtime','Rent','Utilities','Packaging','Maintenance','Pest Control','Other operating expenses'];
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]);
  const amount = n => n == null ? 'N/A' : n.toLocaleString('en-AE',{minimumFractionDigits:2,maximumFractionDigits:2});
  const margin = (value, net) => net ? (100*value/net).toFixed(1)+'%' : 'N/A';
  const rounded = n => Math.round(n*100)/100;
  const field = name => form.elements.namedItem(name);
  const val = name => field(name).value;
  const sum = values => values.reduce((a,b) => a+b,0);
  const normalized = s => String(s).trim().toLowerCase();
  let imports = {}, history = [], editing = null, current = null, busy = false;
  let token = sessionStorage.getItem('goya-pnl-handoff') || localStorage.getItem('goya-admin-session-v1');
  sessionStorage.removeItem('goya-pnl-handoff');
  let db;

  function status(message) { $('status').textContent = message; }
  async function rpc(name,args={}) {
    const {data,error} = await db.rpc('goya_pnl_'+name,{p_token:token,...args}).abortSignal(AbortSignal.timeout(20000));
    if (error) {
      if (error.code==='28000' || /invalid session|session expired|unauthorized/i.test(error.message)) {
        token = null;
        $('workspace').hidden = true;
        $('preview').hidden = true;
      }
      throw Error(error.message);
    }
    return data;
  }
  async function run(action) {
    if (busy) return;
    busy = true;
    try { await action(); }
    catch (e) { status(e.message); }
    finally { busy = false; }
  }
  function table(head,rows) {
    return '<table><thead><tr>'+head.map(v=>'<th>'+esc(v)+'</th>').join('')+'</tr></thead><tbody>'+
      rows.map(row=>'<tr'+(/^Total/.test(row[0])?' class="total"':'')+'>'+row.map(v=>'<td>'+esc(v)+'</td>').join('')+'</tr>').join('')+'</tbody></table>';
  }
  function numberField(name,label,max='') {
    return '<input type="number" min="0" step="0.01" '+(max?'max="'+max+'" ':'')+'name="'+name+'" aria-label="'+esc(label)+'" placeholder="0">';
  }
  function inputTable(id, labels, cols, prefix) {
    $(id).innerHTML = '<thead><tr><th>Name</th>'+cols.map(c=>'<th>'+c+'</th>').join('')+'</tr></thead><tbody>'+
      labels.map((name,i)=>'<tr><th scope="row">'+esc(name)+'</th>'+cols.map((col,j)=>'<td>'+numberField(prefix+i+'_'+j,name+' '+col,col.includes('%')?'100':'')+'</td>').join('')+'</tr>').join('')+'</tbody>';
  }
  $('uploads').innerHTML = Object.entries(sources).map(([key,[label,url]])=>
    '<div class="field"><label for="csv-'+key+'">'+label+' CSV</label><input type="file" id="csv-'+key+'" accept=".csv,text/csv">'+
    '<small id="file-'+key+'">No file selected</small><a href="'+url+'" target="_blank" rel="noopener noreferrer">Open Foodics report ↗</a></div>').join('');
  inputTable('partners',partners,['Gross sales','Discount','Refund','Fee %'],'partner');
  inputTable('fees',processors,['Payment amount override','Fee %','Actual fee'],'processor');
  $('expenses').innerHTML = costs.map((label,i)=>'<label class="field">'+label+numberField('cost'+i,label)+'</label>').join('');
  function num(value, label) {
    const text = String(value ?? '').trim().replaceAll(',','');
    if (!text || !Number.isFinite(Number(text))) throw Error('Invalid number for '+label+'.');
    return Number(text);
  }
  function parse(key,text) {
    const book = XLSX.read(text.replace(/^\uFEFF/,''),{type:'string',raw:true,FS:','});
    const rows = XLSX.utils.sheet_to_json(book.Sheets[book.SheetNames[0]],{defval:''});
    if (!rows.length) {
      if (key==='suppliers') return [];
      throw Error('The CSV has no report rows.');
    }
    function cell(row,name) {
      if (!(name in row)) throw Error('Missing CSV column '+name+'.');
      return row[name];
    }
    function matchBranch(value) { return /^goya cafe\s*-\s*jarir bookstore(?:\s+b01)?$/i.test(String(value).trim()); }
    const branchColumn = {sales:'Branch',stock:'Branch',suppliers:'BRANCH_NAME',types:'Branch'}[key];
    const selected = branchColumn ? rows.filter(r=>matchBranch(cell(r,branchColumn))) : rows;
    if (!selected.length) throw Error('The CSV does not contain Goya Cafe–Jarir Bookstore.');
    const read = (row,key)=>num(cell(row,key),key);
    const total = key=>sum(selected.map(row=>read(row,key)));
    if (key==='sales') {
      if (selected.length!==1 || 'Order Type' in selected[0]) throw Error('Upload the branch summary without Order Type grouping.');
      const row=selected[0];
      return {net:read(row,'Net Sales'),gross:read(row,'Gross Sales Without Tax'),discount:read(row,'Discount Amount'),returns:read(row,'Return Amount')};
    }
    if (key==='stock') {
      if (selected.every(r=>read(r,'Closing Quantity')===0 && read(r,'Closing Cost')===0) &&
          selected.some(r=>Math.abs(read(r,'Opening Quantity')+read(r,'Total in Quantity')-read(r,'Total Out Quantity'))>0.01)) {
        throw Error('Closing stock is zero across the report despite inventory movements. Verify and re-export Foodics.');
      }
      return {opening:total('Opening Cost'),purchase:total('Purchasing Cost'),closing:total('Closing Cost'),
        returns:total('Return to Supplier Cost'),transferIn:total('Transfer Receiving Cost'),transferOut:total('Transfer Sending Cost'),
        returnTransfer:total('Return Transfer Cost')};
    }
    if (key==='suppliers') {
      const grouped = new Map();
      for (const row of selected) {
        const name=String(cell(row,'SUPPLIER_NAME')).trim() || 'Unassigned supplier';
        const code=String(cell(row,'SUPPLIER_CODE')).trim() || name;
        const entry=grouped.get(code) || {name,gross:0,returns:0};
        entry.gross+=read(row,'PURCHASING_COST');
        entry.returns+=read(row,'RETURN_TO_SUPPLIER_COST');
        grouped.set(code,entry);
      }
      return [...grouped.values()].map(row=>({...row,gross:rounded(row.gross),returns:rounded(row.returns)}));
    }
    const label=key==='types'?'Order Type':'Payment Method';
    const metric=key==='types'?'Net Sales':'Net Amount';
    const grouped=new Map();
    for(const row of selected) {
      const name=normalized(cell(row,label));
      grouped.set(name,(grouped.get(name)||0)+read(row,metric));
    }
    return Object.fromEntries(grouped);
  }
  function invalidate() {
    current=null;
    $('preview').hidden=true;
    $('save').disabled=true;
    $('print').disabled=true;
  }
  for (const key of Object.keys(sources)) {
    const input=$('csv-'+key);
    input.addEventListener('change',async ()=>{
      const file=input.files[0];
      if (!file) return;
      invalidate();
      delete imports[key];
      $('file-'+key).textContent='Reading…';
      try {
        if (file.size>15_000_000) throw Error('Export exceeds 15 MB.');
        const data = parse(key,await file.text());
        if (input.files[0]!==file) return;
        invalidate();
        imports[key]={name:file.name,data};
        $('file-'+key).textContent=file.name;
        status(sources[key][0]+' imported.');
      } catch (error) {
        if (input.files[0]!==file) return;
        $('file-'+key).textContent='Import failed';
        status(sources[key][0]+' — '+error.message);
      }
    });
  }
  form.addEventListener('input',invalidate);
  const getValue = (name,fallback=0) => val(name)==='' ? fallback : num(val(name),name);
  const getImport = (data,key) => data.imports[key]?.data;
  function metrics(data) {
    const sales=getImport(data,'sales');
    const stock=getImport(data,'stock');
    const payment=getImport(data,'payments') || {};
    const paymentOf=name=>payment[name] ?? 0;
    const defaults=[paymentOf('visa')+paymentOf('mastercard'),paymentOf('qlub'),paymentOf('beanz')];
    const delivery = data.delivery.map(([gross,discount,refund,rate],i)=>{
      const net=rounded(gross-discount-refund);
      if(net<0) throw Error(partners[i]+' discounts and refunds exceed gross sales.');
      return {name:partners[i],gross,discount,refund,net,rate,fee:rounded(net*rate/100)};
    });
    const fees = data.processing.map(([base,rate,actual],i)=>{
      const effectiveBase=base ?? defaults[i];
      return {name:processors[i],base:effectiveBase,rate,actual,fee:actual ?? rounded(effectiveBase*rate/100)};
    });
    const cogs=rounded(stock.opening+stock.purchase-stock.returns+stock.transferIn+stock.returnTransfer-stock.transferOut-stock.closing);
    const deliveryFees=rounded(sum(delivery.map(row=>row.fee)));
    const payFees=rounded(sum(fees.map(row=>row.fee)));
    const expenses=rounded(sum(data.costs)+deliveryFees+payFees);
    const profit=rounded(sales.net-cogs-expenses);
    return {sales,stock,delivery,fees,cogs,deliveryFees,payFees,expenses,profit};
  }
  function collect() {
    const start=val('start'),end=val('end');
    if (!start || !end || end<start || start.slice(0,7)!==end.slice(0,7)) throw Error('Choose a date range within one month.');
    if (!imports.sales || !imports.stock) throw Error('Sales by Branch and Inventory Control CSVs are required.');
    return {version:1,start,end,imports:structuredClone(imports),
      delivery:partners.map((_,i)=>[0,1,2,3].map(j=>getValue('partner'+i+'_'+j))),
      processing:processors.map((_,i)=>[getValue('processor'+i+'_0',null),getValue('processor'+i+'_1'),getValue('processor'+i+'_2',null)]),
      costs:costs.map((_,i)=>getValue('cost'+i)),manager:val('manager').trim(),suggestions:val('suggestions').trim()};
  }
  function chart(rows) {
    const max=Math.max(1,...rows.map(([,v])=>Math.abs(v??0)));
    return rows.map(([label,v])=>'<div class="pnl-chart"><div class="pnl-bar-label"><span>'+esc(label)+'</span><strong>'+amount(v)+'</strong></div>'+
      (v==null?'':'<div class="pnl-track"><span class="'+(v<0?'negative':'')+'" style="width:'+Math.abs(v)/max*100+'%"></span></div>')+'</div>').join('');
  }
  function profitTrend(rows) {
    const ceiling=Math.max(1,...rows.map(([,value])=>Math.abs(value??0)));
    return '<div class="pnl-trend">'+rows.map(([label,value])=>{
      const height=Math.abs(value??0)/ceiling*44;
      return '<div><div class="pnl-trend-plot">'+(value==null?'<small>N/A</small>':
        '<span class="'+(value<0?'loss':'')+'" style="height:'+height+'%;top:'+(value<0?50:50-height)+'%"></span>')+
        '</div><small>'+esc(label.split(' ')[0])+'</small><br><small>'+ (value==null?'':amount(value))+'</small></div>';
    }).join('')+'</div>';
  }
  function dateOf(s) {return new Date(s+'T00:00:00Z');}
  function shift(s, offset) {
    const date=dateOf(s), y=date.getUTCFullYear(), m=date.getUTCMonth()+offset, day=date.getUTCDate();
    const last=new Date(Date.UTC(y,m+1,0)).getUTCDate();
    return new Date(Date.UTC(y,m,Math.min(day,last))).toISOString().slice(0,10);
  }
  function isMonthEnd(s) {
    const next=dateOf(s);
    next.setUTCDate(next.getUTCDate()+1);
    return next.getUTCDate()===1;
  }
  function matching(data,offset) {
    const start=shift(data.start,offset);
    let end=shift(data.end,offset);
    if (data.start.endsWith('-01') && isMonthEnd(data.end)) {
      const d=dateOf(end);
      end=new Date(Date.UTC(d.getUTCFullYear(),d.getUTCMonth()+1,0)).toISOString().slice(0,10);
    } else if (start.slice(-2)!==data.start.slice(-2) || end.slice(-2)!==data.end.slice(-2)) return null;
    return history.find(row=>row.start_date===start && row.end_date===end)?.payload || null;
  }
  function month(s) {return dateOf(s).toLocaleDateString('en-GB',{month:'short',year:'numeric',timeZone:'UTC'});}
  function render(data) {
    const m=metrics(data), {sales,stock,delivery,fees,cogs,deliveryFees,payFees,expenses,profit}=m;
    const previous=matching(data,-1);
    const prev=previous?metrics(previous):null;
    const payment=getImport(data,'payments') || {};
    const order=getImport(data,'types') || {};
    const supplier=getImport(data,'suppliers');
    const netPartner=rounded(sum(delivery.map(r=>r.net)));
    const difference=Object.keys(order).length?rounded(sum(Object.values(order))-sales.net):null;
    const footer='<p class="pnl-caption">GOYA / JARIR BOOKSTORE · '+esc(data.start)+' to '+esc(data.end)+' · AED</p>';
    const head=title=>'<header><div class="pnl-heading"><strong>GOYA / JARIR BOOKSTORE</strong><span>'+esc(data.start)+' to '+esc(data.end)+'</span></div><h1>'+title+'</h1><div class="pnl-caption">AED · Net sales excluding VAT</div></header>';
    const trend=Array.from({length:6},(_,i)=>{
      const offset=i-5, prior=offset?matching(data,offset):data;
      return [month(shift(data.start,offset)),prior?metrics(prior).profit:null];
    });
    const kpi=(label,value,prior)=>'<div>'+label+'<strong>'+value+'</strong><span class="pnl-caption">Previous month '+prior+'</span></div>';
    const values = [['Net sales',sales.net,prev?.sales.net],['COGS estimate',cogs,prev?.cogs],['Operating expenses',expenses,prev?.expenses],['Operating profit',profit,prev?.profit]];
    const comparison=values.map(([label,now,old])=>[label,amount(now),amount(old),amount(old==null?null:rounded(now-old))]);
    comparison.push(['Operating margin',margin(profit,sales.net),prev?margin(prev.profit,prev.sales.net):'N/A',
      prev&&prev.sales.net&&sales.net?(100*(profit/sales.net-prev.profit/prev.sales.net)).toFixed(1)+' pp':'N/A']);

    let supplierSection='<p>Supplier CSV unavailable.</p>';
    if (supplier) {
      const ranked=[...supplier].sort((a,b)=>(b.gross-b.returns)-(a.gross-a.returns));
      const aggregate=(name,rows)=>({name,gross:rounded(sum(rows.map(r=>r.gross))),returns:rounded(sum(rows.map(r=>r.returns)))});
      const total=aggregate('Total',ranked), list=ranked.slice(0,5);
      if(ranked.length>5) list.push(aggregate('Other Suppliers ('+(ranked.length-5)+')',ranked.slice(5)));
      list.push(total);
      supplierSection=table(['Supplier','Purchases','Returns','Net purchases','Share'],list.map(r=>[r.name,amount(r.gross),amount(r.returns),amount(rounded(r.gross-r.returns)),margin(r.gross-r.returns,total.gross-total.returns)]));
      if(total.gross!==rounded(stock.purchase) || total.returns!==rounded(stock.returns)) supplierSection+='<p class="pnl-caption">Supplier export and Inventory Control totals differ. Inventory Control sets COGS.</p>';
    }

    const displayedStockCogs=rounded(stock.opening)+rounded(stock.purchase)-rounded(stock.returns)+rounded(stock.transferIn+stock.returnTransfer-stock.transferOut)-rounded(stock.closing);
    const stockRounding=rounded(cogs-displayedStockCogs);
    const sourceNotes=[
      'Inventory COGS includes items in the Inventory Control export. Check any packaging overlap with operating expenses.',
      'Partner revenue is shown for reference. Foodics Sales by Branch supplies P&L revenue.',
    ];
    if (difference) sourceNotes.push('Order Type total differs from branch sales by AED '+amount(difference)+'.');
    if(data.processing[0][0]==null && data.processing[0][2]==null && data.processing[0][1]) sourceNotes.push('Estimated Network POS fees assume all Visa and Mastercard payments use Network POS.');
    if(!getImport(data,'payments')) sourceNotes.push('Payments CSV unavailable. Fee calculation uses manual overrides or actual charges.');
    if(fees.some(row=>row.actual==null && row.rate)) sourceNotes.push('Estimated processing fees use net payment amounts and exclude tips.');

    const lines = [['Net sales',sales.net],['Inventory COGS estimate',cogs],['Gross profit',rounded(sales.net-cogs)],
      ...costs.map((label,i)=>[label,data.costs[i]]),['Delivery partner fees',deliveryFees],['Payment processing fees',payFees],
      ['Total operating expenses',expenses],['Operating profit',profit]];
    $('preview').innerHTML=
      '<section class="pnl-sheet">'+head('Monthly performance')+'<div class="pnl-summary">'+
      kpi('Operating Profit',amount(profit),amount(prev?.profit))+kpi('Net Sales',amount(sales.net),amount(prev?.sales.net))+
      kpi('Operating Margin',margin(profit,sales.net),prev?margin(prev.profit,prev.sales.net):'N/A')+'</div>'+
      '<div class="pnl-columns"><section><h2>Profit trend</h2>'+profitTrend(trend)+'</section><section><h2>Delivery partners</h2>'+chart(delivery.map(r=>[r.name,r.net]))+
      '<p>Total net revenue AED '+amount(netPartner)+'</p></section></div>'+
      '<h2>Gross sales to net sales</h2>'+table(['Gross sales ex VAT','Discounts','Returns reported','Net sales'],[[sales.gross,sales.discount,sales.returns,sales.net].map(amount)])+
      '<p class="pnl-caption">Foodics sales already reflect returns.</p><div class="pnl-columns"><section><h2>Payment mix</h2>'+
      chart(['Visa','Mastercard','Qlub','Beanz','Cash'].map(label=>[label,payment[normalized(label)]??null]))+
      '</section><section><h2>Order type</h2>'+chart([['Dine In',order['dine in']??null],['Pickup',order['pick up']??order.pickup??null],['Drive Thru',order['drive thru']??null],['All Aggregators',netPartner]])+
      '<p class="pnl-caption">Aggregator figures may overlap with Foodics order types.</p></section></div>'+footer+'</section>'+
      '<section class="pnl-sheet">'+head('Sales and purchasing')+'<h2>Delivery partner charges</h2>'+
      table(['Partner','Gross','Discount','Refund','Rate','Fee'],delivery.map(r=>[r.name,amount(r.gross),amount(r.discount),amount(r.refund),r.rate+'%',amount(r.fee)]).concat([['Total',amount(sum(delivery.map(r=>r.gross))),amount(sum(delivery.map(r=>r.discount))),amount(sum(delivery.map(r=>r.refund))),'',amount(deliveryFees)]]))+
      '<h2>Period comparison</h2>'+table(['Metric','Current','Previous','Change'],comparison)+
      '<h2>Purchases by supplier</h2>'+supplierSection+footer+'</section>'+
      '<section class="pnl-sheet">'+head('Operating statement')+table(['Line item','AED','% of net sales'],lines.map(([label,n])=>[label,amount(n),margin(n,sales.net)]))+
      '<div class="pnl-columns"><section><h2>Inventory cost</h2>'+table(['Line item','AED'],[
        ['Opening stock',stock.opening],['Purchases',stock.purchase],['Supplier returns',-stock.returns],
        ...(stock.transferIn || stock.transferOut || stock.returnTransfer?[['Net transfers',stock.transferIn+stock.returnTransfer-stock.transferOut]]:[]),
        ['Closing stock',-stock.closing],
        ...(stockRounding?[['Rounding',stockRounding]]:[]),
        ['Total COGS estimate',cogs],
      ].map(([label,n])=>[label,amount(n)]))+'</section><section><h2>Payment processing fees</h2>'+
      table(['Provider','AED'],fees.map(r=>[r.name,amount(r.fee)]).concat([['Total',amount(payFees)]]))+'</section></div>'+
      '<p class="pnl-caption">'+sourceNotes.map(esc).join('\n')+'</p>'+
      (data.suggestions?'<h2>Manager suggestions</h2><p>'+esc(data.suggestions)+'</p>':'')+
      '<p><strong>Prepared by '+esc(data.manager)+'</strong></p>'+footer+'</section>';
    $('preview').hidden=false;
    $('save').disabled=false;
    $('print').disabled=false;
  }
  function reset() {
    form.reset();
    imports={};
    editing=null;
    for(const key of Object.keys(sources)) $('file-'+key).textContent='No file selected';
    field('start').readOnly=field('end').readOnly=false;
    invalidate();
  }
  function edit(row) {
    reset();
    editing=row;
    const data=row.payload;
    imports=structuredClone(data.imports);
    field('start').value=row.start_date;
    field('end').value=row.end_date;
    field('start').readOnly=field('end').readOnly=true;
    for(const [key,file] of Object.entries(imports)) $('file-'+key).textContent=file.name+' (saved)';
    data.delivery.forEach((values,i)=>values.forEach((v,j)=>{field('partner'+i+'_'+j).value=v;}));
    data.processing.forEach((values,i)=>values.forEach((v,j)=>{field('processor'+i+'_'+j).value=v??'';}));
    data.costs.forEach((v,i)=>{field('cost'+i).value=v;});
    field('suggestions').value=data.suggestions;
    field('manager').value=data.manager;
    current=collect();
    render(current);
    form.scrollIntoView();
  }
  async function refresh() {
    history=await rpc('history');
    $('reports').replaceChildren();
    if(!history.length) $('reports').textContent='No saved reports.';
    for(const row of history) {
      const div=document.createElement('div');
      div.className='pnl-history-row';
      const title=document.createElement('strong');
      title.textContent=row.start_date+' to '+row.end_date;
      div.append(title);
      for(const label of ['Open / edit','Delete']) {
        const button=document.createElement('button');
        button.type='button';
        button.className='btn secondary';
        button.textContent=label;
        button.onclick=()=>run(async ()=>{
          if(label==='Open / edit') {
            edit(row);
            status('Report opened.');
          } else if(confirm('Delete the P&L report for '+title.textContent+'?')) {
            await rpc('delete',{p_start:row.start_date,p_end:row.end_date,p_expected:row.updated_at});
            if(editing?.start_date===row.start_date && editing?.end_date===row.end_date) reset();
            await refresh();
            status('P&L report deleted.');
          }
        });
        div.append(button);
      }
      $('reports').append(div);
    }
  }
  form.addEventListener('submit',e=>{
    e.preventDefault();
    if(busy) return;
    try {
      invalidate();
      const data=collect();
      render(data);
      current=data;
      $('preview').scrollIntoView({behavior:'smooth'});
      status('Report preview ready.');
    } catch(e) {status(e.message);}
  });
  $('save').onclick=()=>run(async ()=>{
    if(!current) return;
    const data=current;
    status('Saving report…');
    await rpc('save',{p_start:data.start,p_end:data.end,p_payload:data,p_expected:editing?.updated_at??null});
    $('save').disabled=true;
    await refresh();
    editing=history.find(row=>row.start_date===data.start&&row.end_date===data.end);
    if(current===data) {
      field('start').readOnly=field('end').readOnly=true;
      $('save').disabled=false;
    }
    status('Report saved to history.');
  });
  $('print').onclick=()=>{if(current) window.print();};
  $('new-report').onclick=()=>{if(!busy){reset();status('New report.');}};
  run(async ()=>{
    if (!token) throw Error('Open P&L from the unlocked Admin Panel.');
    db=window.supabase.createClient(GOYA_CONFIG.SUPABASE_URL,GOYA_CONFIG.SUPABASE_ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
    await refresh();
    $('workspace').hidden=false;
    status('');
  });
})();
