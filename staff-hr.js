(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const context = () => window.GoyaAdmin?._context() ?? window.GoyaAttendance?._liveContext() ?? window.GoyaStaff?._liveContext();
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
  let submissionId;
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

  function dialog(title, body, handler) {
    const node = document.createElement('dialog');
    node.className = 'hr-dialog';
    node.innerHTML = '<form><h2>' + escaped(title) + '</h2>' + body +
      '<p role="status"></p><div class="hr-tabs"><button class="btn primary" type="submit">Save</button>' +
      '<button class="btn secondary" type="button">Cancel</button></div></form>';
    document.body.append(node);
    node.querySelector('button[type=button]').onclick = () => node.close();
    node.addEventListener('close', () => node.remove(), {once:true});
    const form = node.querySelector('form');
    form.addEventListener('submit', async event => {
      event.preventDefault();
      const buttons = Array.from(form.querySelectorAll('button'));
      buttons.forEach(button => button.disabled = true);
      try {
        await handler(values(form));
        node.close();
      } catch (error) {
        renderStatus(node, error.message);
      } finally {
        buttons.forEach(button => button.disabled = false);
      }
    });
    node.showModal();
    return node;
  }
  function profileEditor(member, refresh) {
    const profile = member.profile || {};
    const field = (key, label, type='text') => '<label>' + label + '<input name="' + key + '" type="' +
      type + '" value="' + escaped(profile[key]) + '"></label>';
    dialog(member.name, '<div class="hr-fields">' + field('employee_code','Employee ID') +
      field('position','Position') + field('branch','Branch') + field('joining_date','Joining date','date') +
      field('last_day','Last working day','date') + '</div>' +
      '<label>Private manager notes<textarea name="manager_notes" maxlength="4000">' +
      escaped(profile.manager_notes) + '</textarea></label>', async input => {
      if (input.last_day && input.last_day !== profile.last_day &&
          !confirm('Record resignation and deactivate portal access for ' + member.name + '?')) return;
      await rpc('goya_hr_save_profile', {p_staff:member.id,p_profile:input});
      await refresh();
    });
  }
  function resetStaff() {
    staffGeneration++;
    submissionId = null;
    const form = $('hr-leave-form');
    if (!form) return;
    form.reset();
    renderStatus(form,'');
    for (const name of ['journey','leave','staff-archive']) empty($('hr-' + name),'');
    $('hr-staff-archive-month').value = '';
    $('hr-staff-archive').open = false;
  }
  function rejoinEditor(member, refresh) {
    dialog('Rejoin · ' + member.name, '<label>Rejoin date<input type="date" name="date" value="' + date() +
      '" required></label>', async input => {
      await rpc('goya_hr_rejoin', {p_staff:member.id,p_date:input.date});
      await refresh();
    });
  }

  function filteredProfiles() {
    const filter = $('hr-record-filter').value;
    return profiles.filter(member => filter === 'All staff' || stateOf(member) === filter);
  }
  function renderRecords() {
    const pane = $('hr-records');
    const items = filteredProfiles();
    content(pane).innerHTML = items.map((member, i) => '<article class="hr-entry"><strong>' + escaped(member.name) +
      ' · ' + stateOf(member) + '</strong><p>' +
      [member.profile?.position,member.profile?.branch,member.profile?.employee_code,
        member.profile?.joining_date && 'Joined ' + member.profile.joining_date,
        member.profile?.last_day && 'Last day ' + member.profile.last_day].filter(Boolean).map(escaped).join(' · ') +
      '</p>' + (member.history || []).map(item => '<p class="small muted">' + escaped(item.event) + ' · ' +
        escaped(item.details.rejoined_on || item.details.last_day) + '</p>').join('') +
      '<button type="button" class="btn secondary" data-edit="' + i + '">Edit profile</button> ' +
      (member.profile?.last_day ? '<button type="button" class="btn secondary" data-rejoin="' + i + '">Rejoin</button>' : '') +
      '</article>').join('');
    if (!items.length) empty(pane,'No staff match this filter.');
    content(pane).querySelectorAll('[data-edit]').forEach(button =>
      button.onclick = () => profileEditor(items[button.dataset.edit], openRecords));
    content(pane).querySelectorAll('[data-rejoin]').forEach(button =>
      button.onclick = () => rejoinEditor(items[button.dataset.rejoin], openRecords));
  }
  async function openRecords() {
    const pane = $('hr-records');
    profiles = [];
    empty(pane,'');
    renderStatus(pane,'Loading records…');
    try {
      profiles = await rpc('goya_hr_admin_profiles');
      renderRecords();
      renderStatus(pane,'');
    } catch (error) { renderStatus(pane,error.message); }
  }
  const period = request => {
    const from = request.approved_from || request.requested_from;
    const to = request.approved_to || request.requested_to;
    return from === to ? from : from + ' – ' + to;
  };
  function filteredRequests() {
    const filter = $('hr-request-filter').value;
    return requests.filter(request => filter === 'All requests' || request.state === filter);
  }
  function review(request) {
    const node = dialog('Review · ' + request.name,
      '<p>' + escaped(request.kind) + ' · ' + escaped(period(request)) + '</p><label>Decision<select name="decision">' +
      '<option value="Approved">Approve</option><option value="Declined">Decline</option></select></label>' +
      '<div class="hr-fields"><label>Approved from<input name="from" type="date" value="' +
      escaped(request.approved_from || request.requested_from) + '"></label><label>Approved to<input name="to" type="date" value="' +
      escaped(request.approved_to || request.requested_to) + '"></label><label>Payroll outcome<select name="payroll"></select></label></div>' +
      '<label>Note visible to staff<textarea name="note" maxlength="2000">' + escaped(request.review_note) + '</textarea></label>',
      async input => {
        await rpc('goya_hr_review', {p_id:request.id,p_expected:request.updated_at,p_state:input.decision,
          p_from:input.from || null,p_to:input.to || null,p_payroll:input.payroll || null,p_note:input.note});
        await openRequests();
      });
    const {decision, payroll, from, to} = node.querySelector('form').elements;
    if (request.state === 'Declined') decision.value = 'Declined';
    const showChoices = preferred => {
      const approved = decision.value === 'Approved';
      from.disabled = to.disabled = !approved;
      from.required = to.required = approved;
      const choices = approved
        ? (request.kind === 'Sick Leave' && !request.drive_file_id ? ['Unpaid'] : ['Paid','Unpaid'])
        : (request.kind === 'Sick Leave' ? ['','Absent'] : ['']);
      payroll.replaceChildren(...choices.map(item => new Option(item || 'No payroll decision', item)));
      if (choices.includes(preferred)) payroll.value = preferred;
    };
    decision.onchange = () => showChoices();
    showChoices(request.payroll);
  }
  function renderRequests() {
    const pane = $('hr-requests'), items = filteredRequests();
    content(pane).innerHTML = items.map((request,i) => '<article class="hr-entry"><strong>' + escaped(request.name) +
      ' · ' + escaped(request.kind) + ' · ' + escaped(request.state) + '</strong><p>' +
      escaped([period(request),request.payroll,'Email: ' + request.email_state].filter(Boolean).join(' · ')) + '</p><p>' +
      escaped(request.reason) + '</p>' +
      (/^[\w-]+$/.test(request.drive_file_id || '') ? '<p><a target="_blank" rel="noopener noreferrer" href="https://drive.google.com/open?id=' +
        request.drive_file_id + '">📎 Open private Drive document</a></p>' : '') +
      '<button type="button" class="btn secondary" data-review="' + i + '">Review request</button></article>').join('');
    if (!items.length) empty(pane,'No requests match this filter.');
    content(pane).querySelectorAll('[data-review]').forEach(button =>
      button.onclick = () => review(items[button.dataset.review]));
  }
  async function openRequests() {
    const pane = $('hr-requests'), generation = ++requestGeneration;
    requests = [];
    empty(pane,'');
    renderStatus(pane,'Loading requests…');
    const month = $('hr-request-month').value;
    try {
      const data = await rpc('goya_hr_admin_requests',{p_month:month ? month + '-01' : null});
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
      const members = await rpc('goya_hr_admin_profiles');
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
  function journeyMarkup(data) {
    const profile = data.profile || {};
    const details = [['Joining date',profile.joining_date],['Employee ID',profile.employee_code],
      ['Position',profile.position],['Branch',profile.branch]];
    let markup = '<dl>' + details.map(([label,value]) => '<dt>' + label + '</dt><dd>' + escaped(value || '—') + '</dd>').join('') + '</dl>';
    if (data.archived_pending_off) markup += '<p>Pending PH/PO in the Excel archive · ' +
      escaped(data.archived_pending_off.value) + ' (week of ' + escaped(data.archived_pending_off.week) + ')</p>';
    if (!profile.joining_date) return markup;
    const today = date(), thisYear = Number(today.slice(0,4));
    const current = anniversary(profile.joining_date,thisYear);
    const startYear = current > today ? thisYear - 1 : thisYear;
    const annual = data.requests.filter(item => item.kind === 'Annual Leave' && item.state === 'Approved');
    markup += '<h3>Annual leave</h3><p>Annual entitlement · 1 month per completed service year</p>';
    for (let year = startYear; year >= Math.max(Number(profile.joining_date.slice(0,4)),startYear - 30); year--) {
      const start = anniversary(profile.joining_date,year), next = anniversary(profile.joining_date,year + 1);
      const used = annual.filter(item => item.approved_from < next && item.approved_to >= start);
      const archived = (data.archived_annual_days || []).filter(day=>day>=start && day<next && day<today);
      const status = used.some(item => item.approved_to < today) ? 'Taken' : used.length ? 'Approved' :
        archived.length ? 'Recorded in Excel (' + archived.length + ' dates)' :
        year === Number(profile.joining_date.slice(0,4)) ? 'First service year' : 'No approved leave recorded';
      markup += '<p>' + start + ' to ' + next + ' (next anniversary) · ' + status + '</p>';
    }
    return markup;
  }
  async function openStaffTab(name) {
    const generation = ++staffGeneration;
    for (const id of ['schedule','journey','leave']) $('hr-' + id).hidden = name !== id;
    document.querySelectorAll('[data-hr-tab]').forEach(button =>
      button.setAttribute('aria-pressed',String(button.dataset.hrTab === name)));
    if (name === 'schedule') return;
    const pane = $('hr-' + name);
    empty(pane,'Loading…');
    try {
      const data = await rpc('goya_hr_my_journey');
      if (generation !== staffGeneration) return;
      content(pane).innerHTML = name === 'journey' ? journeyMarkup(data) : data.requests.map(request =>
        '<article class="hr-entry"><strong>' + escaped(request.kind) + ' · ' + escaped(request.state) +
        '</strong><p>' + escaped([period(request),request.payroll,request.review_note].filter(Boolean).join(' · ')) +
        '</p></article>').join('') || 'No requests yet.';
    } catch (error) { if (generation === staffGeneration) empty(pane,error.message); }
  }
  async function submitLeave(event) {
    event.preventDefault();
    const form = event.currentTarget, button = form.querySelector('button[type=submit]');
    const token = context()?.token, body = new FormData(form);
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
      submissionId = null;
      if (!$('hr-leave').hidden) await openStaffTab('leave');
      renderStatus(form,result.email === 'Sent' ? 'Request saved. Email sent.' : 'Request saved. Email could not be sent.');
    } catch (error) { if (context()?.token === token) renderStatus(form,error.message); }
    finally { button.disabled = false; fields.forEach(field=>field.disabled = false); }
  }

  function init() {
    if ($('hr-email-settings')) $('hr-email-settings').querySelector('form').onsubmit = saveEmailSettings;
    if ($('hr-records')) {
      $('hr-record-filter').onchange = renderRecords;
      $('hr-preview-import').onclick = prepareImport;
      $('hr-commit-import').onclick = importArchive;
      $('hr-admin-archive-month').onchange = () => showArchive(true);
      $('hr-workbook').onchange = () => {
        archiveRows = [];
        $('hr-commit-import').disabled = true;
        $('hr-admin-archive').querySelector('.hr-mapping').replaceChildren();
      };
      $('hr-request-month').onchange = openRequests;
      $('hr-request-filter').onchange = renderRequests;
      $('hr-record-export').onclick = () => download('GOYA-Staff-Records.csv',
        [['Name','Status','Employee ID','Position','Branch','Joining Date','Last Day'], ...filteredProfiles().map(member =>
          [member.name,stateOf(member),member.profile?.employee_code,member.profile?.position,member.profile?.branch,
            member.profile?.joining_date,member.profile?.last_day])]);
      $('hr-request-export').onclick = () => download('GOYA-Leave-Records.csv',
        [['Staff','Type','Period','Status','Payroll'], ...filteredRequests().map(request =>
          [request.name,request.kind,period(request),request.state,request.payroll])]);
    }
    if ($('hr-leave-form')) {
      document.querySelectorAll('[data-hr-tab]').forEach(button => button.onclick = () => openStaffTab(button.dataset.hrTab));
      $('hr-leave-form').onsubmit = submitLeave;
      $('hr-leave-form').oninput = () => { submissionId = null; };
      $('hr-staff-archive-month').onchange = () => showArchive(false);
    }
    if ($('adminStaff')) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'btn secondary';
      button.textContent = '👤 Employment profiles';
      button.onclick = async () => {
        button.disabled = true;
        try {
          const staff = await rpc('goya_hr_admin_profiles');
          const list = '<label>Staff member<select name="id" required>' +
            staff.map(member => '<option value="' + escaped(member.id) + '">' + escaped(member.name) + ' · ' +
              stateOf(member) + '</option>').join('') + '</select></label>';
          dialog('Employment profiles',list, input => {
            const member = staff.find(entry => entry.id === input.id);
            if (member) setTimeout(() => profileEditor(member,() => window.GoyaAdmin.refreshStaff()),0);
          });
        } catch (error) { alert(error.message); }
        finally { button.disabled = false; }
      };
      $('adminStaff').querySelector('.page-head').append(button);
    }
  }
  window.GoyaHR = {openRecords,openRequests,openStaffTab,resetStaff,openEmailSettings};
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded',init,{once:true});
  else init();
})();
