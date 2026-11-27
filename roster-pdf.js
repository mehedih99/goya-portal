(() => {
  'use strict';
  const $=id=>document.getElementById(id);
  const colors={ink:[21,44,76],line:[160,181,202],group:[216,233,250],morning:[220,234,245],closing:[214,242,224],off:[117,66,45],annual:[255,235,173],leave:[247,220,224],white:[255,255,255]};
  const days=['MON','TUE','WED','THU','FRI','SAT','SUN'];
  const add=(date,n)=>{const d=new Date(date+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);};
  const monday=date=>add(date,-((new Date(date+'T00:00:00Z').getUTCDay()+6)%7));
  const label=date=>new Date(date+'T00:00:00Z').toLocaleDateString('en-GB',{day:'2-digit',month:'short',timeZone:'UTC'});
  const clean=value=>String(value??'').replace(/[–—]/g,'-').replace(/[‘’]/g,"'").replace(/[“”]/g,'"');
  const clock=value=>{const [h,m]=value.split(':').map(Number);return (h%12||12)+(m?':'+String(m).padStart(2,'0'):'')+' '+(h<12?'AM':'PM');};
  let working=false;
  function content(day){
    if(!day)return '-';
    if(day.off_source)return day.off_source==='advance'?'Advance Off':'Paid Off';
    if(day.kind!=='Shift')return clean(day.kind);
    return [day.label,...(day.segments||[]).map(s=>clock(s.start)+'-'+clock(s.end)+(s.end<s.start?'*':'')+(s.break?' | '+s.break+'m break':''))].filter(Boolean).join('\n');
  }
  function color(day){
    return !day?colors.white:day.kind==='Weekly Off'?colors.off:day.kind==='Annual Leave'?colors.annual:
      day.kind!=='Shift'?colors.leave:day.segments?.[0]?.start<'12:00'?colors.morning:colors.closing;
  }
  function build(data,logo) {
    if(!data?.schedule?.staff || !data.staff?.length)throw Error('No published staff were found for this week.');
    const PDF=window.jspdf?.jsPDF;
    if(!PDF)throw Error('PDF tools are still loading. Please try again.');
    let doc=new PDF({orientation:'landscape',unit:'mm',format:'a4',compress:true});
    const width=297,margin=8,tableWidth=281,nameWidth=45,pendingWidth=16,dayWidth=(tableWidth-nameWidth-pendingWidth)/7;
    const people=new Map(data.staff.map(p=>[p.id,p]));
    const teams=['FOH','BOH',''];
    const rows=[];
    for(const group of teams){
      const members=Object.keys(data.schedule.staff).map(id=>people.get(id)||{id,name:'Former staff'})
        .filter(p=>(['FOH','BOH'].includes(p.roster_group)?p.roster_group:'')===group)
        .sort((a,b)=>a.name.localeCompare(b.name));
      if(!members.length)continue;
      rows.push({group:group==='FOH'?'FRONT OF HOUSE - FOH':group==='BOH'?'BACK OF HOUSE - BOH':'OTHER STAFF',count:members.length});
      for(const p of members){
        const balance=data.off_balances?.[p.id]?.balance;
        const pending=balance!==null&&balance!==undefined&&Number.isFinite(Number(balance))?String(Number(balance)):'-';
        rows.push({name:clean(p.name),days:data.schedule.staff[p.id],pending});
      }
    }
    const notes=[clean(data.schedule.notes).trim()];
    for(const row of rows)if(row.days)row.days.forEach((d,i)=>{if(d?.note?.trim())notes.push(row.name+' - '+label(add(data.week,i))+': '+clean(d.note).trim());});
    const noteText=notes.filter(Boolean).join('\n');
    const measureCanvas=document.createElement('canvas'),measure=measureCanvas.getContext('2d');
    const unicode=s=>/[^\x20-\xFF\n]/.test(s);
    function textWidth(text,size,bold=false){
      if(!unicode(text)){doc.setFont('helvetica',bold?'bold':'normal');doc.setFontSize(size);return doc.getTextWidth(text);}
      measure.font=(bold?'bold ':'')+(size*96/72)+'px Arial';
      return measure.measureText(text).width*25.4/96;
    }
    function wrap(text,limit,size,bold=false){
      return clean(text).split('\n').flatMap(part=>{
        const lines=[];let line='';
        for(const word of part.split(/\s+/)){
          if(line&&textWidth(line+' '+word,size,bold)>limit){lines.push(line.trimEnd());line='';}
          if(textWidth(word,size,bold)<=limit){line+=(line?' ':'')+word;continue;}
          for(const char of Array.from(word)){
            if(line&&textWidth(line+char,size,bold)>limit){lines.push(line.trimEnd());line='';}
            line+=char;
          }
        }
        lines.push(line.trimEnd());return lines;
      });
    }
    function draw(text,x,y,size,bold=false,ink=colors.ink,align='left'){
      doc.setTextColor(...ink);doc.setFont('helvetica',bold?'bold':'normal');doc.setFontSize(size);
      if(!unicode(text)){doc.text(text,x,y,{align});return;}
      const c=document.createElement('canvas'),ctx=c.getContext('2d'),px=size*4;
      ctx.font=(bold?'bold ':'')+px+'px Arial';
      c.width=Math.ceil(ctx.measureText(text).width)+8;c.height=Math.ceil(px*1.55);
      ctx.font=(bold?'bold ':'')+px+'px Arial';ctx.fillStyle='rgb('+ink.join(',')+')';ctx.textBaseline='alphabetic';ctx.fillText(text,4,px);
      const w=c.width/4*25.4/72,h=c.height/4*25.4/72;
      doc.addImage(c.toDataURL('image/png'),'PNG',x-(align==='center'?w/2:align==='right'?w:0),y-size*25.4/72,w,h);
    }
    let font=9.5,layout,total,noteLines;
    const plan=()=>{
      const lh=font*.3528*1.12;
      layout=rows.map(row=>row.group?{...row,height:6.2}:{
        ...row,lines:[wrap(row.name,nameWidth-4,font,true),...Array.from({length:7},(_,i)=>wrap(content(row.days[i]),dayWidth-3,font,true)),wrap(row.pending,pendingWidth-2,font,true)],
        height:0
      });
      for(const row of layout)if(!row.group)row.height=Math.max(font*.65+1,Math.max(...row.lines.map(x=>x.length))*lh+2.4);
      noteLines=noteText?wrap(noteText,tableWidth-23,font):[];
      total=36+layout.reduce((n,r)=>n+r.height,0)+11+(noteLines.length?Math.max(10,noteLines.length*lh+4):0)+10;
    };
    plan();
    while(total>210 && font>6.2){font=Math.max(6.2,font-.25);plan();}
    // Keep all staff and notes on one page, extending the sheet only for unusually large teams/notes.
    const height=Math.max(210,Math.ceil(total));
    if(height>210)doc=new PDF({orientation:width>height?'landscape':'portrait',unit:'mm',format:[width,height],compress:true});
    doc.setProperties({title:'GOYA Weekly Duty Roster - '+data.week,subject:'Published roster revision '+data.revision,creator:'GOYA'});
    doc.setLineWidth(.18);doc.setDrawColor(...colors.line);
    const logoInfo=doc.getImageProperties(logo),logoHeight=33*logoInfo.height/logoInfo.width;
    doc.addImage(logo,'PNG',margin,8+(12-logoHeight)/2,33,logoHeight);
    doc.line(44,8,44,22);draw('WEEKLY DUTY ROSTER',49,13.8,18,true);
    draw(label(data.week)+' - '+label(add(data.week,6))+' '+add(data.week,6).slice(0,4),49,21,10.5);
    doc.setFillColor(213,242,224);doc.roundedRect(254,8,35,7,2,2,'F');draw('PUBLISHED',271.5,12.8,9,true,[28,91,57],'center');
    draw(Object.keys(data.schedule.staff).length+' STAFF',289,21,10,true,colors.ink,'right');
    let y=27;
    doc.setFillColor(...colors.ink);doc.rect(margin,y,tableWidth,9,'F');
    draw('STAFF',margin+3,y+6,9.5,true,colors.white);
    for(let i=0;i<7;i++){const x=margin+nameWidth+i*dayWidth;draw(days[i]+' '+label(add(data.week,i)).toUpperCase(),x+dayWidth/2,y+6,8,true,colors.white,'center');}
    draw('PENDING',width-margin-pendingWidth/2,y+3.7,6.5,true,colors.white,'center');
    draw('OFF',width-margin-pendingWidth/2,y+7,6.5,true,colors.white,'center');
    y+=9;
    const lh=font*.3528*1.12;
    for(const row of layout){
      if(row.group){
        doc.setFillColor(...colors.group);doc.rect(margin,y,tableWidth,row.height,'FD');
        draw(row.group+' - '+row.count+' STAFF',margin+3,y+4.3,9,true);y+=row.height;continue;
      }
      let x=margin;
      row.lines.forEach((lines,i)=>{
        const w=i===8?pendingWidth:i?dayWidth:nameWidth,fill=i===8?colors.group:i?color(row.days[i-1]):colors.white;
        doc.setFillColor(...fill);doc.rect(x,y,w,row.height,'FD');
        const ink=fill===colors.off?colors.white:colors.ink;
        const top=y+(row.height-lines.length*lh)/2+font*.3528*.85;
        lines.forEach((line,j)=>draw(line,i?x+w/2:x+2,top+j*lh,font,true,ink,i?'center':'left'));
        x+=w;
      });
      y+=row.height;
    }
    y+=5;
    const legend=[['Morning',colors.morning],['Afternoon / Closing',colors.closing],['Weekly Off',colors.off],['Annual Leave',colors.annual],['Other Leave',colors.leave]];
    draw('LEGEND:',margin,y+2,7.7,true);
    let x=margin+19;
    for(const [name,fill]of legend){doc.setFillColor(...fill);doc.roundedRect(x,y-1,6,4,1,1,'F');draw(name,x+8,y+2,7.5);x+=textWidth(name,7.5)+14;}
    y+=7;
    if(noteLines.length){
      const h=Math.max(10,noteLines.length*lh+4);
      doc.setFillColor(242,246,251);doc.rect(margin,y,tableWidth,h,'F');
      draw('NOTES',margin+2,y+5,font,true);
      noteLines.forEach((line,i)=>draw(line,margin+23,y+3+font*.3528*.85+i*lh,font));
      y+=h+3;
    }
    const footer=Math.max(y+3,height-7);
    doc.line(margin,footer-3,width-margin,footer-3);
    draw('* Overnight shifts end the following day.',margin,footer,7.2);
    draw('Revision '+data.revision+' | Page 1 of 1',width-margin,footer,7.2,false,colors.ink,'right');
    if(doc.getNumberOfPages()!==1)throw Error('The roster could not be fitted to one page.');
    return doc;
  }
  async function download(){
    if(working)return;
    const button=$('roster-download-pdf'),status=$('roster-status'),ctx=window.GoyaAttendance?._liveContext();
    if(!ctx?.token)return;
    working=true;button.disabled=true;
    try{
      const value=$('roster-week').value;
      if(!/^\d{4}-\d{2}-\d{2}$/.test(value))throw Error('Select a roster week first.');
      const week=monday(value),cfg=window.GOYA_CONFIG;
      const client=window.supabase.createClient(cfg.SUPABASE_URL,cfg.SUPABASE_ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
      const [published,balances]=await Promise.all([
        client.rpc('goya_roster_published_export',{p_token:ctx.token,p_week:week}),
        client.rpc('goya_management_balances',{p_token:ctx.token})
      ]);
      if(published.error)throw Error(published.error.message);
      if(balances.error)throw Error(balances.error.message);
      const data=published.data?{...published.data,off_balances:balances.data}:null;
      if(window.GoyaAttendance?._liveContext()?.token!==ctx.token)return;
      const logo=window.GoyaRosterPdfLogo;
      if(!logo)throw Error('The roster logo is still loading. Please refresh and try again.');
      const doc=build(data,logo);
      window.GoyaBranches.savePdf(doc,'GOYA-Weekly-Roster-'+week+'-to-'+add(week,6)+'.pdf');
      status.textContent='Published roster PDF downloaded.';
    }catch(error){status.textContent=error.message||'Unable to download the roster PDF.';}
    finally{working=false;button.disabled=$('roster-download').disabled;}
  }
  const button=$('roster-download-pdf'),csv=$('roster-download');
  if(!button||!csv)return;
  const sync=()=>{if(!working)button.disabled=csv.disabled;};
  new MutationObserver(sync).observe(csv,{attributes:true,attributeFilter:['disabled']});
  button.onclick=download;sync();
})();
