(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const names = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
  const kinds = ['Shift','Weekly Off','Annual Leave','Sick Leave','Other Leave'];
  const esc = value => String(value ?? '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[ch]);
  const dubaiDate = (date = new Date()) => new Intl.DateTimeFormat('sv-SE',{timeZone:'Asia/Dubai',year:'numeric',month:'2-digit',day:'2-digit'}).format(date);
  function add(date, amount) {
    const next = new Date(date+'T00:00:00Z');
    next.setUTCDate(next.getUTCDate()+amount);
    return next.toISOString().slice(0,10);
  }
  function monday(date) {
    return add(date,-((new Date(date+'T00:00:00Z').getUTCDay()+6)%7));
  }
  const shortDate = date => new Date(date+'T00:00:00Z').toLocaleDateString('en-GB',{day:'numeric',month:'short',timeZone:'UTC'});
  const describe = day => !day ? 'Not scheduled' : day.kind!=='Shift' ? day.kind :
    day.segments.map(s=>s.start+'–'+s.end+(s.end<s.start?' (+1 day)':'')+(s.break?' · '+s.break+'m break':'')).join(' / ');
  const context = () => $('roster-admin') ? window.GoyaAttendance?._liveContext() : window.GoyaStaff?._liveContext();
  let client, revision=0, staff=[], schedule, activeWeek, request=0, busy=false;
  let dirty=false, publishedStaff=null, approvedLeave=[], staffWeeks=[], reminderRequest=0;
  async function rpc(name, args) {
    const token=context()?.token;
    if (!token) throw Error('Sign in to view the roster.');
    const cfg=window.GOYA_CONFIG;
    client ||= window.supabase.createClient(cfg.SUPABASE_URL,cfg.SUPABASE_ANON_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
    const {data,error}=await client.rpc(name,{p_token:token,...args});
    if (context()?.token!==token) throw Error('Your session changed. Open the roster again.');
    if (error) throw Error(error.message);
    return data;
  }
  function status(message) { $('roster-status').textContent=message; }
  function weekLabel(week) {return shortDate(week)+' – '+shortDate(add(week,6))+' '+week.slice(0,4);}
  function resetEditor() {
    $('roster-edit').close();
    $('roster-notes').value='';
    $('roster-grid').replaceChildren();
    $('roster-history').replaceChildren();
    $('roster-actions').hidden=true;
    revision=0;
    staff=[];
    schedule=null;
    activeWeek=null;
    dirty=false;
    publishedStaff=null;
    approvedLeave=[];
  }
  async function loadAdmin(date) {
    if (busy || !date) return;
    if (dirty && !confirm('Discard unsaved roster edits?')) {
      $('roster-week').value=activeWeek;
      return;
    }
    const week=monday(date), id=++request;
    resetEditor();
    $('roster-week').value=week;
    status('Loading roster…');
    try {
      const data=await rpc('goya_roster_admin_week',{p_week:week});
      if(id!==request) return;
      activeWeek=week;
      revision=data.draft?.revision || 0;
      schedule=data.draft?.draft || {staff:{},notes:''};
      staff=data.staff;
      approvedLeave=data.approved_leave || [];
      publishedStaff=data.draft?.published_staff || null;
      $('roster-download').disabled=!publishedStaff;
      for(const member of staff) schedule.staff[member.id] ||= Array(7).fill(null);
      $('roster-notes').value=schedule.notes;
      $('roster-history').replaceChildren(...data.history.map(entry=>{
        const item=document.createElement('li');
        item.textContent='Revision '+entry.revision+' · '+new Date(entry.published_at).toLocaleString('en-AE',{timeZone:'Asia/Dubai'});
        return item;
      }));
      renderAdmin();
      $('roster-actions').hidden=false;
      status(data.draft?.published_revision===revision?'Published':revision?'Saved draft':'New draft');
    } catch(error) { if(id===request) status(error.message); }
  }
  function approvedDay(id,index) {
    const date=add(activeWeek,index);
    return approvedLeave.find(leave=>leave.staff_id===id && date>=leave.from && date<=leave.to);
  }
  function effectiveDay(id,index,day) {
    const leave=approvedDay(id,index);
    return leave ? {kind:leave.kind,segments:[],note:''} : day;
  }
  function renderAdmin() {
    const grid=$('roster-grid');
    grid.innerHTML='<thead><tr><th>Staff</th>'+names.map((name,i)=>'<th>'+name+'<br>'+shortDate(add(activeWeek,i))+'</th>').join('')+'</tr></thead>'+
      '<tbody>'+staff.map(member=>'<tr><th scope="row">'+esc(member.name)+'</th>'+schedule.staff[member.id].map((day,i)=>{
        const leave=approvedDay(member.id,i), text=describe(effectiveDay(member.id,i,day));
        return '<td><button type="button" class="btn secondary" data-roster-staff="'+esc(member.id)+'" data-roster-day="'+i+
          '" aria-label="'+esc(member.name+' '+names[i]+': '+text+(leave?' (approved request)':''))+'"'+
          (leave?' disabled title="Change approved dates in Staff Requests"':'')+'>'+esc(text)+'</button></td>';
      }).join('')+'</tr>').join('')+'</tbody>';
  }
  async function save(publish) {
    if(busy || !schedule) return;
    busy=true;
    $('roster-actions').disabled=true;
    $('roster-week').disabled=true;
    try {
      const activeStaff=new Set(staff.map(member=>member.id));
      const former=Object.keys(schedule.staff).filter(id=>!activeStaff.has(id));
      if(publish && former.length && !confirm('Exclude inactive staff from this publication? Earlier publications will be kept.')) return;
      schedule.notes=$('roster-notes').value.trim();
      const submitted=publish?{...schedule,staff:Object.fromEntries(Object.entries(schedule.staff).filter(([id])=>activeStaff.has(id)))}:schedule;
      const saved=await rpc('goya_roster_save',{p_week:activeWeek,p_expected:revision,p_schedule:submitted,p_publish:publish});
      schedule=submitted;
      revision=saved;
      dirty=false;
      status(publish?'Roster published.':'Draft saved.');
      if(publish) {
        publishedStaff=Object.fromEntries(Object.entries(submitted.staff).map(([id,days])=>
          [id,days.map((day,i)=>effectiveDay(id,i,day))]));
        $('roster-download').disabled=false;
        const item=document.createElement('li');
        item.textContent='Revision '+saved+' · Published';
        $('roster-history').prepend(item);
      }
    } catch(error) {status(error.message);}
    finally {busy=false;$('roster-actions').disabled=false;$('roster-week').disabled=false;}
  }
  async function copyLast() {
    if(busy || !schedule) return;
    if(staff.some(m=>schedule.staff[m.id].some(Boolean)) && !confirm('Replace this draft’s shifts with last week’s shifts and weekly offs?')) return;
    busy=true;
    $('roster-actions').disabled=true;
    $('roster-week').disabled=true;
    const week=activeWeek, id=request;
    try {
      const previous=await rpc('goya_roster_admin_week',{p_week:add(week,-7)});
      if(id!==request) return;
      const previousStaff=previous.draft?.published_staff;
      if(!previousStaff) throw Error('No published roster was found for last week.');
      for(const member of staff) schedule.staff[member.id]=(previousStaff[member.id] || Array(7).fill(null)).map(day=>
        day && ['Shift','Weekly Off'].includes(day.kind)?{...day,note:''}:null);
      dirty=true;
      renderAdmin();
      status('Last week’s shifts and weekly offs copied. Review before publishing.');
    } catch(error) {status(error.message);}
    finally {busy=false;$('roster-actions').disabled=false;$('roster-week').disabled=false;}
  }
  function initAdmin() {
    const picker=$('roster-week'), dialog=$('roster-edit'), form=$('roster-day-form');
    picker.addEventListener('change',()=>loadAdmin(picker.value));
    $('roster-notes').addEventListener('input',()=>{dirty=true;});
    $('roster-grid').addEventListener('click',event=>{
      const button=event.target.closest('[data-roster-staff]');
      if(!button || busy || !schedule) return;
      const id=button.dataset.rosterStaff, index=Number(button.dataset.rosterDay), day=schedule.staff[id][index];
      form.reset();
      $('roster-edit-status').textContent='';
      form.dataset.staff=id;
      form.dataset.day=index;
      $('roster-edit-title').textContent=staff.find(m=>m.id===id).name+' · '+names[index];
      form.elements.kind.value=day?.kind || '';
      form.elements.note.value=day?.note || '';
      (day?.segments||[]).forEach((s,i)=>{
        form.elements['start'+i].value=s.start;
        form.elements['end'+i].value=s.end;
        form.elements['break'+i].value=s.break;
      });
      updateInputs();
      dialog.showModal();
    });
    function updateInputs() {
      const isShift=form.elements.kind.value==='Shift';
      $('roster-times').hidden=!isShift;
      $('roster-times').disabled=!isShift;
    }
    form.elements.kind.addEventListener('change',updateInputs);
    $('roster-cancel').addEventListener('click',()=>dialog.close());
    form.addEventListener('submit',event=>{
      event.preventDefault();
      const {staff:id,day:index}=form.dataset;
      const {kind,note}=form.elements;
      const segments=[];
      if(kind.value==='Shift') {
        for(let i=0;i<2;i++){
          const start=form.elements['start'+i].value,end=form.elements['end'+i].value;
          const pause=Number(form.elements['break'+i].value)||0;
          if(i===1&&!start&&!end&&!pause) continue;
          if(!start||!end) {$('roster-edit-status').textContent='Enter a start and end time for each shift block.';return;}
          segments.push({start,end,break:pause});
        }
      }
      schedule.staff[id][index]=kind.value?{kind:kind.value,segments,note:note.value.trim()}:null;
      dirty=true;
      renderAdmin();
      dialog.close();
    });
    $('roster-draft').addEventListener('click',()=>save(false));
    $('roster-publish').addEventListener('click',()=>save(true));
    $('roster-copy').addEventListener('click',copyLast);
    $('roster-download').addEventListener('click',()=>{
      if(!publishedStaff) return;
      const quote=value=>{
        const text=String(value);
        return '"'+(/^[=+@-]/.test(text)?"'":'')+text.replaceAll('"','""')+'"';
      };
      const rows=[['Staff',...names.map((name,i)=>name+' '+add(activeWeek,i))],
        ...Object.entries(publishedStaff).map(([id,days])=>[staff.find(member=>member.id===id)?.name || id,...days.map(describe)])];
      const url=URL.createObjectURL(new Blob(['\uFEFF'+rows.map(row=>row.map(quote).join(',')).join('\r\n')],{type:'text/csv;charset=utf-8'}));
      const link=document.createElement('a');
      link.href=url;
      link.download='GOYA-roster-'+activeWeek+'.csv';
      link.click();
      setTimeout(()=>URL.revokeObjectURL(url),1000);
    });
  }
  async function loadStaff(week, reminderOnly=false) {
    if(!reminderOnly) {
      $('roster-days').replaceChildren();
      $('roster-next').textContent='';
      $('roster-week-note').textContent='';
      status('Loading schedule…');
    }
    const id=reminderOnly?++reminderRequest:++request;
    try {
      const result=await rpc('goya_roster_my_week',{p_week:week});
      if(!reminderOnly && id!==request) return;
      if(reminderOnly) {
        if(id!==reminderRequest) return;
        const tomorrow=add(dubaiDate(),1);
        if(monday(tomorrow)!==week) return;
        const day=result.week?.days?.[(new Date(tomorrow+'T00:00:00Z').getUTCDay()+6)%7];
        $('roster-tomorrow').textContent=day?'Hi '+(context()?.user?.name || 'there')+', tomorrow: '+describe(day):'';
        $('roster-tomorrow').hidden=!day;
        const latest=result.latest_publication, alert=$('roster-publication-alert');
        if(alert && latest && Date.now()-Date.parse(latest.published_at)<7*86400000) {
          alert.textContent='New schedule published · '+weekLabel(latest.week);
          alert.hidden=false;
        }
        return;
      }
      const current=monday(dubaiDate());
      staffWeeks=[...new Set([current,week,...result.weeks])].sort().reverse();
      showStaffWeeks(week);
      const roster=result.week;
      if(!roster) {status('No published schedule for this week.');return;}
      const index=roster.days.findIndex((day,i)=>day?.kind==='Shift'&&add(week,i)>=dubaiDate());
      $('roster-next').textContent=index<0?'':'Next scheduled shift in this week: '+names[index]+' · '+describe(roster.days[index]);
      $('roster-days').innerHTML=names.map((name,i)=>{
        const date=add(week,i), day=roster.days[i];
        return '<div class="card"><strong>'+name+' '+shortDate(date)+'</strong><p>'+esc(describe(day))+'</p>'+
          (day?.note?'<small>'+esc(day.note)+'</small>':'')+'</div>';
      }).join('');
      $('roster-week-note').textContent=roster.notes || '';
      status('Published schedule');
    } catch(error) {if(!reminderOnly&&id===request) status(error.message);}
  }
  function showStaffWeeks(selected) {
    const month=$('roster-filter-month')?.value;
    const weeks=staffWeeks.filter(week=>!month || (week.slice(0,7)<=month && add(week,6).slice(0,7)>=month));
    const selector=$('roster-staff-week');
    selector.replaceChildren(...weeks.map(week=>new Option(weekLabel(week),week)));
    selector.disabled=!weeks.length;
    if(weeks.includes(selected)) selector.value=selected;
    return selector.value;
  }
  const admin=$('roster-admin');
  if(admin) initAdmin();
  else {
    $('roster-staff-week').addEventListener('change',event=>loadStaff(event.target.value));
    $('roster-filter-month')?.addEventListener('change',()=>{
      const week=showStaffWeeks();
      if(week) return loadStaff(week);
      request++;
      $('roster-days').replaceChildren();
      $('roster-next').textContent='';
      $('roster-week-note').textContent='';
      status('No published weeks in this month.');
    });
  }
  window.GoyaRoster={
    open:()=>{
      if(admin) return loadAdmin($('roster-week').value || monday(dubaiDate()));
      window.GoyaHR?.openStaffTab('schedule');
      if($('roster-filter-month')) $('roster-filter-month').value='';
      $('roster-next').textContent='';
      return loadStaff(monday(dubaiDate()));
    },
    clearReminder:()=>{
      if(!admin){
        request++;reminderRequest++;staffWeeks=[];
        $('roster-tomorrow').hidden=true;$('roster-tomorrow').textContent='';
        if($('roster-publication-alert')) $('roster-publication-alert').hidden=true;
        $('roster-days').replaceChildren();$('roster-staff-week').replaceChildren();
        $('roster-week-note').textContent='';$('roster-next').textContent='';
      }
    },
    reminder:()=>{
      if(admin) return;
      $('roster-tomorrow').hidden=true;
      if($('roster-publication-alert')) $('roster-publication-alert').hidden=true;
      return loadStaff(monday(add(dubaiDate(),1)),true);
    }
  };
})();
