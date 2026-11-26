(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const context = () => document.body?.dataset.page === 'staff'
    ? window.GoyaStaff?._liveContext()
    : window.GoyaAttendance?._liveContext() ?? window.GoyaAdmin?._context();
  const config = () => window.GOYA_CONFIG;
  const escaped = value => String(value ?? '').replace(/[&<>"']/g, ch => ({
    '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'
  })[ch]);
  const date = () => new Intl.DateTimeFormat('sv-SE', {timeZone:'Asia/Dubai', year:'numeric', month:'2-digit', day:'2-digit'}).format(new Date());
  let client;
  let profiles = [];
  let requests = [];
  let requestGeneration = 0;
  let staffGeneration = 0;
  let documentGeneration = 0;
  let submissionId;
  let currentOffBalance=null;
  let archiveRows = [];

  async function rpc(name, payload = {}) {
    const token = context()?.token;
    if (!token) throw Error('Sign in again.');
    client ||= window.supabase.createClient(config().SUPABASE_URL, config().SUPABASE_ANON_KEY, {auth:{persistSession:false,autoRefreshToken:false}});
    const {data,error} = await client.rpc(name, {p_token:token,...payload});
    if (context()?.token !== token) throw Error('Your session changed.');
    if (error) throw Error(error.message);
    return data;
  }
  const renderStatus = (pane, value) => pane.querySelector('[role=status]').textContent = value;
  const content = pane => pane.querySelector('.hr-content');
  const stateOf = member => member.profile?.last_day ? 'Resigned' : member.active ? 'Active' : 'Inactive';
  const values = form => Object.fromEntries(new FormData(form));
  const empty = (pane, message) => content(pane).textContent = message;
  const documentCategories = [
    ['passport','🛂','Passport'],
    ['emirates-id','🪪','Emirates ID'],
    ['contract','📄','Employment Contract'],
    ['food-safety','📋','Food Safety Certificate'],
    ['health-card','➕','Food Handler Health Card'],
    ['work-permit','📄','Work Permit / Labour Card'],
    ['residence-visa','🛂','Residence Visa'],
    ['health-insurance','➕','Health Insurance Card'],
    ['pic-certificate','📋','PIC Certificate'],
    ['occupational-health-card','➕','Occupational Health Card'],
    ['noc','📄','NOC'],
    ['profile-photo','👤','Profile Photo'],
  ];
  const documentTypes = ['application/pdf','image/jpeg','image/png'];
  const uploadDate = new Intl.DateTimeFormat('en-AE',{timeZone:'Asia/Dubai',dateStyle:'medium',timeStyle:'short'});
  let emailSettingsRevision = null;
  let emailSettingsRequest = 0;

  function displayEmailSettings(form, data) {
    form.elements.owner.value = data.owner_email ?? '';
    form.elements.hr.value = data.hr_email ?? '';
    emailSettingsRevision = data.revision;
  }
  async function openEmailSettings() {
    const pane = $('hr-email-settings');
    const form = pane.querySelector('form'), button = form.querySelector('button');
    const request = ++emailSettingsRequest;
    const fields = form.querySelectorAll('input');
    emailSettingsRevision = null;
    button.disabled = true;
    fields.forEach(input=>{input.value='';input.disabled=true;});
    renderStatus(pane,'Loading email settings…');
    try {
      const data = await rpc('goya_hr_admin_email_settings');
      if (request !== emailSettingsRequest) return;
      displayEmailSettings(form,data);
      fields.forEach(input=>input.disabled=false);
      button.disabled = false;
      renderStatus(pane,'');
    } catch (error) {
      if (request === emailSettingsRequest) renderStatus(pane,error.message);
    }
  }
  async function saveEmailSettings(event) {
    event.preventDefault();
    const form = event.currentTarget, pane = $('hr-email-settings'), button = form.querySelector('button');
    if (emailSettingsRevision === null || button.disabled) return;
    const input = values(form);
    const request = ++emailSettingsRequest;
    const fields = form.querySelectorAll('input');
    fields.forEach(field=>field.disabled=true);
    button.disabled = true;
    renderStatus(pane,'Saving email settings…');
    try {
      const saved = await rpc('goya_hr_save_email_settings',{p_owner:input.owner,p_hr:input.hr,p_expected:emailSettingsRevision});
      if (request !== emailSettingsRequest) return;
      displayEmailSettings(form,saved);
      renderStatus(pane,saved.owner_email && saved.hr_email ? 'Email settings saved.' :
        'Email settings saved. Add both addresses to enable annual leave emails.');
    } catch (error) {
      if (request === emailSettingsRequest) renderStatus(pane,error.message);
    } finally {
      if (request === emailSettingsRequest) {
        fields.forEach(field=>field.disabled=false);
        button.disabled = false;
      }
    }
  }

  function download(name, rows) {
    const cell = value => {
      const text = String(value ?? '');
      return '"' + (/^[\s]*[=+@-]|^[\t\r\n]/.test(text) ? "'" : '') + text.replaceAll('"','""') + '"';
    };
    const url = URL.createObjectURL(new Blob(['\ufeff', rows.map(row => row.map(cell).join(',')).join('\r\n')], {type:'text/csv;charset=utf-8'}));
    const link = document.createElement('a');
    link.href = url;
    link.download = name;
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  function dialog(title, body, handler, action = 'Save') {
    const node = document.createElement('dialog');
    node.className = 'hr-dialog';
    node.innerHTML = '<form><h2>' + escaped(title) + '</h2>' + body +
      '<p role="status"></p><div class="hr-tabs"><button class="btn primary" type="submit">' + escaped(action) + '</button>' +
      '<button class="btn secondary" type="button">Cancel</button></div></form>';
    document.body.append(node);
    node.querySelector('button[type=button]').onclick = () => node.close();
    node.addEventListener('close', () => node.remove(), {once:true});
    const form = node.querySelector('form');
    let saving = false;
    node.addEventListener('cancel',event=>{if(saving) event.preventDefault();});
    form.addEventListener('submit', async event => {
      event.preventDefault();
      if (saving) return;
      const input = values(form);
      const fields = Array.from(form.elements).filter(field=>!field.disabled);
      saving = true;
      fields.forEach(field=>field.disabled=true);
      try {
        await handler(input);
        node.close();
      } catch (error) {
        renderStatus(node, error.message);
      } finally {
        saving = false;
        fields.forEach(field=>field.disabled=false);
      }
    });
    node.showModal();
    return node;
  }
  function resetStaff() {
    currentOffBalance=null;
    staffGeneration++;
    documentGeneration++;
    submissionId = null;
    const form = $('hr-leave-form');
    if (!form) return;
    form.reset();
    renderStatus(form,'');
    for (const name of ['journey','leave','staff-archive']) empty($('hr-' + name),'');
    $('hr-request-status')?.replaceChildren();
    const documents = $('hr-journey').querySelector('[data-hr-documents]');
    documents?.querySelector('.hr-document-list').replaceChildren();
    documents?.querySelector('[role=status]').replaceChildren();
    $('hr-staff-archive-month').value = '';
    $('hr-staff-archive').open = false;
  }
  function rejoinEditor(member, refresh) {
    dialog('Rejoin · ' + member.name, '<label>Rejoin date<input type="date" name="date" value="' + date() +
      '" required></label>', async input => {
      await rpc('goya_management_rejoin', {p_staff:member.id,p_date:input.date});
      await refresh();
    });
  }

  function filteredProfiles() {
    const filter = $('hr-record-filter').value;
    const search = $('hr-record-search').value.trim().toLowerCase();
    return profiles.filter(member => (filter === 'All staff' || stateOf(member) === filter) &&
      member.name.toLowerCase().includes(search));
  }
  function renderRecords() {
    const pane = $('hr-records');
    const items = filteredProfiles();
    content(pane).innerHTML = items.map((member, i) => {
      const profile = member.profile || {};
      const fields = [['Employee ID',profile.employee_code],['Position',profile.position],['Branch',profile.branch],
        ['Joining date',profile.joining_date],['Last working day',profile.last_day || 'Present'],...Object.entries(window.GoyaPeople?.labels || {mobile:'Mobile / WhatsApp',email:'Email',address:'Address',nationality:'Nationality',date_of_birth:'Date of birth',employment_type:'Employment type',probation_end:'Probation end date',emergency_name:'Emergency contact',emergency_relationship:'Relationship',emergency_phone:'Emergency phone'}).map(([k,l])=>[l,profile[k]])];
      return '<details class="hr-staff-card" data-staff-record="' + i + '" data-staff-id="' + escaped(member.id) + '"><summary><strong>' + escaped(member.name) +
        '</strong><span>' + escaped([profile.employee_code,stateOf(member)].filter(Boolean).join(' · ')) + '</span></summary>' +
        '<div class="hr-staff-card-body"><img class="staff-profile-photo hr-profile-photo" alt="Profile photo" data-profile-photo hidden><div class="toolbar"><button class="btn secondary" type="button" data-staff-pdf>⬇ Staff File</button><button class="btn secondary" type="button" data-balance>Edit Off Balance: ' + escaped(member.off_balance?.balance ?? 'N/A') + '</button></div><dl class="hr-journey-details">' + fields.map(([label,value]) =>
          '<div><dt>' + label + '</dt><dd>' + escaped(value || 'N/A') + '</dd></div>').join('') + '</dl>' +
        (member.history || []).map(item => '<p class="small muted">' + escaped(item.event) + ' · ' +
          escaped(item.details.rejoined_on || item.details.last_day) + '</p>').join('') +
        (profile.manager_notes ? '<p><strong>Private manager notes</strong><br>' + escaped(profile.manager_notes) + '</p>' : '') +
        '<section><h3>Employment &amp; management history</h3>' +
        (member.resignation && !member.resignation.cancelled_at ? '<p><strong>Resignation · Last Working Day: ' + escaped(member.resignation.last_working_day) + '</strong></p><p>' + escaped(member.resignation.note) + '</p>' : '') +
        '<details><summary>View change history ('+(member.history||[]).length+')</summary>'+(member.history||[]).map(h=>'<div class="hr-private-note"><strong>'+escaped(h.event)+'</strong><p>'+escaped(h.created_at)+'</p><p>'+escaped(h.details?.actor||'Management')+'</p><p>'+escaped(h.details?.reason||h.details?.note||'')+'</p>'+(h.event==='Off balance changed'?'<p>Balance: '+escaped(h.details?.before?.balance)+' → '+escaped(h.details?.after?.balance)+'</p>':'')+'</div>').join('')+'</details></section>' +
        '<details data-record-activity><summary>Attendance, roster and request records</summary><p role="status"></p><div data-record-activity-content></div></details>'+
        '<section data-annual-history><h3>Annual Leave History</h3><button type="button" class="btn secondary" data-add-annual>＋ Add annual leave</button>' +
        '<p class="small" role="status"></p><div class="hr-annual-list"></div></section>' +
        '<section data-record-documents><h3>Document history</h3><button type="button" class="btn secondary" data-add-document>＋ Upload Document</button>' +
        '<p class="small" role="status"></p><div class="hr-document-list"></div></section></div></details>';
    }).join('');
    if (!items.length) empty(pane,'No staff match this filter.');
    content(pane).querySelectorAll('[data-staff-record]').forEach(details => {
      const member = items[details.dataset.staffRecord];
      const documents = details.querySelector('[data-record-documents]');
      const annual = details.querySelector('[data-annual-history]');
      const activity=details.querySelector('[data-record-activity]');
      activity.ontoggle=()=>{if(activity.open)GoyaManagement.renderRecordActivity(activity,member);};
      details.querySelector('[data-staff-pdf]').onclick=async event=>{const button=event.currentTarget;if(button.disabled)return;button.disabled=true;try{renderStatus(documents,'Preparing Staff File…');await GoyaStaffFile.download(member,message=>renderStatus(documents,message));renderStatus(documents,'Staff File downloaded. Extract the ZIP to view offline.');}catch(e){renderStatus(documents,e.message);}finally{button.disabled=false;}};
      details.querySelector('[data-balance]').onclick=()=>GoyaManagement.editBalance(member,openRecords);
      documents.querySelector('[data-add-document]').onclick = () => documentEditor(documents,member.id);
      annual.querySelector('[data-add-annual]').onclick = () => annualEditor(annual,member);
      details.ontoggle = () => {
        if (!details.open) return;
        void loadDocuments(documents,member.id);
        void showProfilePhoto(details.querySelector('[data-profile-photo]'),member.id);
        void loadAnnualHistory(annual,member);
      };
    });
  }
  async function loadAnnualHistory(pane, member) {
    const token = context()?.token;
    renderStatus(pane,'Loading annual leave…');
    try {
      const [manual, sources] = await Promise.all([
        rpc('goya_hr_annual_history',{p_staff:member.id}),
        rpc('goya_hr_admin_annual_sources',{p_staff:member.id}),
      ]);
      if (!pane.isConnected || token !== context()?.token) return;
      const rows = [...manual,...sources.map(row=>({...row,source_id:row.id,id:null}))];
      const list = pane.querySelector('.hr-annual-list');
      list.innerHTML = rows.length ? rows.map((row,index) => '<div class="hr-annual-row"><span><strong>' +
        escaped(row.leave_from ? journeyRange(row.leave_from,row.leave_to) : 'N/A') + '</strong> · Done' +
        (row.service_year ? ' · Service year ' + escaped(journeyDateFormat.format(journeyDate(row.service_year))) : '') +
        (row.note ? '<br>' + escaped(row.note) : '') + '</span>' +
        '<button class="btn secondary" type="button" data-annual-edit="' + index + '">Edit</button></div>').join('') :
        '<p class="small muted">No completed annual leave recorded.</p>';
      list.querySelectorAll('[data-annual-edit]').forEach(button =>
        button.onclick = () => annualEditor(pane,member,rows[button.dataset.annualEdit]));
      renderStatus(pane,'');
    } catch (error) { if (pane.isConnected && token === context()?.token) renderStatus(pane,error.message); }
  }
  function annualEditor(pane, member, row = {}) {
    const joined = member.profile?.joining_date;
    const today = date();
    if (!joined || joined > today) return renderStatus(pane,'Add a valid joining date in Staff Management first.');
    const years = serviceYears(joined,today);
    const preferred = row.service_year || years.find(year=>year <= (row.leave_from || today));
    const id = row.id || crypto.randomUUID();
    dialog('Annual Leave · ' + member.name,
      '<label>Service year<select name="year" required>' + years.map(year => '<option value="' + year + '"' +
        (year === preferred ? ' selected' : '') + '>' + escaped(journeyRange(year,anniversary(joined,Number(year.slice(0,4))+1))) +
        '</option>').join('') + '</select></label>' +
      '<p class="small muted">Saved as Done. For an earlier service year, leave both dates blank if unknown.</p>' +
      '<div class="hr-fields"><label>From<input name="from" type="date" value="' + escaped(row.leave_from) + '"></label>' +
      '<label>To<input name="to" type="date" value="' + escaped(row.leave_to) + '"></label></div>' +
      '<label>Note visible to staff<textarea name="note" maxlength="2000">' + escaped(row.note) + '</textarea></label>',
      async input => {
        await rpc('goya_hr_save_annual_history',{p_staff:member.id,p_id:id,p_expected:row.updated_at || null,
          p_source:row.source_id || null,p_year:input.year,p_from:input.from || null,p_to:input.to || null,p_note:input.note});
        await loadAnnualHistory(pane,member);
      });
  }
  async function openRecords() {
    const pane = $('hr-records');
    profiles = [];
    empty(pane,'');
    renderStatus(pane,'Loading records…');
    try {
      profiles = await rpc('goya_management_profiles');
      renderRecords();
      renderStatus(pane,'');
    } catch (error) { renderStatus(pane,error.message); }
  }
  const period = request => {
    const from = request.approved_from || request.requested_from;
    const to = request.approved_to || request.requested_to;
    if (request.state === 'Recorded' && ['Cancelled Off','Attendance Note'].includes(request.kind)) {
      return new Intl.DateTimeFormat('en',{month:'long',year:'numeric',timeZone:'UTC'}).format(new Date(from));
    }
    return from === to ? from : from + ' – ' + to;
  };
  function leaveStatus(request, today = date()) {
    if (request.state !== 'Approved') return request.state;
    if(request.kind==='Resignation')return request.approved_to<today?'Done':'Approved';
    if (request.approved_to < today) return 'Done';
    return request.approved_from <= today ? 'In progress' : 'Approved';
  }
  function filteredRequests() {
    const filter = $('hr-request-filter').value;
    const search=$('hr-request-search')?.value.trim().toLowerCase()||'';
    const type=$('hr-request-type')?.value||'';
    return requests.filter(request => (!type||request.kind===type) && (!search||request.name.toLowerCase().includes(search)) && (filter === 'All requests' || (filter==='Approved'?request.state==='Approved':leaveStatus(request)===filter)));
  }
  function review(request) {
    const resign=request.kind==='Resignation';
    const prior=request.management_history?.[0];
    const node=dialog('Review · '+request.name,
      '<p>'+escaped(request.kind)+' · '+escaped(period(request))+'</p><label>Decision<select name="decision"><option value="Approved">Approve</option><option value="Declined">Reject</option></select></label>'+
      '<div class="hr-fields" data-approval-fields><label>'+(resign?'Last Working Day':'Approved from')+'<input name="from" type="date" value="'+escaped(request.approved_from||request.requested_from)+'"></label>'+
      (resign?'':'<label>Approved to<input name="to" type="date" value="'+escaped(request.approved_to||request.requested_to)+'"></label><label>Payroll outcome<select name="payroll"></select></label>')+'</div>'+
      '<div class="hr-overlap-warning small"></div>'+
      '<label><span data-public-note-label>Message to staff (optional)</span><textarea name="public_note" maxlength="2000">'+escaped(request.review_note||'')+'</textarea></label>'+
      '<p class="small muted" data-public-note-help>This message will be visible to the staff member.</p>'+GoyaManagement.identity()+
      '<label>Private management note<textarea name="private_note" maxlength="2000">'+escaped(prior?.note||'')+'</textarea></label><p class="small muted">Management name, decision history and this note are not visible to staff.</p>',
      async input=>{
        if(input.decision==='Declined'&&!input.public_note?.trim())throw Error('Enter a reason for rejection that the staff member can read.');
        await rpc('goya_management_review',{p_id:request.id,p_expected:request.updated_at,p_state:input.decision,
          p_from:input.decision==='Approved'?(input.from||null):null,p_to:input.decision==='Approved'?((resign?input.from:input.to)||null):null,p_payroll:input.decision==='Approved'?(resign?'Unpaid':input.payroll||null):null,
          p_note:(input.public_note||'').trim(),p_actor:input.actor,p_private_note:input.private_note});
        await openRequests(true);
      });
    const form=node.querySelector('form'),{decision,from,to,payroll,public_note:publicNote}=form.elements;
    if(request.state==='Declined')decision.value='Declined';
    const update=preferred=>{
      const approved=decision.value==='Approved';
      node.querySelector('[data-approval-fields]').hidden=!approved;
      node.querySelector('.hr-overlap-warning').hidden=!approved;
      node.querySelector('[data-public-note-label]').textContent=approved?'Message to staff (optional)':'Reason for rejection';
      node.querySelector('[data-public-note-help]').textContent=approved?'This message will be visible to the staff member.':'This reason will be visible to the staff member.';
      const submit=form.querySelector('button[type=submit]');submit.textContent=approved?'Confirm Approval':'Confirm Rejection';submit.classList.toggle('hr-reject-button',!approved);
      publicNote.required=!approved;
      publicNote.setCustomValidity('');
      from.disabled=!approved;from.required=approved;
      if(to){to.disabled=!approved;to.required=approved;}
      if(payroll)payroll.disabled=!approved;
      if(payroll){const choices=approved?(request.kind==='Sick Leave'&&!request.drive_file_id?['Unpaid']:['Paid','Unpaid']):(request.kind==='Sick Leave'?['','Absent']:['']);
        payroll.replaceChildren(...choices.map(item=>new Option(item||'No payroll decision',item)));if(choices.includes(preferred))payroll.value=preferred;}
      const overlaps=requests.filter(r=>r.id!==request.id&&r.state==='Approved'&&r.kind!=='Resignation'&&
        (r.sections||[]).some(section=>(request.sections||[]).includes(section))&&r.approved_from<=(to?.value||from.value)&&r.approved_to>=from.value);
      node.querySelector('.hr-overlap-warning').textContent=resign?'Access will close after the approved last working day. Future roster entries will remain in history.':
        overlaps.length?'Same section on approved leave: '+overlaps.map(r=>r.name+' ('+period(r)+')').join('; '):'No overlapping approved leave found in the loaded requests for this section.';
    };
    decision.onchange=()=>update();from.onchange=()=>update(payroll?.value);if(to)to.onchange=()=>update(payroll?.value);update(request.payroll);
  }
  function renderRequests() {
    const pane=$('hr-requests'),items=filteredRequests();
    const pending=requests.filter(r=>r.state==='Pending').length;
    if($('hr-pending-tab')){$('hr-pending-tab').textContent='Pending · '+pending;$('hr-all-tab').textContent='All · '+requests.length;
      $('hr-pending-tab').setAttribute('aria-pressed',String($('hr-request-filter').value==='Pending'));
      $('hr-all-tab').setAttribute('aria-pressed',String($('hr-request-filter').value==='All requests'));}
    content(pane).innerHTML=items.map((r,i)=>{
      const resign=r.kind==='Resignation',from=r.approved_from||r.requested_from,to=r.approved_to||r.requested_to;
      const days=Math.round((Date.parse(to)-Date.parse(from))/86400000)+1;
      return '<article class="hr-request-card"><div class="hr-request-heading"><div><h3>'+escaped(r.name)+'</h3><p>'+escaped(r.kind)+'</p></div>'+leaveBadge(leaveStatus(r))+'</div>'+
        '<div class="hr-request-meta"><strong>'+escaped(resign?'Last Working Day: '+from:period(r))+'</strong>'+
        (resign?'':'<span>'+days+' day'+(days===1?'':'s')+'</span>')+(r.payroll&&!resign?'<span>'+escaped(r.payroll)+'</span>':'')+'</div><p>'+escaped(r.reason)+'</p>'+
        (r.review_note&&r.review_note!==r.reason?'<p>'+(r.state==='Declined'?'<strong>Reason for rejection</strong><br>':'')+escaped(r.review_note)+'</p>':'')+
        (/^[\w-]+$/.test(r.drive_file_id||'')?'<a target="_blank" rel="noopener noreferrer" href="https://drive.google.com/open?id='+r.drive_file_id+'">📎 View supporting document</a>':'')+
        (['Withdrawn','Recorded'].includes(r.state)?'':'<div class="toolbar"><button type="button" class="btn" data-review="'+i+'">'+(r.state==='Pending'?'Review · Approve / Reject':'Review / Edit')+'</button></div>')+
        '<details class="hr-management-history"><summary>🔒 Management-only decision history</summary>'+
        ((r.management_history||[]).map(h=>'<div class="hr-private-note"><strong>'+escaped(h.actor)+' · '+escaped(h.after_data.state)+'</strong><p>'+escaped(uploadDate.format(new Date(h.created_at)))+'</p><p>'+escaped(h.note||'No note')+'</p><p>Previous dates: '+escaped([h.before_data.approved_from,h.before_data.approved_to].filter(Boolean).join(' – ')||'N/A')+' · New dates: '+escaped([h.after_data.approved_from,h.after_data.approved_to].filter(Boolean).join(' – ')||'N/A')+'</p></div>').join('')||'<p>No management decision recorded.</p>')+'</details></article>';
    }).join('')||'<div class="hr-request-card">'+($('hr-request-filter').value==='Pending'?'✓ No pending requests.':'No requests match this filter.')+'</div>';
    content(pane).querySelectorAll('[data-review]').forEach(button=>button.onclick=()=>review(items[button.dataset.review]));
  }
  async function openRequests(keepFilter=false) {
    if(keepFilter!==true){$('hr-request-filter').value='Pending';$('hr-request-month').value='';if($('hr-request-type'))$('hr-request-type').value='';}
    const pane = $('hr-requests'), generation = ++requestGeneration;
    requests = [];
    empty(pane,'');
    renderStatus(pane,'Loading requests…');
    const month = $('hr-request-month').value;
    try {
      const data = await rpc('goya_management_requests',{p_month:month ? month + '-01' : null});
      if (generation !== requestGeneration) return;
      requests = data;
      renderRequests();
      renderStatus(pane,'');
    } catch (error) { if (generation === requestGeneration) renderStatus(pane,error.message); }
  }

  function workbookDate(value, date1904) {
    if (value instanceof Date && !Number.isNaN(value.getTime())) return value.toISOString().slice(0,10);
    if (typeof value !== 'number') return '';
    const day = window.XLSX.SSF.parse_date_code(value,{date1904});
    return day ? [day.y,String(day.m).padStart(2,'0'),String(day.d).padStart(2,'0')].join('-') : '';
  }
  function parseArchive(grid,date1904) {
    let days = [];
    const weeks = [], rows = [];
    const cell = value => String(value ?? '').trim();
    grid.forEach((row,i) => {
      if (cell(row[1]).toLowerCase() === 'week of:') {
        days = (grid[i+1] || []).slice(2,9).map(value=>workbookDate(value,date1904));
        if (days.length !== 7 || days.some(day=>!day)) throw Error('Check date headings after workbook row ' + (i+1) + '.');
        weeks.push(days[0]);
        return;
      }
      if (!days.length || i<2 || cell(grid[i-1]?.[1]).toLowerCase() === 'week of:' ||
        cell(grid[i-2]?.[1]).toLowerCase() === 'week of:' || cell(row[1]).toLowerCase() === 'weekly schedule') return;
      const name = cell(row[1]), shifts = days.map((date,d)=>({date,value:cell(row[d+2])}));
      const extra = row.slice(10).map(cell).filter(Boolean).join('\n');
      if (name && (shifts.some(shift=>shift.value) || (cell(row[9]) && !Number.isNaN(Number(row[9]))))) {
        rows.push({source_week:days[0],source_row:i+1,source_name:name,shifts,pending_off:cell(row[9]),private_remarks:extra});
      } else {
        const remark = row.map(cell).filter(Boolean).join(' · ');
        if (remark) rows.push({source_week:days[0],source_row:i+1,source_name:'',shifts:[],pending_off:'',private_remarks:remark});
      }
    });
    return {weeks,rows};
  }
  async function prepareImport() {
    const pane = $('hr-admin-archive'), input = $('hr-workbook');
    const mapping = pane.querySelector('.hr-mapping'), file = input.files[0];
    $('hr-commit-import').disabled = true;
    archiveRows = [];
    mapping.replaceChildren();
    if (!file || !window.XLSX) return renderStatus(pane,'Choose an Excel workbook.');
    if (file.size > 5_000_000) return renderStatus(pane,'Choose a workbook up to 5 MB.');
    $('hr-preview-import').disabled = true;
    try {
      const book = XLSX.read(await file.arrayBuffer(),{cellDates:false});
      const sheet = book.Sheets['Daily schedule'];
      if (!sheet) throw Error('The workbook should contain the Daily schedule tab.');
      const {weeks,rows} = parseArchive(XLSX.utils.sheet_to_json(sheet,{header:1,range:0,defval:null}),
        book.Workbook?.WBProps?.date1904 === true);
      if (!weeks.length || !rows.length) throw Error('No dated rosters were found.');
      const members = await rpc('goya_management_profiles');
      const names = [...new Set(rows.map(row=>row.source_name).filter(Boolean))].sort();
      const norm = value => value.trim().toLowerCase();
      for (const name of names) {
        const label = document.createElement('label'), list = document.createElement('select');
        const matches = members.filter(member=>norm(member.name)===norm(name));
        list.dataset.sourceName = name;
        list.append(new Option('Keep in admin archive only',''),...members.map(member=>new Option(member.name,member.id)));
        if (matches.length === 1) list.value = matches[0].id;
        label.append(name,list);
        mapping.append(label);
      }
      const duplicates = weeks.filter((week,index)=>weeks.indexOf(week)!==index);
      renderStatus(pane,weeks.length + ' dated blocks · ' + rows.length + ' archive rows. Review staff matches and private remarks before importing.' +
        (duplicates.length ? ' Repeated week start: ' + [...new Set(duplicates)].join(', ') + '. Both source blocks will be retained.' : ''));
      archiveRows = rows;
      $('hr-commit-import').disabled = false;
    } catch (error) { renderStatus(pane,error.message); }
    finally { $('hr-preview-import').disabled = false; }
  }
  async function importArchive() {
    const pane = $('hr-admin-archive'), button = $('hr-commit-import');
    if (!archiveRows.length || !confirm('Save this archive and the selected staff matches?')) return;
    const matches = new Map(Array.from(pane.querySelectorAll('[data-source-name]'),list=>[list.dataset.sourceName,list.value]));
    const rows = archiveRows.map(row=>({...row,staff_id:matches.get(row.source_name) || null}));
    button.disabled = true;
    try {
      const count = await rpc('goya_hr_archive_import',{p_rows:rows});
      renderStatus(pane,count + ' archive rows imported or linked.');
    } catch (error) {
      renderStatus(pane,error.message);
      button.disabled = false;
    }
  }
  async function showArchive(admin) {
    const id = admin ? 'hr-admin-archive' : 'hr-staff-archive';
    const pane = $(id), value = $(id + '-month').value, token = context()?.token;
    empty(pane,'');
    if (!value) return renderStatus(pane,'Choose a month.');
    renderStatus(pane,'Loading archive…');
    try {
      const rows = await rpc('goya_hr_archive_read',{p_admin:admin,p_month:value+'-01'});
      if ($(id + '-month').value !== value || context()?.token !== token) return;
      content(pane).innerHTML = rows.map(row=>'<article class="hr-entry"><strong>' +
        escaped([row.source_week, row.source_name || (admin ? 'Workbook notes' : '')].filter(Boolean).join(' · ')) +
        '</strong><p>' + row.shifts.filter(shift=>shift.value).map(shift=>escaped(shift.date + ' · ' + shift.value)).join('<br>') +
        '</p>' + (row.pending_off ? '<p>Pending PH/PO as recorded · ' + escaped(row.pending_off) + '</p>' : '') +
        (admin && row.private_remarks ? '<p><b>Original Excel remarks</b><br>' + escaped(row.private_remarks) + '</p>' : '') +
        '</article>').join('') || 'No archived schedules for this month.';
      renderStatus(pane,'');
    } catch (error) { if ($(id + '-month').value === value && context()?.token === token) renderStatus(pane,error.message); }
  }

  function anniversary(joined, year) {
    const [, month, day] = joined.split('-').map(Number);
    return year + '-' + String(month).padStart(2,'0') + '-' +
      String(Math.min(day,new Date(Date.UTC(year,month,0)).getUTCDate())).padStart(2,'0');
  }
  function serviceYears(joined,today) {
    const first = Number(joined.slice(0,4));
    const current = Number(today.slice(0,4));
    const newest = anniversary(joined,current) > today ? current-1 : current;
    return Array.from({length:Math.max(0,Math.min(31,newest-first+1))},(_,i)=>anniversary(joined,newest-i));
  }
  function serviceLength(joined, today) {
    const [year,month,day] = joined.split('-').map(Number);
    const [currentYear,currentMonth] = today.split('-').map(Number);
    const addMonths = count => {
      const target = new Date(Date.UTC(year,month - 1 + count,1));
      const days = new Date(Date.UTC(target.getUTCFullYear(),target.getUTCMonth() + 1,0)).getUTCDate();
      target.setUTCDate(Math.min(day,days));
      return target;
    };
    const end = new Date(today);
    let months = (currentYear-year)*12+currentMonth-month;
    if (addMonths(months)>end) months--;
    const days = Math.round((end-addMonths(months))/86400000);
    const units = [[Math.floor(months/12),'year'],[months%12,'month'],[days,'day']];
    const parts = units.filter(([count])=>count).map(([count,unit])=>count+' '+unit+(count===1?'':'s'));
    return parts.length ? new Intl.ListFormat('en',{type:'conjunction'}).format(parts) : '0 days';
  }
  const journeyDateFormat = new Intl.DateTimeFormat('en-GB',{day:'numeric',month:'short',year:'numeric',timeZone:'UTC'});
  const journeyDate = value => new Date(value + 'T00:00:00Z');
  const journeyIcon = icon => '<span class="hr-journey-icon" aria-hidden="true">' + icon + '</span>';
  const journeyRange = (from,to) => journeyDateFormat.formatRange(journeyDate(from),journeyDate(to));
  const leaveBadge = status => '<span class="hr-leave-badge" data-status="' + escaped(status) + '">' + escaped(status==='Declined'?'Rejected':status) + '</span>';
  function leaveCard(request, today, action = '') {
    const from = request.approved_from || request.requested_from;
    const to = request.approved_to || request.requested_to;
    const monthOnly = request.state === 'Recorded' && ['Cancelled Off','Attendance Note'].includes(request.kind);
    const when = request.kind==='Resignation' ? 'Last Working Day: '+journeyDateFormat.format(journeyDate(from)) : request.service_year && !from ? 'N/A · Service year ' + journeyDateFormat.format(journeyDate(request.service_year)) :
      monthOnly ? period(request) : journeyRange(from,to);
    return '<article class="hr-leave-card" data-request-id="'+escaped(request.id||'')+'">' + journeyIcon(request.kind === 'Annual Leave' ? '🌴' : '📋') +
      '<div class="hr-leave-card-body"><strong>' + escaped(request.kind) + '</strong><p class="hr-leave-dates">' +
      escaped(when) + '</p>' +
      (request.payroll && request.kind!=='Resignation' ? '<p class="hr-leave-dates">' + escaped(request.payroll) + '</p>' : '') +
      (request.review_note ? '<p class="hr-leave-note">' + (request.state==='Declined'?'<strong>Reason for rejection</strong><br>':'') + escaped(request.review_note) + '</p>' : '') + action +
      '</div>' + leaveBadge(leaveStatus(request,today)) + '</article>';
  }
  function journeySvg(key) {
    const paths = {
      calendar:'<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 11h18M8 15h2M14 15h2"/>',
      id:'<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M9 5V3h6v2M14 11h4M14 15h4"/><circle cx="8" cy="11" r="2"/><path d="M5 17v-1a3 3 0 0 1 6 0v1"/>',
      briefcase:'<rect x="3" y="7" width="18" height="14" rx="2"/><path d="M8 7V4h8v3M3 12a20 20 0 0 0 18 0M10 12h4v4h-4z"/>',
      pin:'<path d="M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="3"/>',
      phone:'<path d="m5 3 4 1 1 5-3 2a16 16 0 0 0 6 6l2-3 5 1 1 4c-1 5-9 1-13-3S0 4 5 3Z"/>',
      mail:'<rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 6 9 7 9-7"/>',
      home:'<path d="m3 10 9-8 9 8M5 9v12h5v-7h4v7h5V9"/>',
      globe:'<circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18M5 6h14M5 18h14"/>',
      cake:'<path d="M4 12h16v9H4zM4 16c3 3 5-3 8 0s5-3 8 0M8 12V8M12 12V8M16 12V8M8 5V3M12 5V3M16 5V3"/>',
      clock:'<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/>',
      person:'<circle cx="12" cy="7" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/>',
      sparkle:'<path d="m12 2 3 7 7 3-7 3-3 7-3-7-7-3 7-3Z"/>',
      check:'<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 11h18m-12 5 2 2 4-4"/>'
    };
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (paths[key] || paths.person) + '</svg>';
  }
  function journeyMarkup(data) {
    const profile = data.profile || {};
    const today = date(), joined = profile.joining_date;
    const name = context()?.user?.name;
    const details = [
      ['calendar','Joining date',joined && journeyDateFormat.format(journeyDate(joined))],
      ['id','Employee ID',profile.employee_code],
      ['briefcase','Position',profile.position],
      ['pin','Branch',profile.branch],...Object.entries({mobile:'Mobile / WhatsApp',email:'Email',address:'Address',nationality:'Nationality',date_of_birth:'Date of birth',employment_type:'Employment type',probation_end:'Probation end date',emergency_name:'Emergency contact',emergency_relationship:'Relationship',emergency_phone:'Emergency phone'}).filter(([key])=>profile[key]).map(([key,label])=>[({mobile:'phone',email:'mail',address:'home',nationality:'globe',date_of_birth:'cake',employment_type:'clock',probation_end:'calendar',emergency_name:'person',emergency_relationship:'person',emergency_phone:'phone'})[key],label,profile[key]]),
    ];
    const initials = (name || 'GOYA').trim().split(/\s+/).slice(0,2).map(part=>Array.from(part)[0]).join('').toUpperCase();
    let markup = '<div class="hr-journey-profile"><div class="hr-journey-identity"><h3>' + escaped(name || 'Staff profile') +
      '</h3><p>' + escaped(profile.position || 'N/A') + '</p><span>' + escaped(profile.employee_code || 'N/A') +
      '</span></div><div class="hr-journey-photo"><span aria-hidden="true">' + escaped(initials) +
      '</span><img alt="Profile photo" data-profile-photo hidden></div></div><div class="hr-service">' + journeyIcon(journeySvg('sparkle')) + '<div>';
    if (joined && joined <= today) {
      markup += '<p>Congratulations' + (name ? ', ' + escaped(name) : '') +
        '! You’ve been part of GOYA for <strong>' + serviceLength(joined,today) + '</strong></p>';
    } else {
      markup += '<span class="small">Time at GOYA</span><strong>' + (joined ? 'Upcoming' : 'N/A') + '</strong>';
    }
    markup += '</div></div><dl class="hr-journey-details">' + details.map(([icon,label,value]) =>
      '<div' + (['Mobile / WhatsApp','Email','Address','Employment type','Emergency contact','Emergency phone'].includes(label) ? ' class="hr-journey-detail-wide"' : '') + '><dt>' + journeyIcon(journeySvg(icon)) + '<span>' + label + '</span></dt><dd>' + escaped(value || 'N/A') + '</dd></div>').join('') + '</dl>';
    const pending = data.off_balance ? {value:data.off_balance.balance,week:(data.off_balance.updated_at||data.off_balance.source_week||'').slice(0,10)} : data.archived_pending_off;
    markup += '<div class="hr-pending-off">' + journeyIcon(journeySvg('check')) +
      '<div><h3>'+(Number(pending?.value)<0?'Advance Day Off':'Pending Day Off')+'</h3><p>'+(Number(pending?.value)<0?'Advance off taken':'PH/PO') +
      (pending?.week ? ' · As of ' + escaped(journeyDateFormat.format(journeyDate(pending.week))) : '') +
      '</p></div><strong>' + escaped(pending?.value ?? 'N/A') + '</strong></div>';
    const history = data.annual_history || [];
    const originals = new Map(data.requests.filter(item => item.kind === 'Annual Leave' && item.state === 'Approved')
      .map(item=>[item.id,item]));
    const replaced = new Set(history.map(item=>item.source_id).filter(Boolean));
    const annual = [...Array.from(originals.values()).filter(item=>!replaced.has(item.id)), ...history.map(item=>({
      kind:'Annual Leave',state:'Done',approved_from:item.leave_from,approved_to:item.leave_to,
      service_year:item.service_year,review_note:item.note,payroll:originals.get(item.source_id)?.payroll,
    }))].sort((a,b)=>(b.approved_from || b.service_year || '').localeCompare(a.approved_from || a.service_year || ''));
    if (annual.length) {
      markup += '<h3 class="hr-journey-heading">Annual leave history</h3><div class="hr-leave-list">' +
        annual.map(item => leaveCard(item,today)).join('') + '</div>';
    }
    if (!profile.joining_date) return markup;
    const thisYear = Number(today.slice(0,4));
    const current = anniversary(profile.joining_date,thisYear);
    const startYear = current > today ? thisYear - 1 : thisYear;
    markup += '<h3 class="hr-journey-heading">Annual leave entitlement</h3>' +
      '<p class="hr-entitlement-rule">1 month per completed service year</p><ul class="hr-entitlement-list">';
    for (let year = startYear; year >= Math.max(Number(profile.joining_date.slice(0,4)),startYear - 30); year--) {
      const start = anniversary(profile.joining_date,year), next = anniversary(profile.joining_date,year + 1);
      const used = annual.filter(item => item.service_year ? item.service_year === start :
        item.approved_from < next && item.approved_to >= start);
      const archived = (data.archived_annual_days || []).filter(day=>day>=start && day<next && day<today);
      const status = used.some(item => leaveStatus(item,today) === 'In progress') ? 'In progress' :
        used.some(item => leaveStatus(item,today) === 'Done') ? 'Done' : used.length ? 'Approved' :
        archived.length ? 'Recorded in Excel (' + archived.length + ' dates)' :
        year === Number(profile.joining_date.slice(0,4)) ? 'First service year' : 'No approved leave recorded';
      markup += '<li><span>' + escaped(journeyRange(start,next)) + '</span>' + leaveBadge(status) + '</li>';
    }
    return markup + '</ul>';
  }
  function showMyRequests(pane, items) {
    const today = date();
    const holder=content(pane),previousType=holder.querySelector('[data-my-request-type]')?.value||'',previousStatus=holder.querySelector('[data-my-request-status]')?.value||'';
    const filterBar=document.createElement('div');filterBar.className='toolbar hr-my-request-filters';
    filterBar.innerHTML='<label>Leave type<select data-my-request-type><option value="">All types</option>'+[...new Set(items.map(r=>r.kind))].map(k=>'<option>'+escaped(k)+'</option>').join('')+'</select></label><label>Status<select data-my-request-status><option value="">All statuses</option>'+['Pending','Approved','In progress','Done','Declined','Withdrawn','Recorded'].map(k=>'<option value="'+k+'">'+(k==='Declined'?'Rejected':k)+'</option>').join('')+'</select></label><span class="small" data-my-request-count></span>';
    content(pane).innerHTML = items.length ? '<div class="hr-leave-list">' + items.map((request,i) =>
      leaveCard(request,today,(['Annual Leave','Resignation'].includes(request.kind)&&request.state==='Pending'?'<button type="button" class="btn secondary" data-open-email="'+i+'">Open Email</button>':'')+(request.state === 'Pending' ? '<button type="button" class="btn secondary" data-withdraw="' + i +
        '">Withdraw</button>' : ''))).join('') + '</div>' : 'No requests yet.';
    holder.prepend(filterBar);
    const type=filterBar.querySelector('[data-my-request-type]'),status=filterBar.querySelector('[data-my-request-status]');
    type.value=previousType;status.value=previousStatus;
    const filter=()=>{let count=0;holder.querySelectorAll('.hr-leave-card').forEach((card,i)=>{const r=items[i],show=(!type.value||type.value===r.kind)&&(!status.value||status.value===leaveStatus(r,today));card.hidden=!show;if(show)count++;});filterBar.querySelector('[data-my-request-count]').textContent=count+' of '+items.length+' requests';};
    type.onchange=status.onchange=filter;filter();
    content(pane).querySelectorAll('[data-open-email]').forEach(b=>b.onclick=()=>openRequestEmail(items[b.dataset.openEmail].id,b));
    content(pane).querySelectorAll('[data-withdraw]').forEach(button => {
      button.onclick = async () => {
        if (!confirm('Withdraw this leave request?')) return;
        const status = $('hr-request-status'), token = context()?.token, generation = staffGeneration;
        button.disabled = true;
        if (status) status.textContent = 'Withdrawing…';
        try {
          await rpc('goya_hr_withdraw_request',{p_id:items[button.dataset.withdraw].id});
          if (generation !== staffGeneration) return;
          await openStaffTab('leave');
          if (status && context()?.token === token) status.textContent = 'Request withdrawn.';
        } catch (error) {
          if (generation !== staffGeneration) return;
          await openStaffTab('leave');
          if (status && context()?.token === token) status.textContent = error.message;
        }
      };
    });
  }
  async function openStaffTab(name) {
    const generation = ++staffGeneration;
    for (const id of ['schedule','journey','leave']) $('hr-' + id).hidden = name !== id;
    document.querySelectorAll('[data-hr-tab]').forEach(button =>
      button.setAttribute('aria-pressed',String(button.dataset.hrTab === name)));
    if (name === 'schedule') return;
    const pane = $('hr-' + name);
    empty(pane,'Loading…');
    if (name === 'journey') renderStatus(pane,'');
    if (name === 'journey') {
      const documents = pane.querySelector('[data-hr-documents]');
      if (documents) {
        documents.querySelector('[data-add-document]').onclick = () => documentEditor(documents);
        void loadDocuments(documents);
      }
    } else {
      $('hr-request-status')?.replaceChildren();
    }
    try {
      const history = name === 'journey' ? rpc('goya_hr_annual_history').catch(error=>error) : Promise.resolve([]);
      const [data, annual] = await Promise.all([rpc('goya_management_journey'),history]);
      if (generation !== staffGeneration) return;
      currentOffBalance=data.off_balance?.balance??null;
      updateRequestFields();
      if (name === 'journey') {
        content(pane).innerHTML = journeyMarkup({...data,annual_history:Array.isArray(annual) ? annual : []});
        void showProfilePhoto(pane.querySelector('[data-profile-photo]'),null);
        if (annual instanceof Error) renderStatus(pane,'Additional annual leave history could not be loaded. Reopen My Journey to retry.');
        else renderStatus(pane,'');
      } else showMyRequests(pane,data.requests);
    } catch (error) { if (generation === staffGeneration) empty(pane,error.message); }
  }
  async function documentRequest(token, body, json = false, signal) {
    const headers = {'x-goya-session':token};
    if (json) headers['Content-Type'] = 'application/json';
    const response = await fetch(config().SUPABASE_URL + '/functions/v1/staff-documents',{
      method:'POST',headers,body:json ? JSON.stringify(body) : body,cache:'no-store',signal,
    });
    if (!response.ok) {
      const result = await response.json().catch(()=>null);
      throw Error(result?.error || 'Unable to access this document.');
    }
    return response;
  }
  async function openDocument(row, staff, downloadFile, status, current) {
    const token = context()?.token;
    if (!token) return;
    const preview = downloadFile ? null : window.open('about:blank','_blank');
    if (!downloadFile && !preview) {
      status.textContent = 'Allow pop-ups to view the document.';
      return;
    }
    if (preview) {
      preview.opener = null;
      preview.document.body.textContent = 'Loading document…';
    }
    status.textContent = 'Opening document…';
    try {
      const result = await documentRequest(token,{id:row.id,staff},true);
      const blob = await result.blob();
      if (!current()) { preview?.close(); return; }
      const url = URL.createObjectURL(blob);
      setTimeout(()=>URL.revokeObjectURL(url),120000);
      if (preview) preview.location.replace(url);
      else {
        const link = document.createElement('a');
        link.href = url;
        link.download = row.file_name;
        document.body.append(link);
        link.click();
        link.remove();
      }
      status.textContent = '';
    } catch (error) {
      preview?.close();
      if (current()) status.textContent = error.message;
    }
  }
  function documentEditor(pane, staff = null, row = null, preferredTitle = '') {
    const token = context()?.token;
    const generation = documentGeneration;
    const current = () => pane.isConnected && token === context()?.token &&
      (staff || generation === documentGeneration);
    const categoryTitle = item => documentCategories.find(([key])=>key===item.category)?.[2] || item.custom_title;
    const options = documentCategories.map(([key,,title])=>'<option value="' + key + '">' + title + '</option>').join('');
    let uploadId = crypto.randomUUID(), customKey = 'custom-' + crypto.randomUUID();
    const extra = staff && !row ? '<label hidden data-custom-title>Document name<input name="title" maxlength="100"></label>' : '';
    const node = dialog(row ? 'Replace · ' + categoryTitle(row) : staff ? 'Upload Document' : 'Add Files',
      (row ? '' : '<label>Document type<select name="category" required><option value="">Choose a document type</option>' +
        options + (staff ? '<option value="custom">Custom document</option>' : '') + '</select></label><p class="small muted" data-document-completion>Checking submitted documents…</p>') + extra +
      '<label>File<input type="file" name="file" accept="' + documentTypes.join(',') + '" required></label>' +
      '<label>Expiry date (optional)<input type="date" name="expires" value="'+escaped(row?.expires_on||'')+'"></label><p class="small muted">PDF, JPG or PNG up to 5 MB per document. Profile photos must be JPG or PNG.</p>',
      async input => {
        if (!current() || !token) throw Error('Sign in again and reopen this page.');
        const file = input.file;
        const category = row?.category || (input.category === 'custom' ? customKey : input.category);
        const title = row?.custom_title || (input.category === 'custom' ? input.title.trim() : '');
        if (input.category === 'custom' && !title) throw Error('Enter a document name.');
        if (!documentTypes.includes(file?.type) || !file.size || file.size > 5000000) {
          throw Error('Choose a PDF, JPG or PNG up to 5 MB.');
        }
        renderStatus(node,'Uploading…');
        const body = new FormData();
        body.set('id',uploadId);
        body.set('category',category);
        if (staff) body.set('staff',staff);
        if (title) body.set('title',title);
        body.set('file',file);
        if(category==='profile-photo'&&!['image/jpeg','image/png'].includes(file.type))throw Error('Choose a JPG or PNG profile photo.');
        await documentRequest(token,body);
        await rpc('goya_people_document_expiry',{p_id:uploadId,p_staff:staff,p_expires:input.expires||null});
        if (current()) await loadDocuments(pane,staff);
      },'Upload');
    const form = node.querySelector('form');
    if(!row){const select=form.elements.category,feedback=node.querySelector('[data-document-completion]');rpc('goya_hr_documents',{p_staff:staff}).then(files=>{if(!node.isConnected||!current())return;if(!Array.isArray(files))throw Error('Unavailable');const done=new Set(files.filter(file=>file.uploaded_at).map(file=>file.category));for(const option of select.options){const title=documentCategories.find(([key])=>key===option.value)?.[2];if(title)option.textContent=title+(done.has(option.value)?' — ✓ Done':'');}feedback.textContent='✓ Done means a document is already uploaded. You can still upload a newer version.';}).catch(()=>{if(node.isConnected&&current())feedback.textContent='Previous uploads could not be checked. You can still upload a document.';});}
    if(preferredTitle&&staff&&!row){form.elements.category.value='custom';form.elements.title.value=preferredTitle;form.elements.title.required=true;form.querySelector('[data-custom-title]').hidden=false;}
    form.onchange = () => {
      uploadId = crypto.randomUUID();
      customKey = 'custom-' + crypto.randomUUID();
      const field = form.querySelector('[data-custom-title]');
      if (field) {
        field.hidden = form.elements.category.value !== 'custom';
        form.elements.title.required = !field.hidden;
      }
    };
  }
  async function loadDocuments(pane, staff = null) {
    const token = context()?.token, generation = documentGeneration;
    const current = () => pane.isConnected && token === context()?.token && (staff || generation === documentGeneration);
    const status = pane.querySelector('[role=status]'), list = pane.querySelector('.hr-document-list');
    status.textContent = 'Loading documents…';
    try {
      const rows = await rpc('goya_hr_documents',{p_staff:staff});
      if (!current()) return;
      list.innerHTML = rows.map((row,index) => {
        const [,icon,title] = documentCategories.find(([key])=>key===row.category) || [row.category,'📎',row.custom_title || 'Document'];
        const button = (mode,label) => '<button type="button" class="btn secondary" data-file-mode="' + mode +
          '" data-file-index="' + index + '">' + label + '</button>';
        const name = staff ? '<strong>' + escaped(row.file_name) + '</strong>' : '';
        const date = escaped(uploadDate.format(new Date(row.uploaded_at)));
        const version = staff ? (row.version_rank === 1 ? 'Current · ' : 'Previous · ') : '';
        const menu = '<details class="hr-document-menu"><summary aria-label="More options for ' + escaped(title) +
          '">⋯</summary><div>' +
          (row.version_rank===1 && (staff || !row.custom_title) ? button('replace','Replace') : '') +
          button('download','Download') + '</div></details>';
        return '<article class="hr-document-card hr-file-card"><div><h3><span aria-hidden="true">' +
          icon + '</span> ' + escaped(title) + '</h3>' + name + '<small>' + version + date + '</small>' +
          (row.expires_on?'<small class="hr-document-expiry">Expires: '+escaped(row.expires_on)+'</small>':'')+'</div><div class="hr-document-actions">' + button('view','View') + menu + '</div></article>';
      }).join('') || '<p class="small muted">No documents uploaded.</p>';
      list.querySelectorAll('[data-file-mode]').forEach(button => {
        const row = rows[button.dataset.fileIndex];
        button.onclick = () => {
          if (button.dataset.fileMode === 'replace') documentEditor(pane,staff,row);
          else void openDocument(row,staff,button.dataset.fileMode==='download',status,current);
        };
      });
      status.textContent = '';
    } catch (error) {
      if (current()) status.textContent = error.message;
    }
  }

  async function profilePhoto(staff){
    const token=context()?.token,rows=await rpc('goya_hr_documents',{p_staff:staff});
    const photo=rows.find(r=>r.category==='profile-photo'&&Number(r.version_rank)===1);if(!photo)return null;
    const response=await documentRequest(token,{id:photo.id,staff},true),blob=await response.blob();
    if(context()?.token!==token)throw Error('Session changed.');return blob;
  }
  async function showProfilePhoto(img,staff){if(!img||img.dataset.loading)return;img.dataset.loading='1';try{const blob=await profilePhoto(staff);if(!blob||!img.isConnected)return;const url=URL.createObjectURL(blob);img.src=url;img.hidden=false;img.onload=()=>URL.revokeObjectURL(url);}catch{}finally{delete img.dataset.loading;}}
  async function openRequestEmail(id,button){
    const pane=$('hr-leave'),status=pane?.querySelector('[role=status]');if(button)button.disabled=true;
    try{const data=await rpc('goya_people_email_draft',{p_request:id}),r=data.request,s=data.staff;
      const valid=v=>typeof v==='string'&&/^[^\s@,;<>]+@[^\s@,;<>]+\.[^\s@,;<>]+$/.test(v);
      if(!valid(data.owner)||!valid(data.hr))throw Error('Request saved. Management needs to set both Owner and HR email addresses.');
      const to=[...new Set([data.owner,data.hr])],cc=valid(data.manager)&&!to.includes(data.manager)?data.manager:'';
      if(!['Annual Leave','Resignation'].includes(r.kind))throw Error('Email drafts are available for annual leave and resignation requests only.');
      if(r.state && r.state!=='Pending')throw Error('Email drafts are available for pending requests only.');
      const formatDate=(value,month='short')=>{
        const stamp=new Date(String(value).slice(0,10)+'T00:00:00Z');
        return Number.isNaN(stamp.getTime())?String(value||''):new Intl.DateTimeFormat('en-GB',{day:'2-digit',month,year:'numeric',timeZone:'UTC'}).format(stamp);
      };
      const resign=r.kind==='Resignation';
      const dates=resign?'Last Working Day: '+formatDate(r.requested_from):formatDate(r.requested_from)+' to '+formatDate(r.requested_to);
      const subject='GOYA '+r.kind+' Request - '+s.name+' - '+dates;
      const details=['Employee Details','Name: '+s.name,'Staff ID: '+(s.code||''),'Position: '+(s.position||''),'Mobile: '+(s.mobile||'')];
      const reason=typeof r.reason==='string'?r.reason.trim():'';
      const body=['Dear Management and HR Team,','',
        resign?'Please accept this email as formal notice of my resignation from my position as '+(s.position||'a staff member')+' at GOYA. My proposed last working day is '+formatDate(r.requested_from,'long')+', subject to confirmation of the applicable notice period.':
          'I am writing to request approval for my annual leave from '+formatDate(r.requested_from,'long')+' to '+formatDate(r.requested_to,'long')+'.',
        '',...details,'',...(resign?['Last Working Day: '+formatDate(r.requested_from,'long')]:
          ['Leave Details','Start Date: '+formatDate(r.requested_from,'long'),'End Date: '+formatDate(r.requested_to,'long')]),
        ...(reason?['',resign?'Reason for Resignation:':'Reason for Leave:',reason]:[]),'',
        ...(resign?['Thank you for the opportunities and support provided during my employment. I will cooperate with the handover process to help ensure a smooth transition.','',
          'Kindly acknowledge receipt of my resignation and confirm my last working day and any required exit formalities.']:
          ['I would appreciate your review and approval of this request. Please let me know if any further information is required.','','Thank you for your consideration.']),
        '','Kind regards,',s.name,[s.position,s.code].filter(Boolean).join(' | ')].join('\n');
      const link=document.createElement('a');link.href='mailto:'+to.map(encodeURIComponent).join(',')+'?'+(cc?'cc='+encodeURIComponent(cc)+'&':'')+'subject='+encodeURIComponent(subject)+'&body='+encodeURIComponent(body);document.body.append(link);link.click();link.remove();
      if(status)status.textContent='Request saved. Review the draft in your email app and press Send. Attach supporting files manually if needed.';
    }catch(e){if(status)status.textContent=e.message;}finally{if(button)button.disabled=false;}
  }

  async function submitLeave(event) {
    event.preventDefault();
    const form = event.currentTarget, button = form.querySelector('button[type=submit]');
    const token = context()?.token, body = new FormData(form);
    if(body.get('kind')==='Resignation')body.set('to',body.get('from'));
    if (!token) return renderStatus(form,'Sign in again.');
    if (body.get('file')?.size > 5000000) return renderStatus(form,'Choose a file up to 5 MB.');
    submissionId ||= crypto.randomUUID();
    body.set('id',submissionId);
    button.disabled = true;
    const fields = Array.from(form.elements).filter(field=>field!==button);
    fields.forEach(field=>field.disabled = true);
    renderStatus(form,'Submitting…');
    try {
      const response = await fetch(config().SUPABASE_URL + '/functions/v1/staff-leave', {
        method:'POST',headers:{'x-goya-session':token},body
      });
      const result = await response.json();
      if (context()?.token !== token) return;
      if (!response.ok) throw Error(result.error || 'Unable to submit leave.');
      form.reset();
      updateRequestFields();
      submissionId = null;
      if (!$('hr-leave').hidden) await openStaffTab('leave');
      renderStatus(form,result.compose ? 'Request saved. Select Open Email below to review your draft and send it to Owner and HR.' : result.email === 'Sent' ? 'Request saved. Email sent.' : 'Request saved. Email notification is unavailable.');
    } catch (error) { if (context()?.token === token) renderStatus(form,error.message); }
    finally { button.disabled = false; fields.forEach(field=>field.disabled = false); }
  }

  function updateRequestFields(){
    const form=$('hr-leave-form');if(!form)return;
    const resign=form.elements.kind.value==='Resignation';
    $('hr-from-label').textContent=resign?'Last Working Day':'From';
    $('hr-to-label').hidden=resign;form.elements.to.required=!resign;
    if(resign)form.elements.to.value=form.elements.from.value;
    const from=form.elements.from.value,to=form.elements.to.value;
    const days=Math.round((Date.parse(to)-Date.parse(from))/86400000)+1;
    $('hr-request-days').textContent=resign?'Submit your resignation letter and proposed last working day. Management will review your request.':Number.isFinite(days)&&days>0?'Total: '+days+' day'+(days===1?'':'s'):'Choose your leave dates.';
    if(['Pending Off','Advance Off'].includes(form.elements.kind.value))$('hr-request-days').textContent+=' Current Off Balance: '+(currentOffBalance??'N/A')+'. A deduction is made only after approval.';
  }
  function init() {
    if ($('hr-email-settings')) $('hr-email-settings').querySelector('form').onsubmit = saveEmailSettings;
    if ($('hr-records')) {
      $('hr-record-filter').onchange = renderRecords;
      $('hr-record-search').oninput = renderRecords;
      $('hr-preview-import').onclick = prepareImport;
      $('hr-commit-import').onclick = importArchive;
      $('hr-admin-archive-month').onchange = () => showArchive(true);
      $('hr-workbook').onchange = () => {
        archiveRows = [];
        $('hr-commit-import').disabled = true;
        $('hr-admin-archive').querySelector('.hr-mapping').replaceChildren();
      };
      $('hr-request-month').onchange = ()=>openRequests(true);
      $('hr-request-search').oninput=renderRequests;
      $('hr-pending-tab').onclick=()=>{$('hr-request-filter').value='Pending';renderRequests();};
      $('hr-all-tab').onclick=()=>{$('hr-request-filter').value='All requests';renderRequests();};
      $('hr-request-filter').onchange = renderRequests;
      if($('hr-request-type'))$('hr-request-type').onchange=renderRequests;
      $('hr-record-export').onclick = () => download('GOYA-Staff-Records.csv',
        [['Name','Status','Employee ID','Position','Branch','Joining Date','Last Day'], ...filteredProfiles().map(member =>
          [member.name,stateOf(member),member.profile?.employee_code,member.profile?.position,member.profile?.branch,
            member.profile?.joining_date,member.profile?.last_day])]);
      $('hr-request-export').onclick = () => download('GOYA-Leave-Records.csv',
        [['Staff','Type','Period','Status','Payroll','Management name','Decision time','Private note'], ...filteredRequests().flatMap(request =>
          (request.management_history?.length?request.management_history:[null]).map(h=>[request.name,request.kind,period(request),leaveStatus(request),request.payroll,h?.actor,h?.created_at,h?.note]))]);
    }
    if ($('hr-leave-form')) {
      document.querySelectorAll('[data-hr-tab]').forEach(button => button.onclick = () => openStaffTab(button.dataset.hrTab));
      $('hr-leave-form').onsubmit = submitLeave;
      $('hr-leave-form').oninput = () => { submissionId = null; updateRequestFields(); };
      $('hr-leave-form').elements.kind.onchange=updateRequestFields;
      updateRequestFields();
      $('hr-staff-archive-month').onchange = () => showArchive(false);
    }
  }
  if(location.hash==='#staff-requests' && document.getElementById('hr-requests')){let attempts=0;const jump=setInterval(()=>{if(++attempts>120){clearInterval(jump);return;}if(!context()?.token)return;clearInterval(jump);window.GoyaAttendance.nav(null,'hr-requests');openRequests(true);},1000);}
  window.GoyaHR = {documentBlob:async(row,staff)=>{const token=context()?.token;if(!token)throw Error('Sign in again.');const response=await documentRequest(token,{id:row.id,staff},true,AbortSignal.timeout(45000)),blob=await response.blob();if(context()?.token!==token)throw Error('Session changed. Please retry the Staff File download.');if(row.byte_size&&blob.size!==Number(row.byte_size))throw Error('A document download was incomplete. Please retry.');return blob;},profilePhoto,uploadDocument:body=>documentRequest(context()?.token,body),openRequestEmail,documentEditor,openRecords,openRequests,openStaffTab,resetStaff,openEmailSettings,openRejoin:rejoinEditor};
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded',init,{once:true});
  else init();
})();
