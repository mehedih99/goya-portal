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
  const time12=value=>{const [h,m]=value.split(':').map(Number);return (h%12||12)+':'+String(m).padStart(2,'0')+' '+(h<12?'AM':'PM');};
  const describe = day => !day ? 'Not scheduled' : day.kind!=='Shift' ? day.kind :
    day.segments.map(s=>time12(s.start)+'–'+time12(s.end)+(s.end<s.start?' (+1 day)':'')+(s.break?' · '+s.break+'m break':'')).join(' / ');
  const context = () => $('roster-admin') ? window.GoyaAttendance?._liveContext() : window.GoyaStaff?._liveContext();
  let client, revision=0, staff=[], schedule, activeWeek, request=0, busy=false;
  let offBalances={},groupFilter='';
  const within=(member,i)=>{const d=add(activeWeek,i);return member.eligible_days?.[i]!==false&&(!member.joining_date||d>=member.joining_date)&&(!member.last_day||d<=member.last_day);};
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
    $('roster-import-dialog')?.close();
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
      offBalances=data.off_balances || {};
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
  function rosterColor(day) {
    return !day?'':day.kind==='Weekly Off'?'roster-shift-off':day.kind==='Annual Leave'?'roster-shift-annual':day.kind!=='Shift'?'roster-shift-leave':day.segments?.[0]?.start<'12:00'?'roster-shift-morning':'roster-shift-closing';
  }
  function publishPreview() {
    const warnings=[],counts={shifts:0,off:0,leave:0,blank:0};
    for(const member of staff)for(let i=0;i<7;i++) {
      if(!within(member,i))continue;
      const raw=schedule.staff[member.id]?.[i],day=effectiveDay(member.id,i,raw);
      counts[!day?'blank':day.kind==='Shift'?'shifts':day.kind==='Weekly Off'?'off':'leave']++;
      if(!day)warnings.push(member.name+' · '+add(activeWeek,i)+' · Not scheduled');
      if(approvedDay(member.id,i)&&raw?.kind==='Shift')warnings.push(member.name+' · '+add(activeWeek,i)+' · Approved leave replaces draft duty');
    }
    return new Promise(resolve=>{
      const node=document.createElement('dialog');node.className='card management-dialog';
      node.innerHTML='<h2>Review before publishing</h2><p>'+esc(weekLabel(activeWeek))+'</p><p>'+staff.length+' staff · '+counts.shifts+' shifts · '+counts.off+' weekly offs · '+counts.leave+' leave days · '+counts.blank+' blank days</p><p>Publishes all staff in FOH and BOH, including unassigned staff and anyone hidden by your current filter. Approved leave is kept automatically.</p><details><summary>Warnings ('+warnings.length+')</summary><p>'+warnings.map(esc).join('<br>')+'</p></details><div class="toolbar"><button class="btn" data-confirm>Publish roster</button><button class="btn secondary" data-cancel>Back to draft</button></div>';
      let confirmed=false;node.querySelector('[data-confirm]').onclick=()=>{confirmed=true;node.close();};node.querySelector('[data-cancel]').onclick=()=>node.close();
      node.onclose=()=>{node.remove();resolve(confirmed);};document.body.append(node);node.showModal();
    });
  }
  function renderAdmin() {
    const teams=['FOH','BOH',''],grid=$('roster-grid');
    const belongs=(m,group)=>(m.roster_group||'')===group;
    const groups=groupFilter?[groupFilter]:teams;
    grid.innerHTML='<thead><tr><th>Staff</th>'+names.map((n,i)=>'<th>'+n.slice(0,3)+'<br>'+shortDate(add(activeWeek,i))+'</th>').join('')+'<th>Off Balance</th></tr></thead><tbody>'+groups.map(group=>{
      const members=staff.filter(m=>belongs(m,group));if(!members.length)return '';
      return '<tr class="roster-section"><th colspan="9">'+esc(group||'Not assigned — select FOH / BOH in Admin → Staff')+' · '+members.length+' staff</th></tr>'+members.map(member=>'<tr><th scope="row">'+esc(member.name)+'</th>'+schedule.staff[member.id].map((day,i)=>{
        if(!within(member,i))return '<td class="roster-outside">'+(member.joining_date&&add(activeWeek,i)<member.joining_date?'Before joining':'After last day')+'</td>';
        const leave=approvedDay(member.id,i),text=describe(effectiveDay(member.id,i,day));
        return '<td><button type="button" class="btn secondary '+rosterColor(effectiveDay(member.id,i,day))+'" data-roster-staff="'+esc(member.id)+'" data-roster-day="'+i+'" aria-label="'+esc(member.name+' '+names[i]+': '+text)+'"'+(leave?' disabled title="Change approved dates in Staff Requests"':'')+'>'+esc(text).replace(' (+1 day)','<small>+1 day</small>')+'</button></td>';
      }).join('')+'<td><button class="btn secondary roster-off-balance" data-roster-balance="'+esc(member.id)+'">'+esc(offBalances[member.id]?.balance??0)+'</button></td></tr>').join('');
    }).join('')+'</tbody>';
    if(!staff.some(m=>!groupFilter||belongs(m,groupFilter)))grid.querySelector('tbody').innerHTML='<tr><td colspan="9">No staff in this roster group.</td></tr>';
  }
  async function save(publish) {
    if(busy || !schedule) return;
    busy=true;
    $('roster-actions').disabled=true;
    $('roster-week').disabled=true;
    try {
      const activeStaff=new Set(staff.map(member=>member.id));
      if(publish&&!await publishPreview())return;
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
          [id,days.map((day,i)=>within(staff.find(m=>m.id===id),i)?effectiveDay(id,i,day):null)]));
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
  const presetKey = 'goya-attendance-roster-presets';
  const defaultShifts = [['08:00','17:00'],['09:00','18:00'],['16:00','00:00'],['16:00','01:00'],['17:00','01:00']];
  function savedPresets() {
    try {
      const list = JSON.parse(localStorage.getItem(presetKey) || '[]');
      return Array.isArray(list) ? list.filter(item=>typeof item?.name==='string' && Array.isArray(item.segments)) : [];
    } catch { return []; }
  }
  function daySegments(form) {
    if (form.elements.kind.value !== 'Shift') return [];
    const segments = [];
    for (let i=0;i<2;i++) {
      const start=form.elements['start'+i].value, end=form.elements['end'+i].value;
      const pause=Number(form.elements['break'+i].value)||0;
      if(i===1&&!start&&!end&&!pause) continue;
      if(!start||!end) throw Error('Enter a start and end time for each shift block.');
      segments.push({start,end,break:pause});
    }
    validateSegments(segments);
    return segments;
  }
  function validateSegments(segments) {
    const minutes = time => Number(time.slice(0,2))*60 + Number(time.slice(3));
    let previousEnd = 0;
    for (const segment of segments) {
      const start = minutes(segment.start);
      const end = minutes(segment.end)+(segment.end<segment.start ? 1440 : 0);
      if (start<previousEnd || end<=start || segment.break>=end-start) throw Error('Shift blocks overlap or the break exceeds the shift.');
      previousEnd=end;
    }
  }
  function rosterWorkbookDate(value,date1904) {
    if (typeof value === 'number') {
      const entry = XLSX.SSF.parse_date_code(value,{date1904});
      if (entry) return [entry.y,entry.m,entry.d].map((part,i)=>String(part).padStart(i===0?4:2,'0')).join('-');
    }
    return String(value ?? '').match(/\b\d{4}-\d{2}-\d{2}\b/)?.[0] || '';
  }
  function importedDay(value) {
    const text = String(value ?? '').trim().replace(/[–—]/g,'-').replace(/\u00a0/g,' ');
    if (!text || /^[-\s]+$/.test(text) || /^not scheduled$/i.test(text)) return null;
    const kind = kinds.slice(1).find(item=>item.toLowerCase()===text.toLowerCase())
      || ({'ext annual leave':'Annual Leave','on leave':'Other Leave','off':'Weekly Off'})[text.toLowerCase()];
    if (kind) return {kind,segments:[],note:''};
    const clock = (hours,minutes,marker) => {
      let hour=Number(hours), minute=Number(minutes || 0);
      if (minute>59 || hour>23 || (marker && (hour>12 || (hour===0 && marker.toUpperCase()==='PM'))) ||
          (!marker && minutes===undefined)) throw Error('Invalid shift time.');
      if (marker) hour=(hour%12)+(marker.toUpperCase()==='PM' ? 12 : 0);
      return String(hour).padStart(2,'0')+':'+String(minute).padStart(2,'0');
    };
    const blocks = text.replace(/\(\+1 day\)/gi,'').trim().split(/\s*(?:\/|\.)\s*/);
    if (blocks.length>2) throw Error('Too many shift blocks.');
    const segments=blocks.map(block=>{
      const match=block.match(/^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?\s*-\s*(\d{1,2})(?::(\d{2}))?\s*(AM|PM)?(?:\s*·\s*(\d{1,3})m break)?$/i);
      if (!match) throw Error('Unrecognized shift or leave type.');
      return {start:clock(...match.slice(1,4)),end:clock(...match.slice(4,7)),break:Number(match[7] || 0)};
    });
    validateSegments(segments);
    return {kind:'Shift',segments,note:''};
  }
  function parseRosterWorkbook(book, week, members) {
    const sheet = book.Sheets['Daily schedule'] || book.Sheets[book.SheetNames[0]];
    if (!sheet?.['!ref']) throw Error('The workbook contains no roster cells.');
    const range = XLSX.utils.decode_range(sheet['!ref']);
    if (range.e.r>5000 || range.e.c>100) throw Error('Use a roster workbook with up to 5,001 rows and 101 columns.');
    const grid = XLSX.utils.sheet_to_json(sheet,{header:1,range:0,defval:null,blankrows:true});
    const dates = Array.from({length:7},(_,index)=>add(week,index));
    const date1904 = book.Workbook?.WBProps?.date1904 === true;
    const normalize = value => String(value ?? '').trim().toLowerCase().replace(/\s+/g,' ');
    const aliases = new Map([['alvinne','alvine'],['shafi','safi'],['chef sayd','chef farrukh']]);
    const changes = new Map(), issues = new Set(), conflicts = new Set();
    const daysFound = new Set();
    let columns = [], nameCol = 1;
    grid.forEach((row,index)=>{
      if (normalize(row[1])==='week of:') {
        nameCol = 1;
        columns = (grid[index+1] || []).slice(2,9).map((value,i)=>[i+2,dates.indexOf(rosterWorkbookDate(value,date1904))]);
        columns.forEach(([,day])=>{if(day>=0) daysFound.add(day);});
        return;
      }
      if (normalize(row[0])==='staff') {
        nameCol = 0;
        columns = row.slice(1,8).map((value,i)=>[i+1,dates.indexOf(rosterWorkbookDate(value,date1904))]);
        columns.forEach(([,day])=>{if(day>=0) daysFound.add(day);});
        return;
      }
      const name = String(row[nameCol] ?? '').trim();
      if (!name || ['weekly schedule','total'].includes(normalize(name))) return;
      const cells = columns.filter(([column,day])=>day>=0 && String(row[column] ?? '').trim());
      if(!cells.length) return;
      const key = aliases.get(normalize(name)) || normalize(name);
      const matches = members.filter(member=>normalize(member.name)===key);
      if (matches.length!==1) { issues.add(name + ' · Staff match unavailable.'); return; }
      const member=matches[0];
      for (const [column,day] of cells) {
        if (approvedDay(member.id,day)) {issues.add(name + ' · ' + dates[day] + ' · Approved leave kept.');continue;}
        const id=member.id+':'+day;
        try {
          const shift=importedDay(row[column]);
          if (!shift) continue;
          const existing=changes.get(id);
          if (existing && JSON.stringify(existing.shift)!==JSON.stringify(shift)) {
            conflicts.add(id);
            issues.add(name+' · '+dates[day]+' · Conflicting Excel shifts.');
          }
          changes.set(id,{member,day,shift});
        } catch (error) { issues.add(name+' · '+dates[day]+' · '+error.message+' ('+String(row[column]).slice(0,60)+')'); }
      }
    });
    if (!daysFound.size) throw Error('No dated columns matched '+weekLabel(week)+'. Use Daily schedule or a sheet headed Staff and seven dated columns.');
    return {changes:[...changes].filter(([id])=>!conflicts.has(id)).map(([,change])=>change),
      issues:[...issues],missing:dates.filter((_,day)=>!daysFound.has(day))};
  }
  function initRosterImport() {
    const dialog = $('roster-import-dialog'), form = $('roster-import-form');
    const feedback = $('roster-import-status'), preview = $('roster-import-preview'), apply = $('roster-apply-import');
    const previewButton = form.querySelector('[type=submit]');
    let pending, generation = 0;
    const reset = () => {
      generation++;
      pending=null;
      feedback.textContent='';
      preview.replaceChildren();
      apply.disabled=true;
      previewButton.disabled=false;
    };
    $('roster-import').onclick = () => {
      if (busy || !schedule) return;
      form.reset();
      reset();
      dialog.showModal();
    };
    $('roster-import-cancel').onclick = () => dialog.close();
    dialog.addEventListener('close',reset);
    form.elements.workbook.onchange=reset;
    form.onsubmit = async event => {
      event.preventDefault();
      reset();
      const current = generation, week = activeWeek, token = context()?.token, file = form.elements.workbook.files[0];
      previewButton.disabled=true;
      try {
        if (!window.XLSX) throw Error('The Excel reader could not load. Refresh and try again.');
        if (!file?.size || file.size>5000000) throw Error('Choose an Excel workbook up to 5 MB.');
        const bytes = await file.arrayBuffer();
        if (current!==generation || !dialog.open || !schedule || activeWeek!==week || context()?.token!==token) return;
        const book = XLSX.read(bytes,{cellFormula:false});
        const result = parseRosterWorkbook(book,week,staff);
        pending={...result,week,token};
        feedback.textContent=result.changes.length+' valid entries · '+result.issues.length+' skipped items. Blank cells keep the current draft.';
        if (result.missing.length) feedback.textContent+=' Dates missing from workbook: '+result.missing.join(', ')+'.';
        if (result.changes.length) {
          preview.innerHTML='<div class="roster-import-scroll"><table><thead><tr><th>Staff</th><th>Date</th><th>Current draft</th><th>Excel</th></tr></thead><tbody>'+
            result.changes.map(({member,day,shift})=>'<tr><td>'+esc(member.name)+'</td><td>'+datesLabel(week,day)+'</td><td>'+
              esc(describe(schedule.staff[member.id][day]))+'</td><td>'+esc(describe(shift))+'</td></tr>').join('')+'</tbody></table></div>';
        }
        if (result.issues.length) {
          const issues=document.createElement('details');
          issues.innerHTML='<summary>Skipped items</summary><ul>'+result.issues.map(issue=>'<li>'+esc(issue)+'</li>').join('')+'</ul>';
          preview.append(issues);
          issues.open=true;
        }
        apply.disabled=!result.changes.length;
      } catch(error) {if (current===generation) feedback.textContent=error.message;}
      finally {if (current===generation) previewButton.disabled=false;}
    };
    apply.onclick = () => {
      if (!pending || busy || !schedule || activeWeek!==pending.week || context()?.token!==pending.token) return;
      for (const {member,day,shift} of pending.changes) {
        const existing = schedule.staff[member.id][day];
        schedule.staff[member.id][day]={...shift,note:existing?.note || '',segments:shift.segments.map((segment,index)=>{
          const previous = existing?.segments?.[index];
          return !segment.break && previous?.start===segment.start && previous.end===segment.end
            ? {...segment,break:previous.break} : segment;
        })};
      }
      dirty=true;
      renderAdmin();
      status(pending.changes.length+' Excel entries applied to the draft. Review and save before publishing.');
      dialog.close();
    };
  }
  const datesLabel = (week,day) => shortDate(add(week,day));

  function initAdmin() {
    const tools=document.createElement('div');tools.className='roster-tools';tools.innerHTML='<label>Roster Group<select id="roster-group"><option value="">All</option><option value="FOH">FOH</option><option value="BOH">BOH</option></select></label><button class="btn secondary" type="button" id="roster-collapse" aria-pressed="false">Hide Sidebar</button><button class="btn secondary" type="button" id="roster-focus" aria-pressed="false">Expand Roster</button>';
    $('roster-status').after(tools);
    $('roster-group').onchange=e=>{groupFilter=e.target.value;if(schedule)renderAdmin();};
    $('roster-collapse').onclick=()=>{const collapsed=document.body.classList.toggle('roster-sidebar-collapsed');$('roster-collapse').textContent=collapsed?'Show Sidebar':'Hide Sidebar';$('roster-collapse').setAttribute('aria-pressed',collapsed);};
    const focus=value=>{document.body.classList.toggle('roster-focus',value);$('roster-focus').textContent=value?'Exit Expanded View':'Expand Roster';$('roster-focus').setAttribute('aria-pressed',value);};
    $('roster-focus').onclick=()=>focus(!document.body.classList.contains('roster-focus'));
    document.addEventListener('keydown',e=>{if(e.key==='Escape')focus(false);});

    const picker=$('roster-week'), dialog=$('roster-edit'), form=$('roster-day-form');
    const preset = form.elements.preset;
    let presets = [];
    function refreshPresets() {
      presets = [...defaultShifts.map(([start,end])=>({kind:'Shift',segments:[{start,end,break:0}],
        name:describe({kind:'Shift',segments:[{start,end,break:0}]})})),
        ...kinds.slice(1).map(kind=>({kind,name:kind,segments:[]})),...savedPresets()];
      preset.replaceChildren(new Option('Custom / edit manually',''),...presets.map((item,i)=>new Option(item.name,String(i))));
    }
    preset.onchange = () => {
      if (!preset.value) return;
      const selected = presets[Number(preset.value)];
      form.elements.kind.value=selected.kind;
      for (let i=0;i<2;i++) {
        const segment=selected.segments[i];
        form.elements['start'+i].value=segment?.start || '';
        form.elements['end'+i].value=segment?.end || '';
        form.elements['break'+i].value=segment?.break || '';
      }
      updateInputs();
    };
    $('roster-save-preset').onclick = () => {
      try {
        if (form.elements.kind.value!=='Shift') throw Error('Choose Shift and enter the shift hours first.');
        const segments = daySegments(form);
        const name = prompt('Name this shift preset',describe({kind:'Shift',segments}))?.trim().slice(0,60);
        if (!name) return;
        const saved = savedPresets();
        const existing = saved.findIndex(item=>item.name.toLowerCase()===name.toLowerCase());
        if (existing>=0 && !confirm('Replace the preset named “'+name+'”?')) return;
        const item = {name,kind:'Shift',segments};
        if (existing>=0) saved[existing]=item;
        else saved.push(item);
        localStorage.setItem(presetKey,JSON.stringify(saved));
        refreshPresets();
        $('roster-edit-status').textContent='Shift preset saved on this device.';
      } catch (error) { $('roster-edit-status').textContent=error.message; }
    };
    $('roster-template').onclick=()=>{
      if(!activeWeek||!window.XLSX)return;
      const rows=[['Staff',...names.map((name,i)=>add(activeWeek,i))],...staff.map(m=>[m.name,...Array(7).fill('')])];
      const book=XLSX.utils.book_new(),sheet=XLSX.utils.aoa_to_sheet(rows);
      sheet['!cols']=[{wch:24},...Array(7).fill({wch:22})];
      XLSX.utils.book_append_sheet(book,sheet,'Weekly roster');
      XLSX.utils.book_append_sheet(book,XLSX.utils.aoa_to_sheet([
        ['GOYA Weekly Roster Template'],['Week starts Monday',activeWeek],
        ['Shift example','09:00-18:00'],['Closing example','16:00-01:00'],
        ['Split shift example','08:00-12:00 / 16:00-20:00'],['Day off','Weekly Off'],['Vacation','Annual Leave'],
        ['Other leave','Sick Leave or Other Leave'],
        ['Import','Select the same week in GOYA, choose Import Excel, Preview, then Apply to draft. Publish after review.'],
        ['Off Balance','Edit Off Balance directly in GOYA. This template changes shifts only.']
      ]),'Instructions');
      XLSX.writeFile(book,'GOYA-roster-template-'+activeWeek+'.xlsx');
    };
    $('roster-grid').addEventListener('click',event=>{
      const button=event.target.closest('[data-roster-balance]');if(!button||busy)return;
      const member=staff.find(m=>m.id===button.dataset.rosterBalance);if(!member)return;
      const week=activeWeek,version=request;
      GoyaManagement.editBalance({...member,off_balance:offBalances[member.id]||{balance:0,revision:0}},async()=>{
        const values=await GoyaManagement.rpc('goya_management_balances');
        if(week===activeWeek&&version===request){offBalances=values;renderAdmin();}
      });
    });
    window.addEventListener('beforeunload',event=>{if(dirty){event.preventDefault();event.returnValue='';}});
    initRosterImport();
    picker.addEventListener('change',()=>loadAdmin(picker.value));
    $('roster-notes').addEventListener('input',()=>{dirty=true;});
    $('roster-grid').addEventListener('click',event=>{
      const button=event.target.closest('[data-roster-staff]');
      if(!button || busy || !schedule) return;
      const id=button.dataset.rosterStaff, index=Number(button.dataset.rosterDay), day=schedule.staff[id][index];
      form.reset();
      refreshPresets();
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
    form.elements.kind.addEventListener('change',()=>{preset.value='';updateInputs();});
    $('roster-times').addEventListener('input',()=>{preset.value='';});
    $('roster-cancel').addEventListener('click',()=>dialog.close());
    form.addEventListener('submit',event=>{
      event.preventDefault();
      const {staff:id,day:index}=form.dataset;
      const {kind,note}=form.elements;
      let segments;
      try { segments = daySegments(form); }
      catch (error) { $('roster-edit-status').textContent=error.message; return; }
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
  async function loadStaff(week) {
    $('roster-days').replaceChildren();
    $('roster-next').textContent='';
    $('roster-week-note').textContent='';
    status('Loading schedule…');
    const id=++request;
    try {
      const result=await rpc('goya_roster_my_week',{p_week:week});
      if(id!==request) return;
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
    } catch(error) {
      if(id===request) status(error.message);
    }
  }
  async function loadDutyWindow() {
    const generation=++reminderRequest;
    const token=context()?.token;
    const date=window.GoyaDashboard?.scheduleDate?.()||dubaiDate();
    const tomorrow=add(date,1);
    const weeks=[...new Set([monday(date),monday(tomorrow)])];
    try {
      const results=await Promise.all(weeks.map(week=>rpc('goya_roster_my_week',{p_week:week})));
      if(generation!==reminderRequest||context()?.token!==token)return;
      if((window.GoyaDashboard?.scheduleDate?.()||dubaiDate())!==date)return loadDutyWindow();
      const dayFor=day=>{
        const result=results[weeks.indexOf(monday(day))];
        return result.week?.days?.[(new Date(day+'T00:00:00Z').getUTCDay()+6)%7]||null;
      };
      const latest=results.map(result=>result.latest_publication).filter(Boolean)
        .sort((a,b)=>Date.parse(b.published_at)-Date.parse(a.published_at))[0];
      window.GoyaDashboard?.setDutyWindow({date,today:dayFor(date),tomorrow:dayFor(tomorrow)},latest);
    } catch(error) {
      if(generation===reminderRequest&&context()?.token===token) {
        window.GoyaDashboard?.setDutyWindow({date,unavailable:true},null);
      }
    }
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
        window.GoyaDashboard?.setDutyWindow(null,null);
        $('roster-days').replaceChildren();$('roster-staff-week').replaceChildren();
        $('roster-week-note').textContent='';$('roster-next').textContent='';
      }
    },
    reminder:()=>{
      if(admin) return;
      return loadDutyWindow();
    }
  };
})();
