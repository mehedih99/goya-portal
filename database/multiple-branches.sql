begin;
set local lock_timeout='5s';
-- Branch identity is durable. Existing records remain GOYA; no history is removed.
create role goya_operations nologin nosuperuser nocreatedb nocreaterole noinherit nobypassrls;
grant goya_operations to postgres;
grant create on schema public,goya_private to goya_operations;
grant usage on schema public,goya_private,extensions,net to goya_operations;
grant execute on all functions in schema net to goya_operations;
grant select,insert,update,delete on all tables in schema public,goya_private to goya_operations;
grant usage,select on all sequences in schema public,goya_private to goya_operations;
create table goya_private.branches(id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 100),kind text not null check(kind in ('branch','event')),address text not null default '',starts_on date,ends_on date,archived_at timestamptz,revision integer not null default 1,created_at timestamptz not null default now(),check(ends_on is null or starts_on is null or ends_on>=starts_on));
insert into goya_private.branches(id,name,kind) values('00000000-0000-0000-0000-000000000001','GOYA','branch');
create table goya_private.branch_members(branch_id uuid not null references goya_private.branches(id),staff_id uuid not null references public.staff(id),assigned_on date not null default (now() at time zone 'Asia/Dubai')::date,primary key(branch_id,staff_id));
insert into goya_private.branch_members(branch_id,staff_id,assigned_on) select '00000000-0000-0000-0000-000000000001',id,'0001-01-01'::date from public.staff;
create table goya_private.branch_audit(id bigint generated always as identity primary key,branch_id uuid not null references goya_private.branches(id),before_data jsonb,after_data jsonb,created_at timestamptz not null default now());
alter table goya_private.branches enable row level security;
alter table goya_private.branch_members enable row level security;
alter table goya_private.branch_audit enable row level security;
grant select on goya_private.branches,goya_private.branch_members to goya_operations;
create policy branch_catalog_internal on goya_private.branches to goya_operations using(true);
create policy branch_members_internal on goya_private.branch_members to goya_operations using(true);
create function goya_private.current_branch() returns uuid language sql stable set search_path='' as $$select coalesce(nullif(current_setting('goya.branch_id',true),''),'00000000-0000-0000-0000-000000000001')::uuid$$;
create view goya_private.branch_staff with(security_invoker=true) as select s.* from public.staff s where exists(select 1 from goya_private.branch_members b where b.staff_id=s.id and b.branch_id=goya_private.current_branch());
grant select,update on goya_private.branch_staff to goya_operations;
create policy operations_internal on public.suppliers to goya_operations using(true) with check(true);
create policy operations_internal on public.master_items to goya_operations using(true) with check(true);
create policy operations_internal on public.internal_items to goya_operations using(true) with check(true);
create policy operations_internal on public.staff to goya_operations using(true) with check(true);
create policy operations_internal on public.wastage_reasons to goya_operations using(true) with check(true);
create policy operations_internal on public.app_sessions to goya_operations using(true) with check(true);
create policy operations_internal on public.admin_credentials to goya_operations using(true) with check(true);
create policy operations_internal on public.attendance_staff to goya_operations using(true) with check(true);
create policy operations_internal on public.attendance_documents to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.push_config to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.push_subscriptions to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.notice_push_jobs to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.notice_push_deliveries to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.staff_remembered_sessions to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.admin_remembered_sessions to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.admin_push_devices to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.admin_push_deliveries to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.staff_hr_profiles to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.staff_leave_requests to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.staff_leave_uploads to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.staff_leave_drive_folders to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.staff_leave_email_settings to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.staff_hr_audit to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.staff_document_versions to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.staff_annual_history to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.staff_off_balances to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.staff_management_decisions to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.staff_resignations to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.off_credit_batches to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.off_credit_members to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.off_balance_events to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.staff_notifications to goya_operations using(true) with check(true);
create policy operations_internal on goya_private.staff_appearance to goya_operations using(true) with check(true);
alter table public.order_groups add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.order_groups alter column branch_id set default goya_private.current_branch();
alter table public.order_groups enable row level security;
create policy branch_operations on public.order_groups to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.order_groups(branch_id);
alter table public.orders add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.orders alter column branch_id set default goya_private.current_branch();
alter table public.orders enable row level security;
create policy branch_operations on public.orders to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.orders(branch_id);
alter table public.production_batches add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.production_batches alter column branch_id set default goya_private.current_branch();
alter table public.production_batches enable row level security;
create policy branch_operations on public.production_batches to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.production_batches(branch_id);
alter table public.wastage_entries add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.wastage_entries alter column branch_id set default goya_private.current_branch();
alter table public.wastage_entries enable row level security;
create policy branch_operations on public.wastage_entries to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.wastage_entries(branch_id);
alter table public.inventory_sessions add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.inventory_sessions alter column branch_id set default goya_private.current_branch();
alter table public.inventory_sessions enable row level security;
create policy branch_operations on public.inventory_sessions to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.inventory_sessions(branch_id);
alter table public.inventory_counts add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.inventory_counts alter column branch_id set default goya_private.current_branch();
alter table public.inventory_counts enable row level security;
create policy branch_operations on public.inventory_counts to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.inventory_counts(branch_id);
alter table public.inventory_drafts add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.inventory_drafts alter column branch_id set default goya_private.current_branch();
alter table public.inventory_drafts enable row level security;
create policy branch_operations on public.inventory_drafts to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.inventory_drafts(branch_id);
alter table public.inventory_submissions add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.inventory_submissions alter column branch_id set default goya_private.current_branch();
alter table public.inventory_submissions enable row level security;
create policy branch_operations on public.inventory_submissions to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.inventory_submissions(branch_id);
alter table public.staff_drafts add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.staff_drafts alter column branch_id set default goya_private.current_branch();
alter table public.staff_drafts enable row level security;
create policy branch_operations on public.staff_drafts to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.staff_drafts(branch_id);
alter table public.complaint_feedback add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.complaint_feedback alter column branch_id set default goya_private.current_branch();
alter table public.complaint_feedback enable row level security;
create policy branch_operations on public.complaint_feedback to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.complaint_feedback(branch_id);
alter table public.info_pages add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.info_pages alter column branch_id set default goya_private.current_branch();
alter table public.info_pages enable row level security;
create policy branch_operations on public.info_pages to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.info_pages(branch_id);
alter table public.settings add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.settings alter column branch_id set default goya_private.current_branch();
alter table public.settings enable row level security;
create policy branch_operations on public.settings to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.settings(branch_id);
alter table public.attendance_records add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.attendance_records alter column branch_id set default goya_private.current_branch();
alter table public.attendance_records enable row level security;
create policy branch_operations on public.attendance_records to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.attendance_records(branch_id);
alter table public.attendance_uploads add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.attendance_uploads alter column branch_id set default goya_private.current_branch();
alter table public.attendance_uploads enable row level security;
create policy branch_operations on public.attendance_uploads to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.attendance_uploads(branch_id);
alter table public.attendance_settings add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.attendance_settings alter column branch_id set default goya_private.current_branch();
alter table public.attendance_settings enable row level security;
create policy branch_operations on public.attendance_settings to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.attendance_settings(branch_id);
alter table public.attendance_staff_submissions add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.attendance_staff_submissions alter column branch_id set default goya_private.current_branch();
alter table public.attendance_staff_submissions enable row level security;
create policy branch_operations on public.attendance_staff_submissions to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.attendance_staff_submissions(branch_id);
alter table public.attendance_monthly_finalizations add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.attendance_monthly_finalizations alter column branch_id set default goya_private.current_branch();
alter table public.attendance_monthly_finalizations enable row level security;
create policy branch_operations on public.attendance_monthly_finalizations to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.attendance_monthly_finalizations(branch_id);
alter table public.attendance_device_records add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.attendance_device_records alter column branch_id set default goya_private.current_branch();
alter table public.attendance_device_records enable row level security;
create policy branch_operations on public.attendance_device_records to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.attendance_device_records(branch_id);
alter table public.attendance_finalized_reports add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.attendance_finalized_reports alter column branch_id set default goya_private.current_branch();
alter table public.attendance_finalized_reports enable row level security;
create policy branch_operations on public.attendance_finalized_reports to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.attendance_finalized_reports(branch_id);
alter table public.attendance_live_days add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.attendance_live_days alter column branch_id set default goya_private.current_branch();
alter table public.attendance_live_days enable row level security;
create policy branch_operations on public.attendance_live_days to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.attendance_live_days(branch_id);
alter table public.attendance_live_sessions add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.attendance_live_sessions alter column branch_id set default goya_private.current_branch();
alter table public.attendance_live_sessions enable row level security;
create policy branch_operations on public.attendance_live_sessions to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.attendance_live_sessions(branch_id);
alter table public.attendance_live_audit add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table public.attendance_live_audit alter column branch_id set default goya_private.current_branch();
alter table public.attendance_live_audit enable row level security;
create policy branch_operations on public.attendance_live_audit to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on public.attendance_live_audit(branch_id);
alter table goya_private.notices add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table goya_private.notices alter column branch_id set default goya_private.current_branch();
alter table goya_private.notices enable row level security;
create policy branch_operations on goya_private.notices to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on goya_private.notices(branch_id);
alter table goya_private.inventory_shared_sheets add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table goya_private.inventory_shared_sheets alter column branch_id set default goya_private.current_branch();
alter table goya_private.inventory_shared_sheets enable row level security;
create policy branch_operations on goya_private.inventory_shared_sheets to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on goya_private.inventory_shared_sheets(branch_id);
alter table goya_private.inventory_shared_lines add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table goya_private.inventory_shared_lines alter column branch_id set default goya_private.current_branch();
alter table goya_private.inventory_shared_lines enable row level security;
create policy branch_operations on goya_private.inventory_shared_lines to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on goya_private.inventory_shared_lines(branch_id);
alter table goya_private.inventory_shared_audit add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table goya_private.inventory_shared_audit alter column branch_id set default goya_private.current_branch();
alter table goya_private.inventory_shared_audit enable row level security;
create policy branch_operations on goya_private.inventory_shared_audit to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on goya_private.inventory_shared_audit(branch_id);
alter table goya_private.inventory_shared_finals add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table goya_private.inventory_shared_finals alter column branch_id set default goya_private.current_branch();
alter table goya_private.inventory_shared_finals enable row level security;
create policy branch_operations on goya_private.inventory_shared_finals to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on goya_private.inventory_shared_finals(branch_id);
alter table goya_private.equipment_reports add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table goya_private.equipment_reports alter column branch_id set default goya_private.current_branch();
alter table goya_private.equipment_reports enable row level security;
create policy branch_operations on goya_private.equipment_reports to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on goya_private.equipment_reports(branch_id);
alter table goya_private.equipment_status_history add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table goya_private.equipment_status_history alter column branch_id set default goya_private.current_branch();
alter table goya_private.equipment_status_history enable row level security;
create policy branch_operations on goya_private.equipment_status_history to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on goya_private.equipment_status_history(branch_id);
alter table goya_private.admin_notifications add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table goya_private.admin_notifications alter column branch_id set default goya_private.current_branch();
alter table goya_private.admin_notifications enable row level security;
create policy branch_operations on goya_private.admin_notifications to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on goya_private.admin_notifications(branch_id);
alter table goya_private.pw_quantity_audit add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table goya_private.pw_quantity_audit alter column branch_id set default goya_private.current_branch();
alter table goya_private.pw_quantity_audit enable row level security;
create policy branch_operations on goya_private.pw_quantity_audit to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on goya_private.pw_quantity_audit(branch_id);
alter table goya_private.pnl_reports add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table goya_private.pnl_reports alter column branch_id set default goya_private.current_branch();
alter table goya_private.pnl_reports enable row level security;
create policy branch_operations on goya_private.pnl_reports to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on goya_private.pnl_reports(branch_id);
alter table goya_private.roster_weeks add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table goya_private.roster_weeks alter column branch_id set default goya_private.current_branch();
alter table goya_private.roster_weeks enable row level security;
create policy branch_operations on goya_private.roster_weeks to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on goya_private.roster_weeks(branch_id);
alter table goya_private.roster_publications add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table goya_private.roster_publications alter column branch_id set default goya_private.current_branch();
alter table goya_private.roster_publications enable row level security;
create policy branch_operations on goya_private.roster_publications to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on goya_private.roster_publications(branch_id);
alter table goya_private.roster_push_deliveries add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table goya_private.roster_push_deliveries alter column branch_id set default goya_private.current_branch();
alter table goya_private.roster_push_deliveries enable row level security;
create policy branch_operations on goya_private.roster_push_deliveries to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on goya_private.roster_push_deliveries(branch_id);
alter table goya_private.roster_excel_archive add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table goya_private.roster_excel_archive alter column branch_id set default goya_private.current_branch();
alter table goya_private.roster_excel_archive enable row level security;
create policy branch_operations on goya_private.roster_excel_archive to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on goya_private.roster_excel_archive(branch_id);
alter table goya_private.roster_off_charges add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table goya_private.roster_off_charges alter column branch_id set default goya_private.current_branch();
alter table goya_private.roster_off_charges enable row level security;
create policy branch_operations on goya_private.roster_off_charges to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on goya_private.roster_off_charges(branch_id);
alter table goya_private.push_deliveries add column branch_id uuid not null default '00000000-0000-0000-0000-000000000001' references goya_private.branches(id);
alter table goya_private.push_deliveries alter column branch_id set default goya_private.current_branch();
alter table goya_private.push_deliveries enable row level security;
create policy branch_operations on goya_private.push_deliveries to goya_operations using(branch_id=goya_private.current_branch()) with check(branch_id=goya_private.current_branch());
create index on goya_private.push_deliveries(branch_id);
alter table goya_private.roster_publications drop constraint roster_publications_week_start_fkey;
alter table goya_private.roster_push_deliveries drop constraint roster_push_deliveries_week_start_revision_fkey;
alter table goya_private.pnl_reports drop constraint pnl_reports_pkey;
alter table goya_private.pnl_reports add constraint pnl_reports_pkey PRIMARY KEY (branch_id, start_date, end_date);
alter table goya_private.push_deliveries drop constraint push_deliveries_pkey;
alter table goya_private.push_deliveries add constraint push_deliveries_pkey PRIMARY KEY (branch_id, subscription_id, operational_date);
alter table goya_private.roster_excel_archive drop constraint roster_excel_archive_pkey;
alter table goya_private.roster_excel_archive add constraint roster_excel_archive_pkey PRIMARY KEY (branch_id, source_week, source_row);
alter table goya_private.roster_off_charges drop constraint roster_off_charges_pkey;
alter table goya_private.roster_off_charges add constraint roster_off_charges_pkey PRIMARY KEY (branch_id, staff_id, off_date);
alter table goya_private.roster_publications drop constraint roster_publications_pkey;
alter table goya_private.roster_publications add constraint roster_publications_pkey PRIMARY KEY (branch_id, week_start, revision);
alter table goya_private.roster_push_deliveries drop constraint roster_push_deliveries_pkey;
alter table goya_private.roster_push_deliveries add constraint roster_push_deliveries_pkey PRIMARY KEY (branch_id, week_start, revision, subscription_id);
alter table goya_private.roster_weeks drop constraint roster_weeks_pkey;
alter table goya_private.roster_weeks add constraint roster_weeks_pkey PRIMARY KEY (branch_id, week_start);
alter table public.attendance_device_records drop constraint attendance_device_records_pkey;
alter table public.attendance_device_records add constraint attendance_device_records_pkey PRIMARY KEY (branch_id, id);
alter table public.attendance_device_records drop constraint attendance_device_records_attendance_staff_id_operational_d_key;
alter table public.attendance_device_records add constraint attendance_device_records_attendance_staff_id_operational_d_key UNIQUE (branch_id, attendance_staff_id, operational_date);
alter table public.attendance_live_days drop constraint attendance_live_days_pkey;
alter table public.attendance_live_days add constraint attendance_live_days_pkey PRIMARY KEY (branch_id, id);
alter table public.attendance_live_days drop constraint attendance_live_days_staff_id_operational_date_key;
alter table public.attendance_live_days add constraint attendance_live_days_staff_id_operational_date_key UNIQUE (branch_id, staff_id, operational_date);
alter table public.attendance_live_sessions drop constraint attendance_live_sessions_staff_id_operational_date_session__key;
alter table public.attendance_live_sessions add constraint attendance_live_sessions_staff_id_operational_date_session__key UNIQUE (branch_id, staff_id, operational_date, session_no);
alter table public.attendance_monthly_finalizations drop constraint attendance_monthly_finalizations_month_start_key;
alter table public.attendance_monthly_finalizations add constraint attendance_monthly_finalizations_month_start_key UNIQUE (branch_id, month_start);
alter table public.attendance_monthly_finalizations drop constraint attendance_monthly_finalizations_pkey;
alter table public.attendance_monthly_finalizations add constraint attendance_monthly_finalizations_pkey PRIMARY KEY (branch_id, id);
alter table public.attendance_records drop constraint attendance_records_attendance_staff_id_operational_date_key;
alter table public.attendance_records add constraint attendance_records_attendance_staff_id_operational_date_key UNIQUE (branch_id, attendance_staff_id, operational_date);
alter table public.attendance_records drop constraint attendance_records_pkey;
alter table public.attendance_records add constraint attendance_records_pkey PRIMARY KEY (branch_id, id);
alter table public.attendance_settings drop constraint attendance_settings_pkey;
alter table public.attendance_settings add constraint attendance_settings_pkey PRIMARY KEY (branch_id, key);
alter table public.settings drop constraint settings_pkey;
alter table public.settings add constraint settings_pkey PRIMARY KEY (branch_id, key);
alter table public.staff_drafts drop constraint staff_drafts_pkey;
alter table public.staff_drafts add constraint staff_drafts_pkey PRIMARY KEY (branch_id, staff_id, draft_type);
alter table goya_private.roster_publications add constraint roster_publications_week_start_fkey FOREIGN KEY (branch_id, week_start) REFERENCES goya_private.roster_weeks(branch_id, week_start);
alter table goya_private.roster_push_deliveries add constraint roster_push_deliveries_week_start_revision_fkey FOREIGN KEY (branch_id, week_start, revision) REFERENCES goya_private.roster_publications(branch_id, week_start, revision);
alter table public.order_groups add column branch_snapshot jsonb;
create function goya_private.capture_order_branch() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='INSERT' then select jsonb_build_object('id',id,'name',name,'kind',kind,'address',address) into new.branch_snapshot from goya_private.branches where id=new.branch_id;
 elsif new.branch_id is distinct from old.branch_id or new.branch_snapshot is distinct from old.branch_snapshot then raise exception 'Order delivery identity cannot be changed';end if;return new;end$$;
create trigger capture_order_branch before insert or update on public.order_groups for each row execute function goya_private.capture_order_branch();
create view goya_private.branch_staff_history with(security_invoker=true) as select s.* from public.staff s where exists(select 1 from goya_private.branch_members b where b.staff_id=s.id and b.branch_id=goya_private.current_branch()) or exists(select 1 from public.attendance_live_days d where d.staff_id=s.id) or exists(select 1 from public.attendance_records r join public.attendance_staff a on a.id=r.attendance_staff_id where a.portal_staff_id=s.id) or exists(select 1 from goya_private.roster_publications p where p.schedule->'staff' ? s.id::text);
grant select on goya_private.branch_staff_history to goya_operations;
create function goya_private.branch_employee_on(employee uuid,day date) returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from goya_private.branch_members m join goya_private.branches b on b.id=m.branch_id where m.branch_id=goya_private.current_branch() and m.staff_id=employee and m.assigned_on<=day and (b.id='00000000-0000-0000-0000-000000000001' or day>=coalesce(b.starts_on,(b.created_at at time zone 'Asia/Dubai')::date))) or exists(select 1 from public.attendance_live_days d where d.staff_id=employee and d.operational_date=day) or exists(select 1 from public.attendance_records r join public.attendance_staff a on a.id=r.attendance_staff_id where a.portal_staff_id=employee and r.operational_date=day) or exists(select 1 from goya_private.roster_publications p join goya_private.roster_weeks w on (w.branch_id,w.week_start,w.published_revision)=(p.branch_id,p.week_start,p.revision) where day between p.week_start and p.week_start+6 and p.schedule->'staff' ? employee::text and p.schedule->'staff'->employee::text->(day-p.week_start)<>'null'::jsonb)$$;
alter function goya_private.branch_employee_on(uuid,date) owner to goya_operations;revoke all on function goya_private.branch_employee_on(uuid,date) from public;grant execute on function goya_private.branch_employee_on(uuid,date) to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_push_check(p_id uuid, p_date date)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select exists(select 1 from goya_private.due_reminders() where subscription_id=p_id and operational_date=p_date) $function$
;
alter function public.goya_push_check(p_id uuid, p_date date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_push_claim()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; outv jsonb:='[]';
begin
 for r in select * from goya_private.due_reminders() limit 100 loop
 insert into goya_private.push_deliveries(subscription_id,operational_date,claimed_at,attempts)
 values(r.subscription_id,r.operational_date,now(),1)
 on conflict(branch_id,subscription_id,operational_date) do update set claimed_at=now(),attempts=goya_private.push_deliveries.attempts+1
 where goya_private.push_deliveries.sent_at is null and goya_private.push_deliveries.attempts<3 and goya_private.push_deliveries.claimed_at<now()-interval '3 minutes';
 if found then outv:=outv||jsonb_build_array(to_jsonb(r));end if;
 end loop;
 return outv;
end $function$
;
alter function public.goya_push_claim() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_push_result(p_id uuid, p_date date, p_ok boolean, p_expired boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 update goya_private.push_deliveries set sent_at=case when p_ok then now() else sent_at end,error=case when p_ok then null else 'Push delivery failed' end where subscription_id=p_id and operational_date=p_date;
 if p_expired then update goya_private.push_subscriptions set active=false where id=p_id;end if;
end $function$
;
alter function public.goya_push_result(p_id uuid, p_date date, p_ok boolean, p_expired boolean) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.force_break_policy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if coalesce((public.attendance_live_rules()->>'force_no_break')::boolean,false) and new.operational_date>=public.attendance_live_operational_date(now()) then new.break_taken:=false;end if;return new;
end $function$
;
alter function goya_private.force_break_policy() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_staff_push_state(p_token text, p_endpoint text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare sess public.app_sessions;
begin
 sess:=public.require_session(p_token,false);
 -- The caller possesses this browser's endpoint. Stop reminders for a previous user on this same device.
 update goya_private.push_subscriptions set active=false,updated_at=now() where endpoint=p_endpoint and staff_id<>sess.staff_id and active;
 return jsonb_build_object('enabled',exists(select 1 from goya_private.push_subscriptions where staff_id=sess.staff_id and endpoint=p_endpoint and active));
end $function$
;
alter function public.goya_staff_push_state(p_token text, p_endpoint text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_replace_internal_items(p_token text, p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it jsonb;n int:=0;
begin
  perform public.require_session(p_token,true);
  delete from public.internal_items where id is not null;
  for it in select * from jsonb_array_elements(p_rows)
  loop
    insert into public.internal_items(name,sku,storage_unit,ingredient_unit,items_type,active)
    values(trim(it->>'name'),trim(it->>'sku'),trim(it->>'storage_unit'),trim(it->>'ingredient_unit'),trim(it->>'items_type'),true);
    n:=n+1;
  end loop;
  return n;
end;
$function$
;
alter function public.admin_replace_internal_items(p_token text, p_rows jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_history(p_token text, p_month date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  start_d date;
  end_d date;
begin
  -- A valid staff session is still required, but records are no longer
  -- filtered by the logged-in staff member.
  sess := public.require_session(p_token,false);
  start_d := date_trunc('month',p_month)::date;
  end_d := (start_d + interval '1 month')::date;

  return jsonb_build_object(
    'orders',(
      select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb)
      from (
        select o.id,g.order_no,o.name,o.sku,o.quantity,o.unit,o.supplier,
               o.status,o.received_date,o.logged_by,o.notes,o.created_at
        from public.orders o
        join public.order_groups g on g.id=o.order_group_id
        where o.created_at>=start_d and o.created_at<end_d
      ) q
    ),
    'production',(
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
      from public.production_batches x
      where x.created_at>=start_d and x.created_at<end_d
    ),
    'wastage',(
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
      from public.wastage_entries x
      where x.created_at>=start_d and x.created_at<end_d
    ),
    'inventory',(
      select coalesce(jsonb_agg(to_jsonb(x) order by x.counted_at desc),'[]'::jsonb)
      from public.inventory_counts x
      where x.counted_at>=start_d and x.counted_at<end_d
    )
  );
end;
$function$
;
alter function public.staff_history(p_token text, p_month date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_draft_get(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
begin
  sess := public.require_session(p_token,false);
  return jsonb_build_object(
    'order',coalesce((select items from public.staff_drafts where staff_id=sess.staff_id and draft_type='order'),'[]'::jsonb),
    'production',coalesce((select items from public.staff_drafts where staff_id=sess.staff_id and draft_type='production'),'[]'::jsonb),
    'wastage',coalesce((select items from public.staff_drafts where staff_id=sess.staff_id and draft_type='wastage'),'[]'::jsonb)
  );
end;
$function$
;
alter function public.staff_draft_get(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_draft_save(p_token text, p_kind text, p_items jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  k text := lower(trim(p_kind));
begin
  sess := public.require_session(p_token,false);
  if k not in ('order','production','wastage') then
    raise exception 'Invalid draft type';
  end if;
  if jsonb_typeof(coalesce(p_items,'[]'::jsonb)) <> 'array' then
    raise exception 'Invalid draft payload';
  end if;
  insert into public.staff_drafts(staff_id,draft_type,items,updated_at)
  values(sess.staff_id,k,coalesce(p_items,'[]'::jsonb),now())
  on conflict(branch_id,staff_id,draft_type)
  do update set items=excluded.items,updated_at=now();
  return true;
end;
$function$
;
alter function public.staff_draft_save(p_token text, p_kind text, p_items jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_draft_clear(p_token text, p_kind text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  k text := lower(trim(p_kind));
begin
  sess := public.require_session(p_token,false);
  if k not in ('order','production','wastage') then
    raise exception 'Invalid draft type';
  end if;
  delete from public.staff_drafts
  where staff_id=sess.staff_id and draft_type=k;
  return true;
end;
$function$
;
alter function public.staff_draft_clear(p_token text, p_kind text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_upsert_master_items(p_token text, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  it jsonb;
  ins integer:=0;
  upd integer:=0;
  v_sku text;
begin
  perform public.require_session(p_token,true);
  if jsonb_typeof(p_rows)<>'array' then raise exception 'Invalid import payload'; end if;

  for it in select * from jsonb_array_elements(p_rows)
  loop
    v_sku := trim(it->>'sku');
    if nullif(v_sku,'') is null or nullif(trim(it->>'name'),'') is null then
      continue;
    end if;

    if exists(select 1 from public.master_items where sku=v_sku) then
      update public.master_items
      set name=trim(it->>'name'),
          storage_unit=trim(it->>'storage_unit'),
          ingredient_unit=trim(it->>'ingredient_unit'),
          supplier=nullif(trim(it->>'supplier'),''),
          items_type=trim(it->>'items_type'),
          active=true,
          updated_at=now()
      where sku=v_sku;
      upd:=upd+1;
    else
      insert into public.master_items(name,sku,storage_unit,ingredient_unit,supplier,items_type,active)
      values(trim(it->>'name'),v_sku,trim(it->>'storage_unit'),trim(it->>'ingredient_unit'),
             nullif(trim(it->>'supplier'),''),trim(it->>'items_type'),true);
      ins:=ins+1;
    end if;
  end loop;

  return jsonb_build_object('inserted',ins,'updated',upd);
end;
$function$
;
alter function public.admin_upsert_master_items(p_token text, p_rows jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_upsert_internal_items(p_token text, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  it jsonb;
  ins integer:=0;
  upd integer:=0;
  v_sku text;
begin
  perform public.require_session(p_token,true);
  if jsonb_typeof(p_rows)<>'array' then raise exception 'Invalid import payload'; end if;

  for it in select * from jsonb_array_elements(p_rows)
  loop
    v_sku := trim(it->>'sku');
    if nullif(v_sku,'') is null or nullif(trim(it->>'name'),'') is null then
      continue;
    end if;

    if exists(select 1 from public.internal_items where sku=v_sku) then
      update public.internal_items
      set name=trim(it->>'name'),
          storage_unit=trim(it->>'storage_unit'),
          ingredient_unit=trim(it->>'ingredient_unit'),
          items_type=trim(it->>'items_type'),
          active=true,
          updated_at=now()
      where sku=v_sku;
      upd:=upd+1;
    else
      insert into public.internal_items(name,sku,storage_unit,ingredient_unit,items_type,active)
      values(trim(it->>'name'),v_sku,trim(it->>'storage_unit'),trim(it->>'ingredient_unit'),
             trim(it->>'items_type'),true);
      ins:=ins+1;
    end if;
  end loop;

  return jsonb_build_object('inserted',ins,'updated',upd);
end;
$function$
;
alter function public.admin_upsert_internal_items(p_token text, p_rows jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_replace_master_items(p_token text, p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it jsonb;n int:=0;
begin
  perform public.require_session(p_token,true);
  delete from public.master_items where id is not null;
  for it in select * from jsonb_array_elements(p_rows)
  loop
    insert into public.master_items(name,sku,storage_unit,ingredient_unit,supplier,items_type,active)
    values(trim(it->>'name'),trim(it->>'sku'),trim(it->>'storage_unit'),trim(it->>'ingredient_unit'),
           nullif(trim(it->>'supplier'),''),trim(it->>'items_type'),true);
    n:=n+1;
  end loop;
  return n;
end;
$function$
;
alter function public.admin_replace_master_items(p_token text, p_rows jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_admin_profiles(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.require_session(p_token,true);
  return coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'active',s.active,'profile',to_jsonb(p),
    'history',(select jsonb_agg(jsonb_build_object('event',a.event,'created_at',a.created_at,'details',a.details)
      order by a.id desc) from goya_private.staff_hr_audit a where a.staff_id=s.id and a.event in ('Resignation','Rejoined')))
    order by s.active desc,s.name) from public.staff s
    left join goya_private.staff_hr_profiles p on p.staff_id=s.id),'[]'::jsonb);
end $function$
;
alter function public.goya_hr_admin_profiles(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.run_duty_reminders()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare token text; request_id bigint;
begin
 if not exists(select 1 from goya_private.push_subscriptions where active) and not exists(select 1 from goya_private.notice_push_jobs j join goya_private.notices n on n.id=j.notice_id where j.started_at is null and j.cancelled_at is null and n.active and n.important and n.published_at<=now() and (n.expires_at is null or n.expires_at>now())) then return null;end if;
 select worker_token into token from goya_private.push_config where id;
 select net.http_post(url:='https://yudrsojnfucvdigehkku.supabase.co/functions/v1/duty-reminders',headers:=jsonb_build_object('Content-Type','application/json','x-goya-worker',token),body:='{}'::jsonb,timeout_milliseconds:=15000) into request_id;
 return request_id;
end $function$
;
alter function goya_private.run_duty_reminders() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_save_profile(p_token text, p_staff uuid, p_profile jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare previous goya_private.staff_hr_profiles; cessation date := nullif(p_profile->>'last_day','')::date;
begin
  perform public.require_session(p_token,true);
  perform 1 from public.staff where id=p_staff for update;
  if not found then raise exception 'Staff member was not found'; end if;
  select * into previous from goya_private.staff_hr_profiles where staff_id=p_staff;
  if cessation > (now() at time zone 'Asia/Dubai')::date then
    raise exception 'Record resignation on or after the last working day';
  end if;
  if previous.last_day is not null and cessation is null then
    raise exception 'Use the rejoin action to remove resigned status';
  end if;
  insert into goya_private.staff_hr_profiles(staff_id,joining_date,employee_code,position,branch,manager_notes,last_day)
  values(p_staff,nullif(p_profile->>'joining_date','')::date,left(coalesce(p_profile->>'employee_code',''),80),
    left(coalesce(p_profile->>'position',''),120),left(coalesce(p_profile->>'branch',''),120),
    left(coalesce(p_profile->>'manager_notes',''),4000),cessation)
  on conflict(staff_id) do update set joining_date=excluded.joining_date,employee_code=excluded.employee_code,
    position=excluded.position,branch=excluded.branch,manager_notes=excluded.manager_notes,last_day=excluded.last_day,updated_at=now();
  if cessation is not null then
    update public.staff set active=false where id=p_staff and active;
    update public.app_sessions set expires_at=now() where staff_id=p_staff and not is_admin and expires_at>now();
  end if;
  insert into goya_private.staff_hr_audit(staff_id,event,details)
  values(p_staff,case when previous.last_day is distinct from cessation and cessation is not null then 'Resignation' else 'Profile saved' end,
    jsonb_build_object('prior_joining_date',previous.joining_date,'prior_last_day',previous.last_day,'last_day',cessation));
end $function$
;
alter function public.goya_hr_save_profile(p_token text, p_staff uuid, p_profile jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_rejoin(p_token text, p_staff uuid, p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cessation date;
begin
  perform public.require_session(p_token,true);
  perform 1 from public.staff where id=p_staff for update;
  select last_day into cessation from goya_private.staff_hr_profiles where staff_id=p_staff;
  if cessation is null or p_date is null or p_date<=cessation or p_date>(now() at time zone 'Asia/Dubai')::date then
    raise exception 'Enter a rejoin date after the last working day and on or before today';
  end if;
  update goya_private.staff_hr_profiles set last_day=null,updated_at=now() where staff_id=p_staff;
  update public.staff set active=true where id=p_staff;
  insert into goya_private.staff_hr_audit(staff_id,event,details)
    values(p_staff,'Rejoined',jsonb_build_object('last_day',cessation,'rejoined_on',p_date));
end $function$
;
alter function public.goya_hr_rejoin(p_token text, p_staff uuid, p_date date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_staff_push(p_token text, p_subscription jsonb, p_enabled boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare sess public.app_sessions; ep text:=p_subscription->>'endpoint';
begin
 sess:=public.require_session(p_token,false);
 if ep is null or ep !~ '^https://(fcm[.]googleapis[.]com|updates[.]push[.]services[.]mozilla[.]com|web[.]push[.]apple[.]com|[a-z0-9-]+[.]notify[.]windows[.]com)/' then raise exception 'Unsupported push provider'; end if;
 if p_enabled and (coalesce(length(p_subscription#>>'{keys,p256dh}'),0)<20 or coalesce(length(p_subscription#>>'{keys,auth}'),0)<10) then raise exception 'Invalid push subscription'; end if;
 if p_enabled then
 insert into goya_private.push_subscriptions(staff_id,endpoint,subscription,active) values(sess.staff_id,ep,p_subscription,true)
 on conflict(endpoint) do update set staff_id=excluded.staff_id,subscription=excluded.subscription,active=true,updated_at=now();
 else update goya_private.push_subscriptions set active=false,updated_at=now() where endpoint=ep and staff_id=sess.staff_id;
 end if;
 return jsonb_build_object('ok',true);
end $function$
;
alter function public.goya_staff_push(p_token text, p_subscription jsonb, p_enabled boolean) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_staff_identity(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := (public.require_session(p_token,false)).staff_id;
begin
  return (select jsonb_build_object('id',id,'name',name) from public.staff where id=employee and active);
end $function$
;
alter function public.goya_hr_staff_identity(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_archive_import(p_token text, p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare inserted integer;
begin
  perform public.require_session(p_token,true);
  if jsonb_typeof(p_rows) is distinct from 'array' or octet_length(p_rows::text)>800000 then
    raise exception 'Invalid archive data';
  end if;
  insert into goya_private.roster_excel_archive(source_week,source_row,source_name,staff_id,shifts,pending_off,private_remarks)
  select source_week,source_row,source_name,staff_id,shifts,coalesce(pending_off,''),coalesce(private_remarks,'')
    from jsonb_to_recordset(p_rows) as r(source_week date,source_row integer,source_name text,
      staff_id uuid,shifts jsonb,pending_off text,private_remarks text)
  on conflict(branch_id,source_week,source_row) do update set staff_id=excluded.staff_id
  where roster_excel_archive.staff_id is null and excluded.staff_id is not null
    and roster_excel_archive.source_name=excluded.source_name and roster_excel_archive.shifts=excluded.shifts;
  get diagnostics inserted = row_count;
  return inserted;
end $function$
;
alter function public.goya_hr_archive_import(p_token text, p_rows jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_archive_read(p_token text, p_admin boolean, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare sess public.app_sessions := public.require_session(p_token,p_admin);
begin
  if not p_admin and not exists(select 1 from public.staff where id=sess.staff_id and active) then
    raise exception 'Unauthorized';
  end if;
  return coalesce((select jsonb_agg(case when p_admin then to_jsonb(a) else
    jsonb_build_object('source_week',a.source_week,'shifts',a.shifts,'pending_off',a.pending_off) end
    order by a.source_week desc,a.source_row)
    from goya_private.roster_excel_archive a
    where (p_admin or a.staff_id=sess.staff_id) and a.source_week+6>=p_month and a.source_week<p_month+interval '1 month'),'[]'::jsonb);
end $function$
;
alter function public.goya_hr_archive_read(p_token text, p_admin boolean, p_month date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_admin_email_settings(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.require_session(p_token,true);
  return goya_private.staff_leave_email_recipients();
end $function$
;
alter function public.goya_hr_admin_email_settings(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_notice_push_claim()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare j record; r record; outv jsonb:='[]';
begin
 -- Snapshot recipients exactly once at publication; future opt-ins do not receive old broadcasts.
 for j in select q.notice_id from goya_private.notice_push_jobs q join goya_private.notices n on n.id=q.notice_id
 where q.started_at is null and q.cancelled_at is null and n.active and n.important and n.published_at<=now() and (n.expires_at is null or n.expires_at>now())
 order by q.requested_at for update of q skip locked limit 20 loop
  insert into goya_private.notice_push_deliveries(notice_id,subscription_id,staff_id)
  select j.notice_id,p.id,p.staff_id from goya_private.push_subscriptions p join goya_private.branch_staff s on s.id=p.staff_id and s.active where p.active
  on conflict do nothing;
  update goya_private.notice_push_jobs set started_at=now() where notice_id=j.notice_id;
 end loop;
 for r in select d.notice_id,d.subscription_id,p.subscription,n.title,n.body from goya_private.notice_push_deliveries d
 join goya_private.notices n on n.id=d.notice_id join goya_private.notice_push_jobs q on q.notice_id=d.notice_id and q.cancelled_at is null
 join goya_private.push_subscriptions p on p.id=d.subscription_id and p.staff_id=d.staff_id and p.active
 join goya_private.branch_staff s on s.id=d.staff_id and s.active
 where d.sent_at is null and d.attempts<3 and (d.claimed_at is null or d.claimed_at<now()-interval '3 minutes')
 and n.active and n.important and n.published_at<=now() and (n.expires_at is null or n.expires_at>now())
 order by q.requested_at for update of d skip locked limit 50 loop
  update goya_private.notice_push_deliveries set claimed_at=now(),attempts=attempts+1 where notice_id=r.notice_id and subscription_id=r.subscription_id;
  outv:=outv||jsonb_build_array(to_jsonb(r));
 end loop;
 return outv;
end $function$
;
alter function public.goya_notice_push_claim() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_notice_push_check(p_notice uuid, p_subscription uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from goya_private.notice_push_deliveries d join goya_private.notices n on n.id=d.notice_id
 join goya_private.notice_push_jobs q on q.notice_id=n.id and q.cancelled_at is null
 join goya_private.push_subscriptions p on p.id=d.subscription_id and p.staff_id=d.staff_id and p.active
 join goya_private.branch_staff s on s.id=d.staff_id and s.active
 where d.notice_id=p_notice and d.subscription_id=p_subscription and d.sent_at is null and n.active and n.important and n.published_at<=now() and (n.expires_at is null or n.expires_at>now()))
$function$
;
alter function public.goya_notice_push_check(p_notice uuid, p_subscription uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_notice_push_result(p_notice uuid, p_subscription uuid, p_ok boolean, p_expired boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 update goya_private.notice_push_deliveries set sent_at=case when p_ok then now() else sent_at end,error=case when p_ok then null else 'Push delivery failed' end,
 attempts=case when p_expired then 3 else attempts end where notice_id=p_notice and subscription_id=p_subscription;
 if p_expired then update goya_private.push_subscriptions set active=false,updated_at=now() where id=p_subscription;end if;
end $function$
;
alter function public.goya_notice_push_result(p_notice uuid, p_subscription uuid, p_ok boolean, p_expired boolean) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_save_email_settings(p_token text, p_owner text, p_hr text, p_expected integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  owner_address text := nullif(btrim(p_owner),'');
  hr_address text := nullif(btrim(p_hr),'');
  address text;
begin
  perform public.require_session(p_token,true);
  foreach address in array array[owner_address,hr_address] loop
    if address is not null and (length(address)>254 or address !~ '^[^[:space:]@<>,;]+@[^[:space:]@<>,;.]+([.][^[:space:]@<>,;.]+)+$') then
      raise exception 'Enter a valid email address for Owner and HR.';
    end if;
  end loop;
  if p_expected=0 then
    insert into goya_private.staff_leave_email_settings(owner_email,hr_email) values(owner_address,hr_address)
      on conflict(id) do nothing;
  else
    update goya_private.staff_leave_email_settings
      set owner_email=owner_address,hr_email=hr_address,revision=revision+1
      where id and revision=p_expected;
  end if;
  if not found then raise exception 'Email settings changed. Reload the settings before saving again.'; end if;
  return goya_private.staff_leave_email_recipients();
end $function$
;
alter function public.goya_hr_save_email_settings(p_token text, p_owner text, p_hr text, p_expected integer) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_record_request(p_staff uuid, p_id uuid, p_kind text, p_from date, p_to date, p_reason text, p_drive text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result goya_private.staff_leave_requests;
begin
  perform 1 from public.staff where id=p_staff and active for share;
  if not found then raise exception 'Unauthorized'; end if;
  insert into goya_private.staff_leave_requests(id,staff_id,kind,requested_from,requested_to,reason,drive_file_id)
  values(p_id,p_staff,p_kind,p_from,p_to,p_reason,p_drive) on conflict(id) do nothing;
  select * into result from goya_private.staff_leave_requests where id=p_id and staff_id=p_staff;
  if not found then raise exception 'Request ID is unavailable'; end if;
  return to_jsonb(result);
end $function$
;
alter function public.goya_hr_record_request(p_staff uuid, p_id uuid, p_kind text, p_from date, p_to date, p_reason text, p_drive text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_email_state(p_id uuid, p_state text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  update goya_private.staff_leave_requests set email_state=p_state
  where id=p_id and email_state not in ('Sent','Imported');
$function$
;
alter function public.goya_hr_email_state(p_id uuid, p_state text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_orders_page(p_token text, p_admin boolean DEFAULT false, p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 select o.id,o.created_at,case when p_admin then to_jsonb(o)||jsonb_build_object('order_no',g.order_no,'branch_snapshot',g.branch_snapshot,'submitted_at',g.submitted_at,'group_notes',g.notes)
 else jsonb_build_object('id',o.id,'order_no',g.order_no,'branch_snapshot',g.branch_snapshot,'name',o.name,'sku',o.sku,'quantity',o.quantity,'unit',o.unit,'supplier',o.supplier,'status',o.status,'received_date',o.received_date,'logged_by',o.logged_by,'notes',o.notes,'created_at',o.created_at) end rowv
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
end $function$
;
alter function public.goya_orders_page(p_token text, p_admin boolean, p_filters jsonb, p_page integer) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_upload_slot(p_staff uuid, p_id uuid, p_drive text, p_fingerprint text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare slot goya_private.staff_leave_uploads;
begin
  insert into goya_private.staff_leave_uploads(request_id,staff_id,drive_file_id,fingerprint)
    values(p_id,p_staff,p_drive,p_fingerprint) on conflict(request_id) do nothing;
  select * into slot from goya_private.staff_leave_uploads where request_id=p_id;
  if slot.staff_id<>p_staff or slot.fingerprint<>p_fingerprint then raise exception 'Attachment changed. Start a new request.'; end if;
  return slot.drive_file_id;
end $function$
;
alter function public.goya_hr_upload_slot(p_staff uuid, p_id uuid, p_drive text, p_fingerprint text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_drive_folder_slot(p_parent text, p_name text, p_candidate text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if p_candidate is not null then
    insert into goya_private.staff_leave_drive_folders(parent_id,folder_name,drive_id)
    values(p_parent,p_name,p_candidate) on conflict(parent_id,folder_name) do nothing;
  end if;
  return (select drive_id from goya_private.staff_leave_drive_folders where parent_id=p_parent and folder_name=p_name);
end $function$
;
alter function public.goya_hr_drive_folder_slot(p_parent text, p_name text, p_candidate text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_worker_email_settings()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select goya_private.staff_leave_email_recipients() || jsonb_build_object(
    'manager_email',(select nullif(btrim(value->>'email'),'') from public.settings where key='admin')
  );
$function$
;
alter function public.goya_hr_worker_email_settings() owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.off_snapshot(employee uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb; archived record;
begin
 select to_jsonb(b) into result from goya_private.staff_off_balances b where staff_id=employee;
 if result is not null then return result; end if;
 select pending_off,source_week into archived from goya_private.roster_excel_archive
 where staff_id=employee and pending_off ~ '^[-+]?[0-9]{1,5}$' order by source_week desc,source_row desc limit 1;
 return jsonb_build_object('staff_id',employee,'balance',coalesce(archived.pending_off::integer,0),
  'revision',0,'updated_at',null,'source_week',archived.source_week);
end $function$
;
alter function goya_private.off_snapshot(employee uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.apply_off_credits(employee uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare g record;b jsonb;next_balance integer;
begin
 perform 1 from public.staff where id=employee for update;
 for g in select c.id,c.days,c.effective_on,c.notice,c.actor from goya_private.off_credit_members m
 join goya_private.off_credit_batches c on c.id=m.batch_id where m.staff_id=employee and m.applied_at is null
 and c.reversed_at is null and c.effective_on<=(now() at time zone 'Asia/Dubai')::date order by c.effective_on,c.id for update of m loop
  b:=goya_private.off_snapshot(employee);next_balance:=(b->>'balance')::integer+g.days;
  insert into goya_private.staff_off_balances(staff_id,balance) values(employee,next_balance)
  on conflict(staff_id) do update set balance=excluded.balance,revision=staff_off_balances.revision+1,updated_at=clock_timestamp();
  update goya_private.off_credit_members set applied_at=clock_timestamp() where batch_id=g.id and staff_id=employee;
  insert into goya_private.off_balance_events(staff_id,delta,balance_after,effective_on,source,source_id,notice,actor)
  values(employee,g.days,next_balance,g.effective_on,'credit',g.id::text,g.notice,g.actor);
  insert into goya_private.staff_hr_audit(staff_id,event,details) values(employee,'Paid Off credited',jsonb_build_object('days',g.days,'before',b,'after',goya_private.off_snapshot(employee),'actor',g.actor,'batch',g.id));
 end loop;
end $function$
;
alter function goya_private.apply_off_credits(employee uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.apply_due_off_credits()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid;begin
 for employee in select distinct m.staff_id from goya_private.off_credit_members m join goya_private.off_credit_batches c on c.id=m.batch_id
 where m.applied_at is null and c.reversed_at is null and c.effective_on<=(now() at time zone 'Asia/Dubai')::date order by m.staff_id loop perform goya_private.apply_off_credits(employee);end loop;
end $function$
;
alter function goya_private.apply_due_off_credits() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_staff_history_page(p_token text, p_kind text DEFAULT 'orders'::text, p_month date DEFAULT CURRENT_DATE, p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$
;
alter function public.goya_staff_history_page(p_token text, p_kind text, p_month date, p_filters jsonb, p_page integer) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_order_summary(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.require_session(p_token,true);
 return jsonb_build_object('counts',(select jsonb_build_object('Pending',count(*) filter(where status='Pending'),'Ordered',count(*) filter(where status='Ordered'),'Received',count(*) filter(where status='Received'),'Not Received',count(*) filter(where status='Not Received')) from public.orders),
 'recent',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc),'[]') from (select o.id,o.name,o.supplier,o.status,o.logged_by,o.created_at,g.order_no from public.orders o join public.order_groups g on g.id=o.order_group_id order by o.created_at desc,o.id desc limit 8)x));
end $function$
;
alter function public.goya_admin_order_summary(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_bootstrap(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.require_session(p_token,true);
  perform public.attendance_sync_portal_staff(p_token);
  return jsonb_build_object(
    'staff',(select coalesce(jsonb_agg(to_jsonb(x) order by lower(x.name)),'[]'::jsonb) from public.attendance_staff x where x.active=true),
    'settings',(select coalesce(value,'{}'::jsonb) from public.attendance_settings where key='rules')
  );
end; $function$
;
alter function public.attendance_bootstrap(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_sync_portal_staff(p_token text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int;
begin
  perform public.require_session(p_token,true);
  insert into public.attendance_staff(portal_staff_id,name,employment_type,active)
  select s.id,s.name,'Full Time',s.active from public.staff s
  where not exists(select 1 from public.attendance_staff a where a.portal_staff_id=s.id)
  on conflict do nothing;
  get diagnostics n = row_count;
  update public.attendance_staff a set name=s.name,active=s.active,updated_at=now()
  from public.staff s where a.portal_staff_id=s.id;
  return n;
end; $function$
;
alter function public.attendance_sync_portal_staff(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_save_staff(p_token text, p_id uuid, p_name text, p_employee_code text, p_employment_type text, p_designation text, p_phone text, p_default_start_time time without time zone, p_expected_presence_minutes integer, p_default_break_minutes integer, p_active boolean, p_notes text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;
begin
 perform public.require_session(p_token,true);
 if p_id is null then
   insert into public.attendance_staff(name,employee_code,employment_type,designation,phone,default_start_time,expected_presence_minutes,default_break_minutes,active,notes)
   values(trim(p_name),nullif(trim(p_employee_code),''),coalesce(p_employment_type,'Full Time'),nullif(trim(p_designation),''),nullif(trim(p_phone),''),coalesce(p_default_start_time,'08:00'),coalesce(p_expected_presence_minutes,540),coalesce(p_default_break_minutes,60),coalesce(p_active,true),p_notes)
   returning id into v_id;
 else
   update public.attendance_staff set name=trim(p_name),employee_code=nullif(trim(p_employee_code),''),employment_type=coalesce(p_employment_type,'Full Time'),designation=nullif(trim(p_designation),''),phone=nullif(trim(p_phone),''),default_start_time=coalesce(p_default_start_time,default_start_time),expected_presence_minutes=coalesce(p_expected_presence_minutes,expected_presence_minutes),default_break_minutes=coalesce(p_default_break_minutes,default_break_minutes),active=coalesce(p_active,active),notes=p_notes,updated_at=now() where id=p_id returning id into v_id;
 end if;
 return v_id;
end; $function$
;
alter function public.attendance_save_staff(p_token text, p_id uuid, p_name text, p_employee_code text, p_employment_type text, p_designation text, p_phone text, p_default_start_time time without time zone, p_expected_presence_minutes integer, p_default_break_minutes integer, p_active boolean, p_notes text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_save_settings(p_token text, p_value jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin perform public.require_session(p_token,true); insert into public.attendance_settings(key,value,updated_at) values('rules',p_value,now()) on conflict(branch_id,key) do update set value=excluded.value,updated_at=now(); return true; end; $function$
;
alter function public.attendance_save_settings(p_token text, p_value jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_get_document(p_token text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin perform public.require_session(p_token,true); return (select jsonb_build_object('file_name',file_name,'mime_type',mime_type,'base64',encode(file_data,'base64')) from public.attendance_documents where id=p_id); end; $function$
;
alter function public.attendance_get_document(p_token text, p_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_delete_notice(p_token text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.require_session(p_token,true);
 update goya_private.notices set active=false,deleted_at=coalesce(deleted_at,now()),updated_at=now() where id=p_id;
 if not found then raise exception 'Notice not found';end if;
 update goya_private.notice_push_jobs set cancelled_at=coalesce(cancelled_at,now()) where notice_id=p_id;
 return jsonb_build_object('ok',true);
end $function$
;
alter function public.goya_admin_delete_notice(p_token text, p_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_notices(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.require_session(p_token,true);
 return (select coalesce(jsonb_agg(to_jsonb(n)||jsonb_build_object('push',case when j.notice_id is null then null else jsonb_build_object('requested_at',j.requested_at,'started_at',j.started_at,'cancelled_at',j.cancelled_at,'devices',(select count(*) from goya_private.notice_push_deliveries d where d.notice_id=n.id),'sent',(select count(*) from goya_private.notice_push_deliveries d where d.notice_id=n.id and sent_at is not null),'failed',(select count(*) from goya_private.notice_push_deliveries d where d.notice_id=n.id and sent_at is null and attempts>=3)) end) order by n.created_at desc),'[]'::jsonb) from goya_private.notices n left join goya_private.notice_push_jobs j on j.notice_id=n.id where n.deleted_at is null);
end $function$
;
alter function public.goya_admin_notices(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_import_records(p_token text, p_rows jsonb, p_file_name text, p_upload_type text, p_date_from date, p_date_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it jsonb; s_id uuid; r_id uuid; n int:=0; skipped int:=0; code text; nm text;
begin
 perform public.require_session(p_token,true);
 for it in select * from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
   nm:=trim(it->>'name'); code:=nullif(trim(it->>'employee_code'),'');
   if nm='' or nullif(it->>'operational_date','') is null then continue; end if;
   select id into s_id from public.attendance_staff where (code is not null and employee_code=code) or lower(name)=lower(nm) order by (employee_code=code) desc nulls last limit 1;
   if s_id is null then insert into public.attendance_staff(name,employee_code,employment_type) values(nm,code,'Full Time') returning id into s_id; end if;
   insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,device_file)
   values(s_id,(it->>'operational_date')::date,nullif(it->>'punch_in','')::timestamp,nullif(it->>'punch_out','')::timestamp,coalesce((it->>'break_taken')::boolean,true),nullif(it->>'note',''),'device',p_file_name)
   on conflict(branch_id,attendance_staff_id,operational_date) do update set
      punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,
      note=coalesce(nullif(excluded.note,''),public.attendance_records.note),device_file=excluded.device_file,updated_at=now()
   where public.attendance_records.source <> 'manual'
   returning id into r_id;
   if r_id is null then skipped:=skipped+1; else n:=n+1; perform public.attendance_recalc(r_id); end if;
 end loop;
 insert into public.attendance_uploads(file_name,upload_type,date_from,date_to,rows_imported) values(p_file_name,coalesce(p_upload_type,'Daily'),p_date_from,p_date_to,n);
 return jsonb_build_object('imported',n,'manual_preserved',skipped);
end; $function$
;
alter function public.attendance_import_records(p_token text, p_rows jsonb, p_file_name text, p_upload_type text, p_date_from date, p_date_to date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_records_range(p_token text, p_start date, p_end date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 perform public.require_session(p_token,true);
 perform public.attendance_sync_portal_staff(p_token);
 return jsonb_build_object(
   'records',(select coalesce(jsonb_agg(to_jsonb(q) order by q.operational_date desc,lower(q.staff_name)),'[]'::jsonb) from (
     select r.*,s.name staff_name,s.employee_code,s.employment_type,s.designation,s.default_start_time,s.expected_presence_minutes staff_expected_presence_minutes,s.default_break_minutes staff_break_minutes
     from public.attendance_records r join public.attendance_staff s on s.id=r.attendance_staff_id
     where r.operational_date between p_start and p_end
   ) q),
   'staff',(select coalesce(jsonb_agg(to_jsonb(s) order by lower(s.name)),'[]'::jsonb) from public.attendance_staff s where s.active=true)
 );
end; $function$
;
alter function public.attendance_records_range(p_token text, p_start date, p_end date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_delete_record(p_token text, p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin perform public.require_session(p_token,true); delete from public.attendance_records where id=p_id; return true; end; $function$
;
alter function public.attendance_delete_record(p_token text, p_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_upload_document(p_token text, p_staff_id uuid, p_title text, p_file_name text, p_mime_type text, p_file_size integer, p_base64 text, p_note text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare v_id uuid; begin
 perform public.require_session(p_token,true);
 if p_file_size>5242880 then raise exception 'File is larger than 5 MB'; end if;
 insert into public.attendance_documents(attendance_staff_id,title,file_name,mime_type,file_size,file_data,note) values(p_staff_id,p_title,p_file_name,p_mime_type,p_file_size,decode(p_base64,'base64'),p_note) returning id into v_id; return v_id;
end; $function$
;
alter function public.attendance_upload_document(p_token text, p_staff_id uuid, p_title text, p_file_name text, p_mime_type text, p_file_size integer, p_base64 text, p_note text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_list_documents(p_token text, p_staff_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin perform public.require_session(p_token,true); return (select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'title',d.title,'file_name',d.file_name,'mime_type',d.mime_type,'file_size',d.file_size,'note',d.note,'created_at',d.created_at) order by d.created_at desc),'[]'::jsonb) from public.attendance_documents d where d.attendance_staff_id=p_staff_id); end; $function$
;
alter function public.attendance_list_documents(p_token text, p_staff_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_delete_document(p_token text, p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin perform public.require_session(p_token,true); delete from public.attendance_documents where id=p_id; return true; end; $function$
;
alter function public.attendance_delete_document(p_token text, p_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_staff_remember(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare sess public.app_sessions; s public.staff; expiry timestamptz;
begin
 sess:=public.require_session(p_token,false);
 select * into s from public.staff where id=sess.staff_id and active for share;
 if not found then raise exception using message='DEVICE_LOGIN_REQUIRED',errcode='28000';end if;
 update public.app_sessions set expires_at=now()+interval '30 days' where token=p_token and not is_admin and expires_at>now() returning expires_at into expiry;
 if not found then raise exception using message='DEVICE_LOGIN_REQUIRED',errcode='28000';end if;
 insert into goya_private.staff_remembered_sessions(session_token,staff_id)values(p_token,s.id)on conflict(session_token)do nothing;
 return jsonb_build_object('expires_at',expiry);
end $function$
;
alter function public.goya_staff_remember(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_roster_admin_week(p_token text, p_week date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.require_session(p_token,true);
  return jsonb_build_object(
    'draft',(select to_jsonb(w)||jsonb_build_object('published_staff',p.schedule->'staff')
      from goya_private.roster_weeks w left join goya_private.roster_publications p
      on p.week_start=w.week_start and p.revision=w.published_revision where w.week_start=p_week),
    'off_balances',public.goya_management_balances(p_token),'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'employee_code',hp.employee_code,'sections',s.sections,'roster_group',hp.roster_group,'eligible_days',(select jsonb_agg(goya_private.employed_on(s.id,p_week+i) order by i) from generate_series(0,6) i),'joining_date',hp.joining_date,'last_day',coalesce(hp.last_day,(select r.last_working_day from goya_private.staff_resignations r where r.staff_id=s.id and r.cancelled_at is null))) order by s.name,s.id)
      from goya_private.branch_staff s left join goya_private.staff_hr_profiles hp on hp.staff_id=s.id where (hp.joining_date is null or hp.joining_date<=p_week+6) and s.active and not exists(select 1 from goya_private.staff_resignations x where x.staff_id=s.id and x.cancelled_at is null and x.last_working_day<p_week)),'[]'::jsonb),
    'approved_leave',public.goya_hr_week_leave(p_token,p_week),
    'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.revision desc) from
      (select revision,published_at from goya_private.roster_publications where week_start=p_week order by revision desc limit 30) h),'[]'::jsonb)
  );
end $function$
;
alter function public.goya_roster_admin_week(p_token text, p_week date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_archive_upload(p_token text, p_file_name text, p_mime_type text, p_file_size integer, p_base64 text, p_upload_type text, p_date_from date, p_date_to date, p_rows_imported integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;
begin
 perform public.require_session(p_token,true);
 if p_file_size>10485760 then raise exception 'Device file is larger than 10 MB'; end if;
 update public.attendance_uploads set mime_type=p_mime_type,file_size=p_file_size,file_data=decode(p_base64,'base64'),rows_imported=coalesce(p_rows_imported,rows_imported)
 where id=(select id from public.attendance_uploads where file_name=p_file_name and date_from is not distinct from p_date_from and date_to is not distinct from p_date_to and file_data is null order by created_at desc limit 1)
 returning id into v_id;
 if v_id is null then
   insert into public.attendance_uploads(file_name,upload_type,date_from,date_to,rows_imported,mime_type,file_size,file_data)
   values(p_file_name,coalesce(p_upload_type,'Daily'),p_date_from,p_date_to,coalesce(p_rows_imported,0),p_mime_type,p_file_size,decode(p_base64,'base64')) returning id into v_id;
 end if;
 return v_id;
end $function$
;
alter function public.attendance_archive_upload(p_token text, p_file_name text, p_mime_type text, p_file_size integer, p_base64 text, p_upload_type text, p_date_from date, p_date_to date, p_rows_imported integer) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_upload_history(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 perform public.require_session(p_token,true);
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'upload_type',upload_type,'date_from',date_from,'date_to',date_to,'rows_imported',rows_imported,'file_size',file_size,'created_at',created_at) order by created_at desc) from public.attendance_uploads),'[]'::jsonb);
end $function$
;
alter function public.attendance_upload_history(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_get_upload(p_token text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 perform public.require_session(p_token,true);
 return (select jsonb_build_object('file_name',file_name,'mime_type',mime_type,'base64',case when file_data is null then null else encode(file_data,'base64') end) from public.attendance_uploads where id=p_id);
end $function$
;
alter function public.attendance_get_upload(p_token text, p_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_attendance_submit(p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; v_id uuid;
begin
 sess:=public.require_session(p_token,false);
 select id into a_id from public.attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then
   insert into public.attendance_staff(portal_staff_id,name,employment_type,active)
   select id,name,'Full Time',active from public.staff where id=sess.staff_id returning id into a_id;
 end if;
 -- Replace only an existing Pending request for the same day; Approved history is preserved.
 delete from public.attendance_staff_submissions where attendance_staff_id=a_id and operational_date=p_operational_date and status='Pending';
 insert into public.attendance_staff_submissions(attendance_staff_id,portal_staff_id,operational_date,punch_in,punch_out,break_taken,day_off,note,status)
 values(a_id,sess.staff_id,p_operational_date,case when p_day_off then null else p_punch_in end,case when p_day_off then null else p_punch_out end,coalesce(p_break_taken,true),coalesce(p_day_off,false),p_note,'Pending') returning id into v_id;
 return v_id;
end $function$
;
alter function public.staff_attendance_submit(p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_attendance_month(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; sd date; ed date;
begin
 sess:=public.require_session(p_token,false);
 select id into a_id from public.attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then return jsonb_build_object('records','[]'::jsonb,'submissions','[]'::jsonb); end if;
 sd:=date_trunc('month',p_month)::date;ed:=(sd+interval '1 month')::date;
 return jsonb_build_object(
  'records',coalesce((select jsonb_agg(to_jsonb(r) order by r.operational_date) from public.attendance_records r where r.attendance_staff_id=a_id and r.operational_date>=sd and r.operational_date<ed),'[]'::jsonb),
  'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.operational_date,s.submitted_at desc) from public.attendance_staff_submissions s where s.attendance_staff_id=a_id and s.operational_date>=sd and s.operational_date<ed),'[]'::jsonb)
 );
end $function$
;
alter function public.staff_attendance_month(p_token text, p_month date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_admin_submissions(p_token text, p_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 perform public.require_session(p_token,true);
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.operational_date desc,q.submitted_at desc) from (
   select s.*,a.name staff_name,a.employment_type from public.attendance_staff_submissions s join public.attendance_staff a on a.id=s.attendance_staff_id
   where p_status is null or p_status='' or s.status=p_status
 )q),'[]'::jsonb);
end $function$
;
alter function public.attendance_admin_submissions(p_token text, p_status text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_review_submission(p_token text, p_id uuid, p_status text, p_admin_note text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.attendance_staff_submissions; a public.attendance_staff; r_id uuid;
begin
 perform public.require_session(p_token,true);
 if p_status not in ('Approved','Rejected') then raise exception 'Invalid review status'; end if;
 select * into s from public.attendance_staff_submissions where id=p_id;
 if s.id is null then raise exception 'Submission not found'; end if;
 if p_status='Approved' then
   select * into a from public.attendance_staff where id=s.attendance_staff_id;
   if s.day_off then
     delete from public.attendance_records where attendance_staff_id=s.attendance_staff_id and operational_date=s.operational_date;
   else
     insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,scheduled_start,expected_presence_minutes,break_minutes)
     values(s.attendance_staff_id,s.operational_date,s.punch_in,s.punch_out,s.break_taken,s.note,'manual',a.default_start_time,a.expected_presence_minutes,a.default_break_minutes)
     on conflict(branch_id,attendance_staff_id,operational_date) do update set punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,note=excluded.note,source='manual',scheduled_start=excluded.scheduled_start,expected_presence_minutes=excluded.expected_presence_minutes,break_minutes=excluded.break_minutes,updated_at=now()
     returning id into r_id;
     perform public.attendance_recalc(r_id);
   end if;
 end if;
 update public.attendance_staff_submissions set status=p_status,admin_note=p_admin_note,reviewed_at=now() where id=p_id;
 return true;
end $function$
;
alter function public.attendance_review_submission(p_token text, p_id uuid, p_status text, p_admin_note text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_finalize_month(p_token text, p_month date, p_summary jsonb, p_details jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid; v_month date;
begin
  perform public.require_session(p_token,true);
  v_month:=date_trunc('month',p_month)::date;
  insert into public.attendance_monthly_finalizations(month_start,summary,details,finalized_at,updated_at)
  values(v_month,coalesce(p_summary,'[]'::jsonb),coalesce(p_details,'[]'::jsonb),now(),now())
  on conflict(branch_id,month_start) do update set summary=excluded.summary,details=excluded.details,finalized_at=now(),updated_at=now()
  returning id into v_id;
  return v_id;
end $function$
;
alter function public.attendance_finalize_month(p_token text, p_month date, p_summary jsonb, p_details jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_get_finalized_month(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_month date;
begin
  perform public.require_session(p_token,true);
  v_month:=date_trunc('month',p_month)::date;
  return (select jsonb_build_object('id',id,'month_start',month_start,'summary',summary,'details',details,'finalized_at',finalized_at)
          from public.attendance_monthly_finalizations where month_start=v_month);
end $function$
;
alter function public.attendance_get_finalized_month(p_token text, p_month date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_staff_resume(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare sess public.app_sessions; s public.staff; expiry timestamptz;
begin
 select * into sess from public.app_sessions where token=p_token and not is_admin and expires_at>now();
 if not found then raise exception using message='DEVICE_LOGIN_REQUIRED',errcode='28000';end if;
 select * into s from public.staff where id=sess.staff_id and active for share;
 if not found then raise exception using message='DEVICE_LOGIN_REQUIRED',errcode='28000';end if;
 update public.app_sessions a set expires_at=now()+interval '30 days'
 where a.token=p_token and not a.is_admin and a.expires_at>now()
 and exists(select 1 from goya_private.staff_remembered_sessions r where r.session_token=a.token and r.staff_id=s.id)
 returning a.expires_at into expiry;
 if not found then raise exception using message='DEVICE_LOGIN_REQUIRED',errcode='28000';end if;
 return jsonb_build_object('token',p_token,'staff_id',s.id,'name',s.name,'expires_at',expiry,'access',jsonb_build_object('order',s.can_order,'production',s.can_production,'wastage',s.can_wastage,'inventory',s.can_inventory,'sections',s.sections));
end $function$
;
alter function public.goya_staff_resume(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.revoke_remembered_staff()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 delete from public.app_sessions a using goya_private.staff_remembered_sessions r where a.token=r.session_token and r.staff_id=new.id and not a.is_admin;
 return new;
end $function$
;
alter function goya_private.revoke_remembered_staff() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_roster_save(p_token text, p_week date, p_expected integer, p_schedule jsonb, p_publish boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare next_revision integer; member record; day jsonb; segment jsonb; previous_end integer; start_min integer; end_min integer;
  snapshot jsonb; leave_day record; approval_actor text;
begin
  perform public.require_session(p_token,true);
  approval_actor:=p_schedule->>'approval_actor';p_schedule:=p_schedule-'approval_actor';
  if p_publish then
   perform 1 from goya_private.branch_staff where id::text in(select key from jsonb_each(p_schedule->'staff'))
    or id in(select staff_id from goya_private.roster_off_charges where charged and off_date between p_week and p_week+6) order by id for update;
  end if;
  if p_week is null or p_schedule is null or p_expected is null or p_publish is null
    or extract(isodow from p_week)<>1 or jsonb_typeof(p_schedule->'staff') is distinct from 'object'
    or jsonb_typeof(p_schedule->'notes') is distinct from 'string'
    or length(p_schedule->>'notes')>2000 or octet_length(p_schedule::text)>262144 then
    raise exception 'Invalid roster';
  end if;
  for member in select * from jsonb_each(p_schedule->'staff') loop
    if not exists(select 1 from goya_private.branch_staff s where s.id::text=member.key and (not p_publish or s.active))
      or jsonb_typeof(member.value) is distinct from 'array' then raise exception 'Invalid roster staff'; end if;
    if jsonb_array_length(member.value)<>7 then raise exception 'Enter all seven days'; end if;
    for day in select value from jsonb_array_elements(member.value) loop
      if day='null'::jsonb then continue; end if;
      if jsonb_typeof(day) is distinct from 'object'
        or coalesce(day->>'kind','') not in ('Shift','Weekly Off','Annual Leave','Sick Leave','Other Leave')
        or jsonb_typeof(day->'segments') is distinct from 'array' then raise exception 'Invalid roster day'; end if;
      if day ? 'off_source' and (day->>'kind'<>'Weekly Off' or coalesce(day->>'off_source','') not in ('balance','advance')) then raise exception 'Invalid Paid Off source';end if;
      if day ? 'label' and (day->>'kind'<>'Shift' or jsonb_typeof(day->'label') is distinct from 'string'
        or length(btrim(day->>'label')) not between 1 and 60 or day->>'label' ~ '[[:cntrl:]]') then
        raise exception 'Enter a custom shift name of 1–60 characters';
      end if;
      if length(coalesce(day->>'note',''))>500 then raise exception 'Shift note is too long'; end if;
      if day->>'kind'='Shift' then
        if jsonb_array_length(day->'segments') not between 1 and 2 then raise exception 'A shift needs one or two time blocks'; end if;
        previous_end := -1;
        for segment in select value from jsonb_array_elements(day->'segments') loop
          if coalesce(segment->>'start','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
            or coalesce(segment->>'end','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
            or coalesce(segment->>'break','') !~ '^[0-9]{1,3}$' then raise exception 'Invalid shift time'; end if;
          start_min := extract(epoch from (segment->>'start')::time)::integer/60;
          end_min := extract(epoch from (segment->>'end')::time)::integer/60;
          if end_min<start_min then end_min := end_min+1440; end if;
          if start_min<previous_end or end_min<=start_min or (segment->>'break')::integer>=end_min-start_min then
            raise exception 'Shift blocks overlap or break exceeds the shift';
          end if;
          previous_end := end_min;
        end loop;
      elsif jsonb_array_length(day->'segments')<>0 then raise exception 'Off or leave days cannot contain a shift'; end if;
    end loop;
  end loop;
  snapshot := p_schedule;
  if p_publish then
    for leave_day in
      select r.staff_id::text as staff_id,case when r.kind in ('Pending Off','Advance Off') then 'Weekly Off' when r.kind='Emergency Leave' then 'Other Leave' else r.kind end as kind,r.kind as request_kind,d as day_index
      from goya_private.staff_leave_requests r join goya_private.branch_staff s on s.id=r.staff_id and s.active
      cross join generate_series(0,6) as dates(d)
      where r.kind<>'Resignation' and r.state='Approved' and p_week+d between r.approved_from and r.approved_to
      order by r.staff_id,d
    loop
      if not ((snapshot->'staff') ? leave_day.staff_id) then
        snapshot := jsonb_set(snapshot,array['staff',leave_day.staff_id],'[null,null,null,null,null,null,null]');
      end if;
      snapshot := jsonb_set(snapshot,array['staff',leave_day.staff_id,leave_day.day_index::text],
        jsonb_build_object('kind',leave_day.kind,'segments','[]'::jsonb,'note','')||case when leave_day.request_kind in ('Pending Off','Advance Off') then jsonb_build_object('off_source','request') else '{}'::jsonb end);
    end loop;
  end if;
  if p_publish then
    for member in select * from jsonb_each(snapshot->'staff') loop
      for start_min in 0..6 loop
        if not goya_private.employed_on(member.key::uuid,p_week+start_min) then
          snapshot:=jsonb_set(snapshot,array['staff',member.key,start_min::text],'null'::jsonb);
        end if;
      end loop;
    end loop;
  end if;
  if p_publish and not exists(select 1 from jsonb_each(snapshot->'staff') m
    cross join lateral jsonb_array_elements(m.value) as days(value) where days.value<>'null'::jsonb) then
    raise exception 'Add at least one shift or day status before publishing';
  end if;
  if p_expected=0 then
    insert into goya_private.roster_weeks(week_start,draft) values(p_week,p_schedule)
      on conflict do nothing returning revision into next_revision;
  else
    update goya_private.roster_weeks set draft=p_schedule,revision=revision+1 where week_start=p_week and revision=p_expected
      returning revision into next_revision;
  end if;
  if next_revision is null then raise exception 'This roster changed. Reload before saving.'; end if;
  if p_publish then
    perform goya_private.reconcile_roster_off(p_token,p_week,snapshot,next_revision,approval_actor);
    insert into goya_private.roster_publications(week_start,revision,schedule) values(p_week,next_revision,snapshot);
    update goya_private.roster_weeks set published_revision=next_revision where week_start=p_week;
  end if;
  return next_revision;
end $function$
;
alter function public.goya_roster_save(p_token text, p_week date, p_expected integer, p_schedule jsonb, p_publish boolean) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.inventory_shared_open(p_token text, p_session_id uuid, p_section text)
 RETURNS goya_private.inventory_shared_sheets
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.app_sessions;s public.staff;v public.inventory_sessions;h goya_private.inventory_shared_sheets;
begin
 a:=public.require_session(p_token,false);
 select * into s from public.staff where id=a.staff_id and active for share;
 if s.id is null then raise exception 'Staff is inactive or unauthorized';end if;
 select * into v from public.inventory_sessions where id=p_session_id for share;
 if v.id is null or not v.shared_count or not v.active or not(p_section=any(v.sections)) or not(p_section=any(s.sections))
 or not(s.id=any(v.assigned_staff_ids) or (cardinality(v.assigned_staff_ids)=0 and s.can_inventory)) then raise exception 'Inventory section is not assigned to this staff';end if;
 if not exists(select 1 from goya_private.inventory_shared_sheets where session_id=v.id and section=p_section) then
  if exists(select sku from (select sku from public.master_items where active and lower(items_type)=lower(p_section) union all select sku from public.internal_items where active and lower(items_type)=lower(p_section))q group by sku having count(*)>1) then raise exception 'Duplicate item SKU in this section. Ask Admin to correct it before starting the sheet.';end if;
  insert into goya_private.inventory_shared_sheets(session_id,section,sheet_name,counting_date)
  values(v.id,p_section,coalesce(nullif(v.title,''),'Inventory Count')||' — '||p_section||' — '||to_char(coalesce(v.counting_date,timezone('Asia/Dubai',now())::date),'DD Mon YYYY'),coalesce(v.counting_date,timezone('Asia/Dubai',now())::date)) on conflict(session_id,section) do nothing;
 end if;
 select * into h from goya_private.inventory_shared_sheets where session_id=v.id and section=p_section for update;
 -- Catalog snapshot is taken once, so item-master edits cannot silently remove count entries.
 if not h.initialized then
  insert into goya_private.inventory_shared_lines(sheet_id,sku,item_name,source,storage_unit,ingredient_unit)
  select h.id,sku,name,'Master',storage_unit,ingredient_unit from public.master_items where active and lower(items_type)=lower(p_section)
  union all select h.id,sku,name,'Internal',storage_unit,ingredient_unit from public.internal_items where active and lower(items_type)=lower(p_section);
  update goya_private.inventory_shared_sheets set initialized=true where id=h.id;
 end if;
 return h;
end $function$
;
alter function goya_private.inventory_shared_open(p_token text, p_session_id uuid, p_section text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_save_manual(p_token text, p_staff_id uuid, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_note text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid; s public.attendance_staff;
begin
 perform public.require_session(p_token,true); select * into s from public.attendance_staff where id=p_staff_id;
 insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,scheduled_start,expected_presence_minutes,break_minutes,day_off,split_shift,shift2_in,shift2_out,entry_origin)
 values(p_staff_id,p_operational_date,p_punch_in,p_punch_out,coalesce(p_break_taken,true),p_note,'manual',s.default_start_time,s.expected_presence_minutes,s.default_break_minutes,false,false,null,null,'admin_manual')
 on conflict(branch_id,attendance_staff_id,operational_date) do update set punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,note=excluded.note,source='manual',scheduled_start=excluded.scheduled_start,expected_presence_minutes=excluded.expected_presence_minutes,break_minutes=excluded.break_minutes,day_off=false,split_shift=false,shift2_in=null,shift2_out=null,entry_origin='admin_manual',updated_at=now() returning id into v_id;
 perform public.attendance_recalc(v_id); return v_id;
end $function$
;
alter function public.attendance_save_manual(p_token text, p_staff_id uuid, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_note text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_attendance_submit_v2(p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; v_id uuid;
begin
 sess:=public.require_session(p_token,false);
 select id into a_id from public.attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then insert into public.attendance_staff(portal_staff_id,name,employment_type,active) select id,name,'Full Time',active from public.staff where id=sess.staff_id returning id into a_id; end if;
 delete from public.attendance_staff_submissions where attendance_staff_id=a_id and operational_date=p_operational_date and status='Pending';
 insert into public.attendance_staff_submissions(attendance_staff_id,portal_staff_id,operational_date,punch_in,punch_out,break_taken,day_off,note,status,split_shift,shift2_in,shift2_out)
 values(a_id,sess.staff_id,p_operational_date,case when p_day_off then null else p_punch_in end,case when p_day_off then null else p_punch_out end,coalesce(p_break_taken,true),coalesce(p_day_off,false),p_note,'Pending',case when p_day_off then false else coalesce(p_split_shift,false) end,case when p_day_off then null else p_shift2_in end,case when p_day_off then null else p_shift2_out end) returning id into v_id;
 return v_id;
end $function$
;
alter function public.staff_attendance_submit_v2(p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_admin_submissions_v2(p_token text, p_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 perform public.require_session(p_token,true);
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.operational_date desc,q.submitted_at desc) from (
   select s.*,a.name staff_name,a.employment_type,
     r.punch_in device_punch_in,r.punch_out device_punch_out,r.split_shift device_split_shift,r.shift2_in device_shift2_in,r.shift2_out device_shift2_out
   from public.attendance_staff_submissions s join public.attendance_staff a on a.id=s.attendance_staff_id
   left join public.attendance_records r on r.attendance_staff_id=s.attendance_staff_id and r.operational_date=s.operational_date and coalesce(r.entry_origin,'device')='device'
   where p_status is null or p_status='' or s.status=p_status
 )q),'[]'::jsonb);
end $function$
;
alter function public.attendance_admin_submissions_v2(p_token text, p_status text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_review_submission_v2(p_token text, p_id uuid, p_status text, p_admin_note text, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone, p_note text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.attendance_staff_submissions; a public.attendance_staff; r_id uuid;
begin
 perform public.require_session(p_token,true);
 if p_status not in ('Approved','Rejected') then raise exception 'Invalid review status'; end if;
 select * into s from public.attendance_staff_submissions where id=p_id; if s.id is null then raise exception 'Submission not found'; end if;
 update public.attendance_staff_submissions set punch_in=p_punch_in,punch_out=p_punch_out,break_taken=coalesce(p_break_taken,true),day_off=coalesce(p_day_off,false),split_shift=coalesce(p_split_shift,false),shift2_in=p_shift2_in,shift2_out=p_shift2_out,note=p_note,status=p_status,admin_note=p_admin_note,reviewed_at=now() where id=p_id;
 if p_status='Approved' then
   select * into a from public.attendance_staff where id=s.attendance_staff_id;
   insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,scheduled_start,expected_presence_minutes,break_minutes,day_off,split_shift,shift2_in,shift2_out,entry_origin)
   values(s.attendance_staff_id,s.operational_date,case when p_day_off then null else p_punch_in end,case when p_day_off then null else p_punch_out end,coalesce(p_break_taken,true),p_note,'manual',a.default_start_time,a.expected_presence_minutes,a.default_break_minutes,coalesce(p_day_off,false),case when p_day_off then false else coalesce(p_split_shift,false) end,case when p_day_off then null else p_shift2_in end,case when p_day_off then null else p_shift2_out end,'staff_approved')
   on conflict(branch_id,attendance_staff_id,operational_date) do update set punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,note=excluded.note,source='manual',scheduled_start=excluded.scheduled_start,expected_presence_minutes=excluded.expected_presence_minutes,break_minutes=excluded.break_minutes,day_off=excluded.day_off,split_shift=excluded.split_shift,shift2_in=excluded.shift2_in,shift2_out=excluded.shift2_out,entry_origin='staff_approved',updated_at=now() returning id into r_id;
   perform public.attendance_recalc(r_id);
 end if;
 return true;
end $function$
;
alter function public.attendance_review_submission_v2(p_token text, p_id uuid, p_status text, p_admin_note text, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone, p_note text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_import_records_v2(p_token text, p_rows jsonb, p_file_name text, p_upload_type text, p_date_from date, p_date_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it jsonb; s_id uuid; r_id uuid; n int:=0; skipped int:=0; code text; nm text;
begin
 perform public.require_session(p_token,true);
 for it in select * from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
   nm:=trim(it->>'name'); code:=nullif(trim(it->>'employee_code'),''); if nm='' or nullif(it->>'operational_date','') is null then continue; end if;
   select id into s_id from public.attendance_staff where (code is not null and employee_code=code) or lower(name)=lower(nm) order by (employee_code=code) desc nulls last limit 1;
   if s_id is null then insert into public.attendance_staff(name,employee_code,employment_type) values(nm,code,'Full Time') returning id into s_id; end if;
   insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,device_file,day_off,split_shift,shift2_in,shift2_out,entry_origin)
   values(s_id,(it->>'operational_date')::date,nullif(it->>'punch_in','')::timestamp,nullif(it->>'punch_out','')::timestamp,coalesce((it->>'break_taken')::boolean,true),nullif(it->>'note',''),'device',p_file_name,false,coalesce((it->>'split_shift')::boolean,false),nullif(it->>'shift2_in','')::timestamp,nullif(it->>'shift2_out','')::timestamp,'device')
   on conflict(branch_id,attendance_staff_id,operational_date) do update set punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,note=coalesce(nullif(excluded.note,''),public.attendance_records.note),device_file=excluded.device_file,day_off=false,split_shift=excluded.split_shift,shift2_in=excluded.shift2_in,shift2_out=excluded.shift2_out,entry_origin='device',source='device',updated_at=now()
   where coalesce(public.attendance_records.entry_origin,'device')='device'
   returning id into r_id;
   if r_id is null then skipped:=skipped+1; else n:=n+1; perform public.attendance_recalc(r_id); end if;
 end loop;
 insert into public.attendance_uploads(file_name,upload_type,date_from,date_to,rows_imported) values(p_file_name,coalesce(p_upload_type,'Daily'),p_date_from,p_date_to,n);
 return jsonb_build_object('imported',n,'manual_preserved',skipped);
end $function$
;
alter function public.attendance_import_records_v2(p_token text, p_rows jsonb, p_file_name text, p_upload_type text, p_date_from date, p_date_to date) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.inventory_shared_payload(p_sheet uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select to_jsonb(h)||jsonb_build_object('shared',true,'done',h.submitted_at is not null,
 'items',coalesce((select jsonb_agg(jsonb_build_object('name',l.item_name,'sku',l.sku,'source',l.source,'storage_unit',l.storage_unit,'ingredient_unit',l.ingredient_unit,'storage_quantity',l.storage_quantity,'ingredients_quantity',l.ingredients_quantity,'version',l.version,'updated_name',l.updated_name,'updated_at',l.updated_at) order by lower(l.item_name),l.sku) from goya_private.inventory_shared_lines l where sheet_id=h.id),'[]'::jsonb)) from goya_private.inventory_shared_sheets h where id=p_sheet;
$function$
;
alter function goya_private.inventory_shared_payload(p_sheet uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_attendance_submit_v10(p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; v_id uuid;
begin
 sess:=public.require_session(p_token,false);
 select id into a_id from public.attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then
   insert into public.attendance_staff(portal_staff_id,name,employment_type,active)
   select id,name,'Full Time',active from public.staff where id=sess.staff_id returning id into a_id;
 end if;
 -- Re-submit replaces only the current not-finalized submission for that staff/date.
 delete from public.attendance_staff_submissions
 where attendance_staff_id=a_id and operational_date=p_operational_date and status in ('Pending','Submitted');
 insert into public.attendance_staff_submissions(attendance_staff_id,portal_staff_id,operational_date,punch_in,punch_out,break_taken,day_off,note,status,split_shift,shift2_in,shift2_out)
 values(a_id,sess.staff_id,p_operational_date,case when p_day_off then null else p_punch_in end,case when p_day_off then null else p_punch_out end,
   coalesce(p_break_taken,true),coalesce(p_day_off,false),p_note,'Submitted',
   case when p_day_off then false else coalesce(p_split_shift,false) end,
   case when p_day_off then null else p_shift2_in end,case when p_day_off then null else p_shift2_out end)
 returning id into v_id;
 return v_id;
end $function$
;
alter function public.staff_attendance_submit_v10(p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_attendance_month_v10(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; sd date; ed date;
begin
 sess:=public.require_session(p_token,false);
 select id into a_id from public.attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then return jsonb_build_object('records','[]'::jsonb,'submissions','[]'::jsonb); end if;
 sd:=date_trunc('month',p_month)::date; ed:=(sd+interval '1 month')::date;
 return jsonb_build_object(
   'records',coalesce((select jsonb_agg(to_jsonb(r) order by r.operational_date) from public.attendance_records r where r.attendance_staff_id=a_id and r.operational_date>=sd and r.operational_date<ed),'[]'::jsonb),
   'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.operational_date,s.submitted_at desc) from public.attendance_staff_submissions s where s.attendance_staff_id=a_id and s.operational_date>=sd and s.operational_date<ed),'[]'::jsonb)
 );
end $function$
;
alter function public.staff_attendance_month_v10(p_token text, p_month date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_import_records_v10(p_token text, p_rows jsonb, p_file_name text, p_upload_type text, p_date_from date, p_date_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it jsonb; s_id uuid; r_id uuid; n int:=0; final_updated int:=0; code text; nm text;
begin
 perform public.require_session(p_token,true);
 for it in select * from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
   nm:=trim(it->>'name'); code:=nullif(trim(it->>'employee_code'),'');
   if nm='' or nullif(it->>'operational_date','') is null then continue; end if;
   select id into s_id from public.attendance_staff
   where (code is not null and employee_code=code) or lower(name)=lower(nm)
   order by (employee_code=code) desc nulls last limit 1;
   if s_id is null then insert into public.attendance_staff(name,employee_code,employment_type) values(nm,code,'Full Time') returning id into s_id; end if;

   insert into public.attendance_device_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,split_shift,shift2_in,shift2_out,note,device_file)
   values(s_id,(it->>'operational_date')::date,nullif(it->>'punch_in','')::timestamp,nullif(it->>'punch_out','')::timestamp,
     coalesce((it->>'break_taken')::boolean,true),coalesce((it->>'split_shift')::boolean,false),nullif(it->>'shift2_in','')::timestamp,nullif(it->>'shift2_out','')::timestamp,nullif(it->>'note',''),p_file_name)
   on conflict(branch_id,attendance_staff_id,operational_date) do update set
     punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,split_shift=excluded.split_shift,
     shift2_in=excluded.shift2_in,shift2_out=excluded.shift2_out,note=excluded.note,device_file=excluded.device_file,updated_at=now();
   n:=n+1;

   insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,device_file,day_off,split_shift,shift2_in,shift2_out,entry_origin)
   values(s_id,(it->>'operational_date')::date,nullif(it->>'punch_in','')::timestamp,nullif(it->>'punch_out','')::timestamp,
     coalesce((it->>'break_taken')::boolean,true),nullif(it->>'note',''),'device',p_file_name,false,coalesce((it->>'split_shift')::boolean,false),
     nullif(it->>'shift2_in','')::timestamp,nullif(it->>'shift2_out','')::timestamp,'device')
   on conflict(branch_id,attendance_staff_id,operational_date) do update set
     punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,note=coalesce(nullif(excluded.note,''),public.attendance_records.note),
     device_file=excluded.device_file,day_off=false,split_shift=excluded.split_shift,shift2_in=excluded.shift2_in,shift2_out=excluded.shift2_out,
     entry_origin='device',source='device',updated_at=now()
   where coalesce(public.attendance_records.entry_origin,'device')='device'
   returning id into r_id;
   if r_id is not null then final_updated:=final_updated+1; perform public.attendance_recalc(r_id); end if;
 end loop;
 insert into public.attendance_uploads(file_name,upload_type,date_from,date_to,rows_imported)
 values(p_file_name,coalesce(p_upload_type,'Daily'),p_date_from,p_date_to,n);
 return jsonb_build_object('imported',n,'final_updated',final_updated,'admin_final_preserved',n-final_updated);
end $function$
;
alter function public.attendance_import_records_v10(p_token text, p_rows jsonb, p_file_name text, p_upload_type text, p_date_from date, p_date_to date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_save_finalized_report_v10(p_token text, p_file_name text, p_period_label text, p_date_from date, p_date_to date, p_rows jsonb, p_summary jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;
begin
 perform public.require_session(p_token,true);
 insert into public.attendance_finalized_reports(file_name,period_label,date_from,date_to,processed_rows,summary)
 values(p_file_name,p_period_label,p_date_from,p_date_to,coalesce(p_rows,'[]'::jsonb),coalesce(p_summary,'{}'::jsonb)) returning id into v_id;
 return v_id;
end $function$
;
alter function public.attendance_save_finalized_report_v10(p_token text, p_file_name text, p_period_label text, p_date_from date, p_date_to date, p_rows jsonb, p_summary jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.queue_roster_push()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.week_start+6 < (now() at time zone 'Asia/Dubai')::date then return new; end if;
  insert into goya_private.roster_push_deliveries(week_start,revision,subscription_id,staff_id)
    select new.week_start,new.revision,p.id,p.staff_id from goya_private.push_subscriptions p
    join goya_private.branch_staff s on s.id=p.staff_id and s.active
    where p.active and (new.schedule->'staff') ? p.staff_id::text and exists (
      select 1 from jsonb_array_elements(new.schedule->'staff'->p.staff_id::text) as days(value)
      where days.value <> 'null'::jsonb
    );
  return new;
end $function$
;
alter function goya_private.queue_roster_push() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_staff_device_compare_v10(p_token text, p_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 perform public.require_session(p_token,true);
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.operational_date desc,q.submitted_at desc) from (
   select s.*,a.name staff_name,a.employment_type,
     d.punch_in device_punch_in,d.punch_out device_punch_out,d.break_taken device_break_taken,d.split_shift device_split_shift,d.shift2_in device_shift2_in,d.shift2_out device_shift2_out,
     f.punch_in final_punch_in,f.punch_out final_punch_out,f.break_taken final_break_taken,f.split_shift final_split_shift,f.shift2_in final_shift2_in,f.shift2_out final_shift2_out,
     f.net_work_minutes final_net_work_minutes,f.additional_minutes final_additional_minutes,f.entry_origin final_origin
   from public.attendance_staff_submissions s
   join public.attendance_staff a on a.id=s.attendance_staff_id
   left join public.attendance_device_records d on d.attendance_staff_id=s.attendance_staff_id and d.operational_date=s.operational_date
   left join public.attendance_records f on f.attendance_staff_id=s.attendance_staff_id and f.operational_date=s.operational_date
   where p_status is null or p_status='' or s.status=p_status
 )q),'[]'::jsonb);
end $function$
;
alter function public.attendance_staff_device_compare_v10(p_token text, p_status text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_save_final_submission_v10(p_token text, p_id uuid, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone, p_note text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.attendance_staff_submissions; a public.attendance_staff; r_id uuid;
begin
 perform public.require_session(p_token,true);
 select * into s from public.attendance_staff_submissions where id=p_id;
 if s.id is null then raise exception 'Submission not found'; end if;
 select * into a from public.attendance_staff where id=s.attendance_staff_id;
 update public.attendance_staff_submissions set punch_in=p_punch_in,punch_out=p_punch_out,break_taken=coalesce(p_break_taken,true),day_off=coalesce(p_day_off,false),
   split_shift=coalesce(p_split_shift,false),shift2_in=p_shift2_in,shift2_out=p_shift2_out,note=p_note,status='Finalized',reviewed_at=now() where id=p_id;
 insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,scheduled_start,expected_presence_minutes,break_minutes,day_off,split_shift,shift2_in,shift2_out,entry_origin)
 values(s.attendance_staff_id,s.operational_date,case when p_day_off then null else p_punch_in end,case when p_day_off then null else p_punch_out end,coalesce(p_break_taken,true),p_note,'manual',
   a.default_start_time,a.expected_presence_minutes,a.default_break_minutes,coalesce(p_day_off,false),case when p_day_off then false else coalesce(p_split_shift,false) end,
   case when p_day_off then null else p_shift2_in end,case when p_day_off then null else p_shift2_out end,'admin_final')
 on conflict(branch_id,attendance_staff_id,operational_date) do update set
   punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,note=excluded.note,source='manual',scheduled_start=excluded.scheduled_start,
   expected_presence_minutes=excluded.expected_presence_minutes,break_minutes=excluded.break_minutes,day_off=excluded.day_off,split_shift=excluded.split_shift,
   shift2_in=excluded.shift2_in,shift2_out=excluded.shift2_out,entry_origin='admin_final',updated_at=now()
 returning id into r_id;
 perform public.attendance_recalc(r_id);
 return true;
end $function$
;
alter function public.attendance_save_final_submission_v10(p_token text, p_id uuid, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone, p_note text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_finalized_report_history_v10(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 perform public.require_session(p_token,true);
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'file_name',file_name,'period_label',period_label,'date_from',date_from,'date_to',date_to,'summary',summary,'created_at',created_at) order by created_at desc) from public.attendance_finalized_reports),'[]'::jsonb);
end $function$
;
alter function public.attendance_finalized_report_history_v10(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_get_finalized_report_v10(p_token text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 perform public.require_session(p_token,true);
 return (select jsonb_build_object('id',id,'file_name',file_name,'period_label',period_label,'date_from',date_from,'date_to',date_to,'processed_rows',processed_rows,'summary',summary,'created_at',created_at) from public.attendance_finalized_reports where id=p_id);
end $function$
;
alter function public.attendance_get_finalized_report_v10(p_token text, p_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_inventory_shared_work(p_token text, p_session_id uuid, p_section text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare h goya_private.inventory_shared_sheets;begin h:=goya_private.inventory_shared_open(p_token,p_session_id,p_section);return goya_private.inventory_shared_payload(h.id)||jsonb_build_object('viewer_id',(public.require_session(p_token,false)).staff_id);end $function$
;
alter function public.goya_inventory_shared_work(p_token text, p_session_id uuid, p_section text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_attendance_month_v11(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; sd date; ed date; a public.attendance_staff; rules jsonb;
begin
 sess:=public.require_session(p_token,false);
 select * into a from public.attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a.id is null then return jsonb_build_object('records','[]'::jsonb,'submissions','[]'::jsonb,'staff','{}'::jsonb); end if;
 a_id:=a.id; sd:=date_trunc('month',p_month)::date; ed:=(sd+interval '1 month')::date;
 select coalesce(value,'{}'::jsonb) into rules from public.attendance_settings where key='rules';
 return jsonb_build_object(
   'staff',to_jsonb(a) || jsonb_build_object('late_grace_minutes',coalesce((rules->>'late_grace_minutes')::int,15)),
   'records',coalesce((select jsonb_agg(to_jsonb(r) order by r.operational_date) from public.attendance_records r where r.attendance_staff_id=a_id and r.operational_date>=sd and r.operational_date<ed),'[]'::jsonb),
   'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.operational_date,s.submitted_at desc) from public.attendance_staff_submissions s where s.attendance_staff_id=a_id and s.operational_date>=sd and s.operational_date<ed),'[]'::jsonb)
 );
end $function$
;
alter function public.staff_attendance_month_v11(p_token text, p_month date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_import_records_v11(p_token text, p_rows jsonb, p_file_name text, p_upload_type text, p_date_from date, p_date_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it jsonb; s_id uuid; r_id uuid; n int:=0; final_updated int:=0; code text; nm text;
begin
 perform public.require_session(p_token,true);
 for it in select * from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
   nm:=trim(it->>'name'); code:=nullif(trim(it->>'employee_code'),'');
   if nm='' or lower(nm)='goya lounge' or nullif(it->>'operational_date','') is null then continue; end if;
   s_id:=null;
   select id into s_id from public.attendance_staff where lower(trim(name))=lower(trim(nm)) order by active desc,updated_at desc limit 1;
   if s_id is null then insert into public.attendance_staff(name,employee_code,employment_type) values(nm,code,'Full Time') returning id into s_id; end if;

   insert into public.attendance_device_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,split_shift,shift2_in,shift2_out,note,device_file)
   values(s_id,(it->>'operational_date')::date,nullif(it->>'punch_in','')::timestamp,nullif(it->>'punch_out','')::timestamp,
     coalesce((it->>'break_taken')::boolean,true),coalesce((it->>'split_shift')::boolean,false),nullif(it->>'shift2_in','')::timestamp,nullif(it->>'shift2_out','')::timestamp,nullif(it->>'note',''),p_file_name)
   on conflict(branch_id,attendance_staff_id,operational_date) do update set
     punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,split_shift=excluded.split_shift,
     shift2_in=excluded.shift2_in,shift2_out=excluded.shift2_out,note=excluded.note,device_file=excluded.device_file,updated_at=now();
   n:=n+1;

   insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,device_file,day_off,split_shift,shift2_in,shift2_out,entry_origin)
   values(s_id,(it->>'operational_date')::date,nullif(it->>'punch_in','')::timestamp,nullif(it->>'punch_out','')::timestamp,
     coalesce((it->>'break_taken')::boolean,true),nullif(it->>'note',''),'device',p_file_name,false,coalesce((it->>'split_shift')::boolean,false),
     nullif(it->>'shift2_in','')::timestamp,nullif(it->>'shift2_out','')::timestamp,'device')
   on conflict(branch_id,attendance_staff_id,operational_date) do update set
     punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,note=coalesce(nullif(excluded.note,''),public.attendance_records.note),
     device_file=excluded.device_file,day_off=false,split_shift=excluded.split_shift,shift2_in=excluded.shift2_in,shift2_out=excluded.shift2_out,
     entry_origin='device',source='device',updated_at=now()
   where coalesce(public.attendance_records.entry_origin,'device')='device'
   returning id into r_id;
   if r_id is not null then final_updated:=final_updated+1; perform public.attendance_recalc(r_id); end if;
 end loop;
 insert into public.attendance_uploads(file_name,upload_type,date_from,date_to,rows_imported)
 values(p_file_name,coalesce(p_upload_type,'Daily'),p_date_from,p_date_to,n);
 return jsonb_build_object('imported',n,'final_updated',final_updated,'admin_final_preserved',n-final_updated);
end $function$
;
alter function public.attendance_import_records_v11(p_token text, p_rows jsonb, p_file_name text, p_upload_type text, p_date_from date, p_date_to date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_delete_reason(p_token text, p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin perform public.require_session(p_token,true); delete from public.wastage_reasons where id=p_id; return true; end; $function$
;
alter function public.admin_delete_reason(p_token text, p_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_update_finalized_report_v11(p_token text, p_id uuid, p_rows jsonb, p_summary jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 perform public.require_session(p_token,true);
 update public.attendance_finalized_reports set processed_rows=coalesce(p_rows,'[]'::jsonb),summary=coalesce(p_summary,'{}'::jsonb) where id=p_id;
 return found;
end $function$
;
alter function public.attendance_update_finalized_report_v11(p_token text, p_id uuid, p_rows jsonb, p_summary jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_inventory_shared_save(p_token text, p_session_id uuid, p_section text, p_generation bigint, p_changes jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare h goya_private.inventory_shared_sheets;a public.app_sessions;s public.staff;x jsonb;l goya_private.inventory_shared_lines;sv numeric;iv numeric;conflicts jsonb:='[]';
begin
 h:=goya_private.inventory_shared_open(p_token,p_session_id,p_section);a:=public.require_session(p_token,false);select * into s from public.staff where id=a.staff_id;
 if h.submitted_at is not null then return jsonb_build_object('ok',false,'reason','submitted','sheet',goya_private.inventory_shared_payload(h.id));end if;
 if p_generation is distinct from h.generation then return jsonb_build_object('ok',false,'reason','reopened','sheet',goya_private.inventory_shared_payload(h.id));end if;
 if jsonb_typeof(p_changes) is distinct from 'array' or jsonb_array_length(p_changes)>2000 then raise exception 'Invalid changes';end if;
 if exists(select j.value->>'sku' from jsonb_array_elements(p_changes)j group by j.value->>'sku' having count(*)>1) then raise exception 'Duplicate item changes';end if;
 for x in select * from jsonb_array_elements(p_changes) loop
  select * into l from goya_private.inventory_shared_lines where sheet_id=h.id and sku=x->>'sku';
  if not found then raise exception 'Unknown inventory item';end if;
  if not(x ? 'storage_quantity' and x ? 'ingredients_quantity' and x ? 'version') then raise exception 'Incomplete change payload';end if;
  sv:=nullif(x->>'storage_quantity','')::numeric;iv:=nullif(x->>'ingredients_quantity','')::numeric;
  if (sv is not null and (sv<0 or sv>1000000000000 or sv<>round(sv,3) or sv::text in ('NaN','Infinity','-Infinity'))) or (iv is not null and (iv<0 or iv>1000000000000 or iv<>round(iv,3) or iv::text in ('NaN','Infinity','-Infinity'))) then raise exception 'Use nonnegative quantities with up to three decimal places';end if;
  if (x->>'version')::bigint is distinct from l.version and (sv is distinct from l.storage_quantity or iv is distinct from l.ingredients_quantity) then conflicts:=conflicts||jsonb_build_array(x->>'sku');end if;
 end loop;
 if jsonb_array_length(conflicts)>0 then return jsonb_build_object('ok',false,'reason','conflict','conflicts',conflicts,'sheet',goya_private.inventory_shared_payload(h.id));end if;
 for x in select * from jsonb_array_elements(p_changes) loop
  select * into l from goya_private.inventory_shared_lines where sheet_id=h.id and sku=x->>'sku';sv:=nullif(x->>'storage_quantity','')::numeric;iv:=nullif(x->>'ingredients_quantity','')::numeric;
  if sv is distinct from l.storage_quantity or iv is distinct from l.ingredients_quantity then
   insert into goya_private.inventory_shared_audit(sheet_id,sku,event,actor_id,actor_name,old_values,new_values) values(h.id,l.sku,'edit',s.id,s.name,jsonb_build_object('storage',l.storage_quantity,'ingredients',l.ingredients_quantity),jsonb_build_object('storage',sv,'ingredients',iv));
   update goya_private.inventory_shared_lines set storage_quantity=sv,ingredients_quantity=iv,version=version+1,updated_by=s.id,updated_name=s.name,updated_at=now() where sheet_id=h.id and sku=l.sku;
   update goya_private.inventory_shared_sheets set version=version+1 where id=h.id;
  end if;
 end loop;
 return jsonb_build_object('ok',true,'sheet',goya_private.inventory_shared_payload(h.id));
end $function$
;
alter function public.goya_inventory_shared_save(p_token text, p_session_id uuid, p_section text, p_generation bigint, p_changes jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_inventory_shared_submit(p_token text, p_session_id uuid, p_section text, p_generation bigint, p_version bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare h goya_private.inventory_shared_sheets;a public.app_sessions;s public.staff;
begin
 h:=goya_private.inventory_shared_open(p_token,p_session_id,p_section);a:=public.require_session(p_token,false);select * into s from public.staff where id=a.staff_id;
 if h.submitted_at is not null then return jsonb_build_object('ok',true,'already_submitted',true,'sheet',goya_private.inventory_shared_payload(h.id));end if;
 if p_generation is distinct from h.generation or p_version is distinct from h.version then return jsonb_build_object('ok',false,'reason','changed','sheet',goya_private.inventory_shared_payload(h.id));end if;
 if not exists(select 1 from goya_private.inventory_shared_lines where sheet_id=h.id) or exists(select 1 from goya_private.inventory_shared_lines where sheet_id=h.id and (storage_quantity is null or ingredients_quantity is null)) then raise exception 'Complete both quantities for every item before submission';end if;
 insert into goya_private.inventory_shared_finals(sheet_id,generation,version,submitted_by,submitted_name,items) values(h.id,h.generation,h.version,s.id,s.name,goya_private.inventory_shared_payload(h.id)->'items');
 insert into public.inventory_counts(session_id,staff_id,item_name,sku,section,storage_quantity,ingredients_quantity,counted_by,counted_at,shared_sheet_id,sheet_name,counting_date)
 select p_session_id,s.id,item_name,sku,p_section,storage_quantity,ingredients_quantity,coalesce(updated_name,s.name),now(),h.id,h.sheet_name,h.counting_date from goya_private.inventory_shared_lines where sheet_id=h.id
 on conflict(shared_sheet_id,sku) where shared_sheet_id is not null do update set staff_id=excluded.staff_id,storage_quantity=excluded.storage_quantity,ingredients_quantity=excluded.ingredients_quantity,counted_by=excluded.counted_by,counted_at=excluded.counted_at;
 update goya_private.inventory_shared_sheets set submitted_at=now(),submitted_by=s.id,submitted_name=s.name,version=version+1 where id=h.id;
 insert into goya_private.inventory_shared_audit(sheet_id,event,actor_id,actor_name) values(h.id,'submit',s.id,s.name);
 return jsonb_build_object('ok',true,'sheet',goya_private.inventory_shared_payload(h.id));
end $function$
;
alter function public.goya_inventory_shared_submit(p_token text, p_session_id uuid, p_section text, p_generation bigint, p_version bigint) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_inventory_reopen(p_token text, p_session_id uuid, p_section text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare h goya_private.inventory_shared_sheets;begin
 perform public.require_session(p_token,true);select * into h from goya_private.inventory_shared_sheets where session_id=p_session_id and section=p_section for update;
 if h.id is null then raise exception 'Shared sheet has not been started';end if;
 if h.submitted_at is null then raise exception 'This sheet is already open';end if;
 update goya_private.inventory_shared_sheets set submitted_at=null,submitted_by=null,submitted_name=null,generation=generation+1,version=version+1 where id=h.id;
 insert into goya_private.inventory_shared_audit(sheet_id,event,actor_name,old_values) values(h.id,'reopen','Admin',jsonb_build_object('generation',h.generation,'submitted_at',h.submitted_at));
 return jsonb_build_object('ok',true);
end $function$
;
alter function public.goya_admin_inventory_reopen(p_token text, p_session_id uuid, p_section text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_inventory_shared_history(p_token text, p_session_id uuid, p_section text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.app_sessions;h goya_private.inventory_shared_sheets;begin
 begin a:=public.require_session(p_token,true);select * into h from goya_private.inventory_shared_sheets where session_id=p_session_id and section=p_section;
 exception when others then h:=goya_private.inventory_shared_open(p_token,p_session_id,p_section);end;
 return jsonb_build_object('events',coalesce((select jsonb_agg(to_jsonb(q)) from (select sku,event,actor_name,old_values,new_values,created_at from goya_private.inventory_shared_audit where sheet_id=h.id order by id desc limit 100)q),'[]'::jsonb),
 'submissions',coalesce((select jsonb_agg(to_jsonb(q)) from (select generation,submitted_name,submitted_at,items from goya_private.inventory_shared_finals where sheet_id=h.id order by generation desc)q),'[]'::jsonb));
end $function$
;
alter function public.goya_inventory_shared_history(p_token text, p_session_id uuid, p_section text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.inventory_work(p_token text, p_session_id uuid, p_section text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions;s public.staff;subtime timestamptz;draft_items jsonb;allowed boolean;
begin
  if exists(select 1 from public.inventory_sessions where id=p_session_id and shared_count) then return public.goya_inventory_shared_work(p_token,p_session_id,p_section);end if;
  sess:=public.require_session(p_token,false);select * into s from public.staff where id=sess.staff_id;
  select exists(select 1 from public.inventory_sessions v where v.id=p_session_id and v.active and p_section=any(v.sections) and p_section=any(s.sections) and (s.id=any(v.assigned_staff_ids) or (coalesce(array_length(v.assigned_staff_ids,1),0)=0 and s.can_inventory))) into allowed;
  if not allowed then raise exception 'Inventory section is not assigned to this staff'; end if;
  select submitted_at into subtime from public.inventory_submissions where session_id=p_session_id and staff_id=s.id and section=p_section;
  select items into draft_items from public.inventory_drafts where session_id=p_session_id and staff_id=s.id and section=p_section;
  return jsonb_build_object('done',subtime is not null,'submitted_at',subtime,'draft',coalesce(draft_items,'[]'::jsonb),'items',(
    select coalesce(jsonb_agg(to_jsonb(z) order by lower(z.name),z.source),'[]'::jsonb) from (
      select m.name,m.sku,m.storage_unit,m.ingredient_unit,'Master'::text source from public.master_items m where m.active=true and lower(m.items_type)=lower(p_section)
      union all
      select i.name,i.sku,i.storage_unit,i.ingredient_unit,'Internal'::text source from public.internal_items i where i.active=true and lower(i.items_type)=lower(p_section)
    )z
  ));
end $function$
;
alter function public.inventory_work(p_token text, p_session_id uuid, p_section text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_attendance_submit_v12(p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; v_id uuid; cur_month date;
begin
 sess:=public.require_session(p_token,false);
 cur_month:=date_trunc('month',(now() at time zone 'Asia/Dubai')::date)::date;
 if date_trunc('month',p_operational_date)::date<>cur_month then
   raise exception 'Previous month attendance is locked for staff editing.';
 end if;
 select id into a_id from public.attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then
   insert into public.attendance_staff(portal_staff_id,name,employment_type,active)
   select id,name,'Full Time',active from public.staff where id=sess.staff_id returning id into a_id;
 end if;
 delete from public.attendance_staff_submissions
 where attendance_staff_id=a_id and operational_date=p_operational_date and status in ('Pending','Submitted');
 insert into public.attendance_staff_submissions(attendance_staff_id,portal_staff_id,operational_date,punch_in,punch_out,break_taken,day_off,note,status,split_shift,shift2_in,shift2_out)
 values(a_id,sess.staff_id,p_operational_date,case when p_day_off then null else p_punch_in end,case when p_day_off then null else p_punch_out end,
   coalesce(p_break_taken,true),coalesce(p_day_off,false),p_note,'Submitted',case when p_day_off then false else coalesce(p_split_shift,false) end,
   case when p_day_off then null else p_shift2_in end,case when p_day_off then null else p_shift2_out end)
 returning id into v_id;
 return v_id;
end $function$
;
alter function public.staff_attendance_submit_v12(p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.inventory_save_draft(p_token text, p_session_id uuid, p_section text, p_items jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions;s public.staff;
begin
  if exists(select 1 from public.inventory_sessions where id=p_session_id and shared_count) then raise exception 'Shared count: refresh your Staff Portal to save or submit safely';end if;
  sess:=public.require_session(p_token,false);select * into s from public.staff where id=sess.staff_id;
  perform public.inventory_work(p_token,p_session_id,p_section);
  if exists(select 1 from public.inventory_submissions where session_id=p_session_id and staff_id=s.id and section=p_section) then raise exception 'This section is already submitted'; end if;
  insert into public.inventory_drafts(session_id,staff_id,section,items,updated_at) values(p_session_id,s.id,p_section,coalesce(p_items,'[]'::jsonb),now()) on conflict(session_id,staff_id,section) do update set items=excluded.items,updated_at=now();
  return true;
end $function$
;
alter function public.inventory_save_draft(p_token text, p_session_id uuid, p_section text, p_items jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.inventory_submit_final(p_token text, p_session_id uuid, p_section text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions;s public.staff;it jsonb;expected int;provided int;n int:=0;
begin
  if exists(select 1 from public.inventory_sessions where id=p_session_id and shared_count) then raise exception 'Shared count: refresh your Staff Portal to save or submit safely';end if;
  sess:=public.require_session(p_token,false);select * into s from public.staff where id=sess.staff_id;
  perform public.inventory_work(p_token,p_session_id,p_section);
  if exists(select 1 from public.inventory_submissions where session_id=p_session_id and staff_id=s.id and section=p_section) then raise exception 'This section is already submitted'; end if;
  select count(*) into expected from (select sku from public.master_items where active=true and lower(items_type)=lower(p_section) union all select sku from public.internal_items where active=true and lower(items_type)=lower(p_section))q;
  if jsonb_typeof(p_items)<>'array' then raise exception 'Invalid inventory payload'; end if; provided:=jsonb_array_length(p_items);
  if provided<>expected then raise exception 'All inventory items must be completed before submission'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    if coalesce(it->>'storage_quantity','')='' or coalesce(it->>'ingredients_quantity','')='' then raise exception 'Every item requires Storage Qty and Ingredients Qty'; end if;
    insert into public.inventory_counts(session_id,staff_id,item_name,sku,section,storage_quantity,ingredients_quantity,counted_by,counted_at) values(p_session_id,s.id,trim(it->>'item_name'),trim(it->>'sku'),p_section,(it->>'storage_quantity')::numeric,(it->>'ingredients_quantity')::numeric,s.name,now()) on conflict(session_id,staff_id,sku,section) do update set item_name=excluded.item_name,storage_quantity=excluded.storage_quantity,ingredients_quantity=excluded.ingredients_quantity,counted_by=excluded.counted_by,counted_at=excluded.counted_at;
    n:=n+1;
  end loop;
  insert into public.inventory_submissions(session_id,staff_id,section,submitted_at) values(p_session_id,s.id,p_section,now());
  delete from public.inventory_drafts where session_id=p_session_id and staff_id=s.id and section=p_section;
  return jsonb_build_object('count',n,'done',true);
end $function$
;
alter function public.inventory_submit_final(p_token text, p_session_id uuid, p_section text, p_items jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.protect_shared_count_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$begin if old.shared_sheet_id is not null then raise exception 'Shared sheet counts cannot be partially deleted. Reopen the shared sheet for corrections; previous finals are retained.';end if;return old;end $function$
;
CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION goya_private.validate_shared_inventory_count()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if tg_op='UPDATE' and old.shared_sheet_id is not null and new.shared_sheet_id is distinct from old.shared_sheet_id then raise exception 'Shared sheet identity cannot be changed';end if;
 if exists(select 1 from public.inventory_sessions where id=new.session_id and shared_count) then
  if new.shared_sheet_id is null or not exists(select 1 from goya_private.inventory_shared_sheets h where h.id=new.shared_sheet_id and h.session_id=new.session_id and h.section=new.section) then raise exception 'Use the shared inventory sheet; personal copies are not allowed';end if;
 end if;return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.save_inventory_count(p_token text, p_session_id uuid, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; s public.staff; it jsonb; n int:=0; sec text;
begin
  if exists(select 1 from public.inventory_sessions where id=p_session_id and shared_count) then raise exception 'Shared count: refresh your Staff Portal to save safely';end if;
  sess:=public.require_session(p_token,false); select * into s from public.staff where id=sess.staff_id;
  if not exists(select 1 from public.inventory_sessions v where v.id=p_session_id and v.active and (
    s.id=any(v.assigned_staff_ids) or (coalesce(array_length(v.assigned_staff_ids,1),0)=0 and s.can_inventory and s.sections && v.sections)
  )) then raise exception 'Inventory session not assigned to this staff'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    sec:=trim(it->>'section');
    insert into public.inventory_counts(session_id,item_name,sku,section,storage_quantity,ingredients_quantity,counted_by,counted_at)
    values(p_session_id,trim(it->>'item_name'),trim(it->>'sku'),sec,nullif(it->>'storage_quantity','')::numeric,
      nullif(it->>'ingredients_quantity','')::numeric,s.name,now())
    on conflict(session_id,sku,section) do update set storage_quantity=excluded.storage_quantity,
      ingredients_quantity=excluded.ingredients_quantity,counted_by=excluded.counted_by,counted_at=excluded.counted_at;
    n:=n+1;
  end loop;
  return jsonb_build_object('count',n);
end;
$function$
;
alter function public.save_inventory_count(p_token text, p_session_id uuid, p_items jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_document_reserve_v2(p_token text, p_id uuid, p_category text, p_name text, p_type text, p_size integer, p_sha text, p_staff uuid, p_title text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := goya_private.document_staff(p_token,p_staff);
  folder text;
  version goya_private.staff_document_versions;
begin
  if p_category like 'custom-%' and p_staff is null then raise exception 'Unauthorized'; end if;
  select employee_code into folder from goya_private.staff_hr_profiles where staff_id=employee;
  if folder is null or folder !~ '^GY-[0-9]{3,}$' then
    folder := left(coalesce(nullif(regexp_replace(folder,'[^A-Za-z0-9_-]','-','g'),''),'Staff'),80)
      ||'--'||employee::text;
  end if;
  insert into goya_private.staff_document_versions(id,staff_id,category,file_name,mime_type,byte_size,sha256,folder_key,custom_title)
    values(p_id,employee,p_category,p_name,p_type,p_size,p_sha,folder,p_title)
    on conflict(id) do nothing;
  select * into version from goya_private.staff_document_versions where id=p_id and staff_id=employee;
  if not found or (version.category,version.file_name,version.mime_type,version.byte_size,version.sha256,version.custom_title)
    is distinct from (p_category,p_name,p_type,p_size,p_sha,p_title) then
    raise exception 'Upload ID already used';
  end if;
  return jsonb_build_object('folder',version.folder_key,'complete',version.uploaded_at is not null);
end $function$
;
alter function public.goya_hr_document_reserve_v2(p_token text, p_id uuid, p_category text, p_name text, p_type text, p_size integer, p_sha text, p_staff uuid, p_title text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_bootstrap(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions;s public.staff;
begin
  sess:=public.require_session(p_token,false);select * into s from public.staff where id=sess.staff_id;
  return jsonb_build_object(
    'master_items',(select coalesce(jsonb_agg(to_jsonb(x) order by lower(x.name)),'[]'::jsonb) from public.master_items x where x.active=true),
    'internal_items',(select coalesce(jsonb_agg(to_jsonb(x) order by lower(x.name)),'[]'::jsonb) from public.internal_items x where x.active=true),
    'suppliers',(select coalesce(jsonb_agg(to_jsonb(x) order by lower(x.name)),'[]'::jsonb) from public.suppliers x where x.active=true),
    'info_pages',(select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.title),'[]'::jsonb) from public.info_pages x where x.active=true),
    'inventory_sessions',(select coalesce(jsonb_agg(to_jsonb(v) order by v.month desc),'[]'::jsonb) from public.inventory_sessions v where v.active=true and s.sections && v.sections and (s.id=any(v.assigned_staff_ids) or (coalesce(array_length(v.assigned_staff_ids,1),0)=0 and s.can_inventory)))
  );
end $function$
;
alter function public.staff_bootstrap(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_recalc(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r public.attendance_records;
  s public.attendance_staff;
  rules jsonb;
  shifts jsonb;
  sh text;
  grace int:=15;
  punch_min int;
  sh_min int;
  best_min int:=null;
  best_dist int:=null;
  dist int;
  calculated_late int:=0;
  st timestamp;
  effective_in timestamp;
  out1 timestamp;
  out2 timestamp;
  presence1 int:=0;
  presence2 int:=0;
  total_presence int:=0;
  netv int:=0;
  exp_net int:=0;
  cutoff_min int:=120;
begin
  select * into r from public.attendance_records where id=p_id;
  if r.id is null then return; end if;
  select * into s from public.attendance_staff where id=r.attendance_staff_id;
  select coalesce(value,'{}'::jsonb) into rules from public.attendance_settings where key='rules';

  grace:=coalesce((rules->>'late_grace_minutes')::int,15);
  cutoff_min:=coalesce(
    split_part(coalesce(rules->>'operational_cutoff','02:00'),':',1)::int*60 +
    split_part(coalesce(rules->>'operational_cutoff','02:00'),':',2)::int,
    120
  );
  r.expected_presence_minutes:=coalesce(r.expected_presence_minutes,s.expected_presence_minutes,(rules->>'default_presence_minutes')::int,540);
  r.break_minutes:=coalesce(r.break_minutes,s.default_break_minutes,(rules->>'default_break_minutes')::int,60);
  shifts:=coalesce(rules->'shift_start_times',jsonb_build_array('08:00','09:00','10:00','11:00','12:00','13:00','14:00','15:00','16:00','17:00'));

  if r.punch_in is not null then
    punch_min:=extract(hour from r.punch_in)::int*60 + extract(minute from r.punch_in)::int;
    for sh in select jsonb_array_elements_text(shifts) loop
      begin
        sh_min:=split_part(sh,':',1)::int*60 + split_part(sh,':',2)::int;
        dist:=abs(punch_min-sh_min);
        if best_dist is null or dist<best_dist or (dist=best_dist and sh_min>best_min) then
          best_dist:=dist;
          best_min:=sh_min;
        end if;
      exception when others then null;
      end;
    end loop;

    if best_min is not null then
      st:=r.operational_date::timestamp + make_interval(mins=>best_min);
      r.scheduled_start:=st::time;
      if punch_min-best_min>grace then calculated_late:=punch_min-best_min; end if;
    end if;
  end if;

  effective_in:=r.punch_in;
  if effective_in is not null and st is not null and effective_in<st then effective_in:=st; end if;

  out1:=r.punch_out;
  if effective_in is not null and out1 is not null and out1<=effective_in then
    -- Safe legacy/manual overnight correction only when OUT clock is inside the next-day cutoff window.
    if (extract(hour from out1)::int*60 + extract(minute from out1)::int)<=cutoff_min then
      out1:=out1+interval '1 day';
    end if;
  end if;
  if effective_in is not null and out1 is not null then
    presence1:=greatest(0,floor(extract(epoch from (out1-effective_in))/60)::int);
  end if;

  if coalesce(r.split_shift,false) and r.shift2_in is not null and r.shift2_out is not null then
    out2:=r.shift2_out;
    if out2<=r.shift2_in and (extract(hour from out2)::int*60 + extract(minute from out2)::int)<=cutoff_min then
      out2:=out2+interval '1 day';
    end if;
    presence2:=greatest(0,floor(extract(epoch from (out2-r.shift2_in))/60)::int);
  end if;

  total_presence:=presence1+presence2;
  netv:=greatest(0,total_presence-case when r.break_taken then r.break_minutes else 0 end);
  exp_net:=greatest(0,r.expected_presence_minutes-r.break_minutes);

  update public.attendance_records set
    scheduled_start=r.scheduled_start,
    expected_presence_minutes=r.expected_presence_minutes,
    break_minutes=r.break_minutes,
    late_minutes=calculated_late,
    presence_minutes=total_presence,
    net_work_minutes=netv,
    additional_minutes=greatest(0,netv-exp_net),
    updated_at=now()
  where id=p_id;
end $function$
;
alter function public.attendance_recalc(p_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.logout(p_token text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin delete from public.app_sessions where token=p_token; return true; end;
$function$
;
alter function public.logout(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.capture_ot_policy()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare effective date:=nullif(public.attendance_live_rules()->>'ot_policy_effective_date','')::date;
begin
 if effective is null or new.operational_date<effective then return new;end if;
 if new.ot_policy is null then
  if tg_op='INSERT' or exists(select 1 from public.attendance_live_sessions s where s.staff_id=new.staff_id and s.operational_date=new.operational_date and s.check_out_at is null and not coalesce(s.is_deleted,false)) then new.ot_policy:=goya_private.current_ot_policy();end if;
 elsif exists(select 1 from public.attendance_live_sessions s where s.staff_id=new.staff_id and s.operational_date=new.operational_date and s.check_out_at is null and not coalesce(s.is_deleted,false)) then
  new.ot_policy:=new.ot_policy||jsonb_build_object('enabled',coalesce((public.attendance_live_rules()->>'overtime_enabled')::boolean,true));
 end if;
 return new;
end $function$
;
alter function goya_private.capture_ot_policy() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_document_complete_v2(p_token text, p_id uuid, p_drive text, p_staff uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := goya_private.document_staff(p_token,p_staff);
begin
  perform 1 from public.staff where id=employee and (active or p_staff is not null) for update;
  if not found then raise exception 'Unauthorized'; end if;
  update goya_private.staff_document_versions
    set drive_file_id=p_drive,uploaded_at=coalesce(uploaded_at,clock_timestamp())
    where id=p_id and staff_id=employee and (drive_file_id is null or drive_file_id=p_drive)
      and p_drive is not null;
  if not found then raise exception 'Upload is unavailable'; end if;
end $function$
;
alter function public.goya_hr_document_complete_v2(p_token text, p_id uuid, p_drive text, p_staff uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_live_attendance_set_break(p_token text, p_break_taken boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  open_row public.attendance_live_sessions;
  target_date date;
begin
  sess := public.require_session(p_token,false);

  select * into open_row
    from public.attendance_live_sessions
   where staff_id=sess.staff_id
     and check_out_at is null
     and coalesce(is_deleted,false)=false
   order by check_in_at desc
   limit 1;

  target_date := coalesce(open_row.operational_date,public.attendance_live_operational_date(now()));

  update public.attendance_live_days
     set break_taken=coalesce(p_break_taken,true),updated_at=now()
   where staff_id=sess.staff_id
     and operational_date=target_date
     and coalesce(is_deleted,false)=false;

  return found;
end;
$function$
;
alter function public.staff_live_attendance_set_break(p_token text, p_break_taken boolean) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.current_ot_policy()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select jsonb_build_object('version',1,'enabled',coalesce((r->>'overtime_enabled')::boolean,true),'grace_minutes',30,'early_grace_minutes',30,'regular_minutes',coalesce((r->>'regular_net_minutes')::int,480),'break_minutes',coalesce((r->>'break_minutes')::int,60)) from (select public.attendance_live_rules() r)q;
$function$
;
alter function goya_private.current_ot_policy() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_public_dashboard(p_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  d date:=coalesce(p_date,public.attendance_live_operational_date(now()));
  rules jsonb:=public.attendance_live_rules();
begin
  return jsonb_build_object(
    'server_now',now(),
    'operational_date',d,
    'rules',jsonb_build_object(
      'duty_presence_minutes',coalesce((rules->>'duty_presence_minutes')::int,540),
      'regular_net_minutes',coalesce((rules->>'regular_net_minutes')::int,480),
      'break_minutes',coalesce((rules->>'break_minutes')::int,60),
      'timezone',coalesce(rules->>'timezone','Asia/Dubai')
    ),
    'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name)
                      from goya_private.branch_staff_history s where s.active=true and goya_private.employed_on(s.id,d) and goya_private.branch_employee_on(s.id,d)),'[]'::jsonb),
    'days',coalesce((select jsonb_agg(jsonb_build_object(
                       'staff_id',x.staff_id,'operational_date',x.operational_date,
                       'break_taken',x.break_taken,'classification',x.classification,
                       'ot_policy',x.ot_policy,'scheduled_start',x.scheduled_start,'late_minutes',x.late_minutes))
                      from public.attendance_live_days x
                      where x.operational_date=d and goya_private.employed_on(x.staff_id,d) and coalesce(x.is_deleted,false)=false),'[]'::jsonb),
    'sessions',coalesce((select jsonb_agg(jsonb_build_object(
                           'id',x.id,'staff_id',x.staff_id,'operational_date',x.operational_date,
                           'session_no',x.session_no,'check_in_at',x.check_in_at,'check_out_at',x.check_out_at,
                           'check_in_verified',x.check_in_verified,'check_out_verified',x.check_out_verified)
                         order by x.staff_id,x.session_no)
                        from public.attendance_live_sessions x
                        where x.operational_date=d and goya_private.employed_on(x.staff_id,d) and coalesce(x.is_deleted,false)=false),'[]'::jsonb)
  );
end $function$
;
alter function public.attendance_live_public_dashboard(p_date date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_operational_date(p_ts timestamp with time zone DEFAULT now())
 RETURNS date
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rules jsonb:=public.attendance_live_rules();
  tz text:=coalesce(rules->>'timezone','Asia/Dubai');
  cutoff time:=coalesce((rules->>'operational_cutoff')::time,'02:00'::time);
  lt timestamp;
begin
  lt:=timezone(tz,p_ts);
  if lt::time<=cutoff then return lt::date-1; end if;
  return lt::date;
end $function$
;
alter function public.attendance_live_operational_date(p_ts timestamp with time zone) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_settings(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin
  perform public.require_session(p_token,true); return public.attendance_live_rules(); end $function$
;
alter function public.attendance_live_admin_settings(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_rules()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    coalesce((select value from public.attendance_settings where key='live_rules'),'{}'::jsonb)
    || case
         when exists(
           select 1
           from public.attendance_settings a
           where a.key='rules'
             and jsonb_typeof(a.value)='object'
             and (a.value->>'operational_cutoff') ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
         ) then jsonb_build_object(
           'operational_cutoff',
           (select a.value->>'operational_cutoff'
              from public.attendance_settings a
             where a.key='rules'
             limit 1)
         )
         else '{}'::jsonb
       end;
$function$
;
alter function public.attendance_live_rules() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_week_leave(p_token text, p_week date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.require_session(p_token,true);
  return coalesce((select jsonb_agg(jsonb_build_object('id',id,'staff_id',staff_id,'kind',case when kind in ('Pending Off','Advance Off') then 'Weekly Off' when kind='Emergency Leave' then 'Other Leave' else kind end,
    'from',approved_from,'to',approved_to,'paid_request',kind in ('Pending Off','Advance Off')))
    from goya_private.staff_leave_requests where kind<>'Resignation' and state='Approved' and approved_from<=p_week+6 and approved_to>=p_week),'[]'::jsonb);
end $function$
;
alter function public.goya_hr_week_leave(p_token text, p_week date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_verify_workplace(p_lat double precision, p_lon double precision, p_public_ip text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rules jsonb:=public.attendance_live_rules();
  require_location boolean:=coalesce((rules->>'require_location')::boolean,true);
  require_network boolean:=coalesce((rules->>'require_network')::boolean,true);
  loc jsonb;
  ips jsonb:=coalesce(rules->'approved_public_ips','[]'::jsonb);
  locations jsonb:=coalesce(rules->'locations','[]'::jsonb);
  lat2 double precision;
  lon2 double precision;
  radius_m double precision;
  dist_m double precision;
  best_dist double precision:=null;
  best_name text:=null;
  location_ok boolean:=false;
  network_ok boolean:=false;
begin
  if jsonb_array_length(ips)>0 and nullif(trim(coalesce(p_public_ip,'')),'') is not null then
    select exists(select 1 from jsonb_array_elements_text(ips) x where trim(x)=trim(p_public_ip)) into network_ok;
  end if;

  if jsonb_array_length(locations)>0 and p_lat is not null and p_lon is not null then
    for loc in select * from jsonb_array_elements(locations) loop
      if coalesce((loc->>'active')::boolean,true) then
        begin
          lat2:=(loc->>'lat')::double precision;
          lon2:=(loc->>'lon')::double precision;
          radius_m:=coalesce((loc->>'radius_m')::double precision,150);
          dist_m:=6371000 * 2 * asin(sqrt(least(1.0,
            power(sin(radians(lat2-p_lat)/2),2) +
            cos(radians(p_lat))*cos(radians(lat2))*power(sin(radians(lon2-p_lon)/2),2)
          )));
          if best_dist is null or dist_m<best_dist then
            best_dist:=dist_m;
            best_name:=coalesce(nullif(loc->>'name',''),'Workplace');
          end if;
          if dist_m<=radius_m then location_ok:=true; end if;
        exception when others then null;
        end;
      end if;
    end loop;
  end if;

  if require_location and jsonb_array_length(locations)=0 then
    return jsonb_build_object('ok',false,'location_ok',false,'network_ok',network_ok,'reason','No approved workplace location is configured in Attendance Settings.');
  end if;
  if require_network and jsonb_array_length(ips)=0 then
    return jsonb_build_object('ok',false,'location_ok',location_ok,'network_ok',false,'reason','No approved office public IP/network is configured in Attendance Settings.');
  end if;
  if require_location and not location_ok then
    return jsonb_build_object('ok',false,'location_ok',false,'network_ok',network_ok,'location_name',best_name,'distance_m',best_dist,'reason','You are outside the approved workplace GPS radius.');
  end if;
  if require_network and not network_ok then
    return jsonb_build_object('ok',false,'location_ok',location_ok,'network_ok',false,'location_name',best_name,'distance_m',best_dist,'reason','Your current public network IP is not approved. Connect to the approved office network.');
  end if;

  return jsonb_build_object(
    'ok',true,
    'location_ok',case when require_location then location_ok else true end,
    'network_ok',case when require_network then network_ok else true end,
    'location_name',best_name,
    'distance_m',best_dist,
    'public_ip',p_public_ip
  );
end $function$
;
alter function public.attendance_live_verify_workplace(p_lat double precision, p_lon double precision, p_public_ip text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_shift_info(p_ts timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rules jsonb:=public.attendance_live_rules();
  tz text:=coalesce(rules->>'timezone','Asia/Dubai');
  grace int:=coalesce((rules->>'late_grace_minutes')::int,15);
  shifts jsonb:=coalesce(rules->'shift_start_times',jsonb_build_array('08:00','09:00','10:00','11:00','12:00','13:00','14:00','15:00','16:00','17:00'));
  lt timestamp:=timezone(tz,p_ts);
  pm int:=extract(hour from lt)::int*60+extract(minute from lt)::int;
  sh text; sm int; dist int; best int:=null; best_dist int:=null; last_shift int:=null; late int:=0;
begin
  for sh in select jsonb_array_elements_text(shifts) loop
    begin
      sm:=split_part(sh,':',1)::int*60+split_part(sh,':',2)::int;
      if last_shift is null or sm>last_shift then last_shift:=sm; end if;
      dist:=abs(pm-sm);
      if best_dist is null or dist<best_dist or (dist=best_dist and sm>best) then best:=sm; best_dist:=dist; end if;
    exception when others then null;
    end;
  end loop;
  if best is null then return jsonb_build_object('scheduled_start',null,'late_minutes',0,'timing_review',true); end if;
  if last_shift is not null and pm>last_shift+60 then
    return jsonb_build_object('scheduled_start',null,'late_minutes',0,'timing_review',true);
  end if;
  if pm-best>grace then late:=pm-best; end if;
  return jsonb_build_object(
    'scheduled_start',lpad((best/60)::text,2,'0')||':'||lpad((best%60)::text,2,'0'),
    'late_minutes',late,
    'timing_review',false
  );
end $function$
;
alter function public.attendance_live_shift_info(p_ts timestamp with time zone) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_update_session(p_token text, p_session_id uuid, p_check_in timestamp with time zone, p_check_out timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  oldv jsonb;
  oldr public.attendance_live_sessions;
  r public.attendance_live_sessions;
  old_date date;
  new_date date;
  new_no int;
begin
  perform public.require_session(p_token,true);
  select * into oldr from public.attendance_live_sessions where id=p_session_id and coalesce(is_deleted,false)=false;
  if oldr.id is null then raise exception 'Live attendance session not found'; end if;
  oldv:=to_jsonb(oldr);
  if p_check_in is null then raise exception 'Check In is required'; end if;
  if p_check_out is not null and p_check_out<=p_check_in then raise exception 'Check Out must be after Check In'; end if;

  old_date:=oldr.operational_date;
  new_date:=public.attendance_live_operational_date(p_check_in);
  if new_date<>old_date then
    select coalesce(max(session_no),0)+1 into new_no
    from public.attendance_live_sessions
    where staff_id=oldr.staff_id and operational_date=new_date and coalesce(is_deleted,false)=false and id<>p_session_id;
  else
    new_no:=oldr.session_no;
  end if;

  update public.attendance_live_sessions
     set operational_date=new_date,
         session_no=new_no,
         check_in_at=p_check_in,
         check_out_at=p_check_out,
         check_in_verified=true,
         check_out_verified=case when p_check_out is null then null else true end,
         updated_at=now()
   where id=p_session_id
   returning * into r;

  perform public.attendance_live_recalculate_day_internal(r.staff_id,new_date);
  if old_date<>new_date then perform public.attendance_live_recalculate_day_internal(r.staff_id,old_date); end if;

  insert into public.attendance_live_audit(staff_id,operational_date,session_id,actor_type,action,before_data,after_data)
  values(r.staff_id,new_date,r.id,'admin','EDIT_SESSION',oldv,to_jsonb(r));
  return to_jsonb(r);
end $function$
;
alter function public.attendance_live_admin_update_session(p_token text, p_session_id uuid, p_check_in timestamp with time zone, p_check_out timestamp with time zone) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_audit(p_token text, p_staff_id uuid DEFAULT NULL::uuid, p_start date DEFAULT NULL::date, p_end date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin
  perform public.require_session(p_token,true);
  return coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.attendance_live_audit a
    where (p_staff_id is null or a.staff_id=p_staff_id)
      and (p_start is null or a.operational_date>=p_start)
      and (p_end is null or a.operational_date<=p_end)),'[]'::jsonb);
end $function$
;
alter function public.attendance_live_admin_audit(p_token text, p_staff_id uuid, p_start date, p_end date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_save_settings(p_token text, p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare oldv jsonb:=public.attendance_live_rules(); newv jsonb; begin
  perform public.require_session(p_token,true);
  if p_value ? 'overtime_enabled' and jsonb_typeof(p_value->'overtime_enabled')<>'boolean' then raise exception 'Overtime enabled must be true or false';end if;
  newv:=oldv || coalesce(p_value,'{}'::jsonb);
  if coalesce((newv->>'duty_presence_minutes')::int,540)<60 then raise exception 'Duty minutes are invalid'; end if;
  if coalesce((newv->>'regular_net_minutes')::int,480)<60 then raise exception 'Regular net minutes are invalid'; end if;
  insert into public.attendance_settings(key,value,updated_at) values('live_rules',newv,now())
  on conflict(branch_id,key) do update set value=excluded.value,updated_at=now();
  insert into public.attendance_live_audit(actor_type,action,before_data,after_data) values('admin','UPDATE_LIVE_SETTINGS',oldv,newv);
  if (oldv->>'overtime_enabled') is distinct from (newv->>'overtime_enabled') then
   update public.attendance_live_days d set ot_policy=d.ot_policy||jsonb_build_object('enabled',coalesce((newv->>'overtime_enabled')::boolean,true))
    where d.ot_policy is not null and not coalesce(d.is_deleted,false) and exists(select 1 from public.attendance_live_sessions s where s.staff_id=d.staff_id and s.operational_date=d.operational_date and s.check_out_at is null and not coalesce(s.is_deleted,false));
  end if;
  return newv;
end $function$
;
alter function public.attendance_live_admin_save_settings(p_token text, p_value jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_complaints(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.require_session(p_token,true);
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.complaint_feedback x),'[]'::jsonb);
end;
$function$
;
alter function public.admin_complaints(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_manual_action(p_token text, p_staff_id uuid, p_action text, p_at timestamp with time zone, p_break_taken boolean DEFAULT true, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s public.staff; od date; action_name text:=upper(trim(coalesce(p_action,''))); active_count int:=0; next_no int:=1;
  r public.attendance_live_sessions; open_row public.attendance_live_sessions; d public.attendance_live_days; sh jsonb; before_row jsonb;
begin
  perform public.require_session(p_token,true);
  if p_at is null then raise exception 'Attendance date/time is required'; end if;
  select * into s from public.staff where id=p_staff_id;
  if s.id is null then raise exception 'Staff record not found'; end if;
  od:=public.attendance_live_operational_date(p_at);
  perform pg_advisory_xact_lock(hashtext(s.id::text));

  if action_name in ('CHECK_IN','REJOIN') and not goya_private.employed_on(s.id,od) then raise exception 'The day is outside employment dates'; end if;
  if action_name in ('CHECK_IN','REJOIN') then
    select * into open_row from public.attendance_live_sessions
      where staff_id=s.id and check_out_at is null and coalesce(is_deleted,false)=false order by check_in_at desc limit 1;
    if open_row.id is not null then raise exception 'Staff is already checked in'; end if;
    select count(*) into active_count from public.attendance_live_sessions
      where staff_id=s.id and operational_date=od and coalesce(is_deleted,false)=false;
    if action_name='REJOIN' and active_count=0 then raise exception 'No earlier session exists for Rejoin'; end if;
    if action_name='CHECK_IN' and active_count>0 then raise exception 'A session already exists for this operational day. Use Rejoin.'; end if;
    select coalesce(max(session_no),0)+1 into next_no from public.attendance_live_sessions where staff_id=s.id and operational_date=od;
    sh:=public.attendance_live_shift_info(p_at);
    insert into public.attendance_live_sessions(staff_id,operational_date,session_no,check_in_at,check_in_location_name,check_in_verified,is_deleted)
    values(s.id,od,next_no,p_at,'Admin',true,false) returning * into r;
    insert into public.attendance_live_days(staff_id,operational_date,break_taken,classification,scheduled_start,late_minutes,classification_note,is_deleted,deleted_at,deleted_reason)
    values(s.id,od,coalesce(p_break_taken,true),'Duty',nullif(sh->>'scheduled_start','')::time,case when active_count=0 then coalesce((sh->>'late_minutes')::int,0) else 0 end,nullif(trim(coalesce(p_note,'')),''),false,null,null)
    on conflict(branch_id,staff_id,operational_date) do update set
      break_taken=excluded.break_taken,classification='Duty',is_deleted=false,deleted_at=null,deleted_reason=null,
      classification_note=coalesce(excluded.classification_note,public.attendance_live_days.classification_note),updated_at=now()
    returning * into d;
    perform public.attendance_live_recalculate_day_internal(s.id,od);
    select * into d from public.attendance_live_days where staff_id=s.id and operational_date=od;
    insert into public.attendance_live_audit(staff_id,operational_date,session_id,actor_type,action,after_data)
    values(s.id,od,r.id,'admin','MANUAL_'||action_name,jsonb_build_object('session',to_jsonb(r),'break_taken',p_break_taken,'note',p_note));

  elsif action_name='CHECK_OUT' then
    select * into open_row from public.attendance_live_sessions
      where staff_id=s.id and operational_date=od and check_out_at is null and coalesce(is_deleted,false)=false
      order by check_in_at desc limit 1;
    if open_row.id is null then raise exception 'No active Check In found for this staff on the selected date'; end if;
    if p_at<=open_row.check_in_at then raise exception 'Check Out must be after Check In'; end if;
    before_row:=to_jsonb(open_row);
    update public.attendance_live_sessions set
      check_out_at=p_at,check_out_location_name='Admin',check_out_verified=true,updated_at=now()
      where id=open_row.id returning * into r;
    update public.attendance_live_days set
      break_taken=coalesce(p_break_taken,true),classification='Duty',is_deleted=false,deleted_at=null,deleted_reason=null,
      classification_note=coalesce(nullif(trim(coalesce(p_note,'')),''),classification_note),updated_at=now()
      where staff_id=s.id and operational_date=od returning * into d;
    perform public.attendance_live_recalculate_day_internal(s.id,od);
    select * into d from public.attendance_live_days where staff_id=s.id and operational_date=od;
    insert into public.attendance_live_audit(staff_id,operational_date,session_id,actor_type,action,before_data,after_data)
    values(s.id,od,r.id,'admin','MANUAL_CHECK_OUT',before_row,jsonb_build_object('session',to_jsonb(r),'break_taken',p_break_taken,'note',p_note));
  else
    raise exception 'Invalid manual attendance action';
  end if;

  return jsonb_build_object('ok',true,'action',action_name,'session',to_jsonb(r),'day',to_jsonb(d),'server_now',now());
end $function$
;
alter function public.attendance_live_admin_manual_action(p_token text, p_staff_id uuid, p_action text, p_at timestamp with time zone, p_break_taken boolean, p_note text) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.capture_admin_submission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if tg_table_name='orders' then
  insert into goya_private.admin_notifications(kind,event_key,source_ref,staff_name)
  select 'orders',order_group_id::text,jsonb_build_object('group_id',order_group_id),min(coalesce(logged_by,'Staff')) from inserted_rows where order_group_id is not null group by order_group_id on conflict do nothing;
 elsif tg_table_name='production_batches' then
  insert into goya_private.admin_notifications(kind,event_key,source_ref,staff_name)
  select 'production',batch_group_id::text,jsonb_build_object('group_id',batch_group_id),min(coalesce(logged_by,'Staff')) from inserted_rows where batch_group_id is not null group by batch_group_id on conflict do nothing;
 elsif tg_table_name='wastage_entries' then
  insert into goya_private.admin_notifications(kind,event_key,source_ref,staff_name)
  select 'wastage',wastage_group_id::text,jsonb_build_object('group_id',wastage_group_id),min(coalesce(logged_by,'Staff')) from inserted_rows where wastage_group_id is not null group by wastage_group_id on conflict do nothing;
 elsif tg_table_name='complaint_feedback' then
  insert into goya_private.admin_notifications(kind,event_key,source_ref,staff_name)
  select 'feedback',id::text,jsonb_build_object('id',id),case when hide_identity then 'Anonymous' else coalesce(staff_name,'Staff') end from inserted_rows on conflict do nothing;
 elsif tg_table_name='inventory_submissions' then
  insert into goya_private.admin_notifications(kind,event_key,source_ref,staff_name)
  select 'inventory',jsonb_build_array(i.session_id,i.staff_id,i.section,i.submitted_at)::text,jsonb_build_object('session_id',i.session_id,'staff_id',i.staff_id,'section',i.section),coalesce(s.name,'Staff') from inserted_rows i left join public.staff s on s.id=i.staff_id on conflict do nothing;
 elsif tg_table_name='inventory_shared_finals' then
  insert into goya_private.admin_notifications(kind,event_key,source_ref,staff_name)
  select 'inventory_shared',id::text,jsonb_build_object('id',id,'sheet_id',sheet_id),coalesce(submitted_name,'Staff') from inserted_rows on conflict do nothing;
 elsif tg_table_name='equipment_reports' then
  insert into goya_private.admin_notifications(kind,event_key,source_ref,staff_name)
  select 'equipment',id::text,jsonb_build_object('id',id),staff_name from inserted_rows on conflict do nothing;
 end if;
 -- Only notification pointers expire. Equipment and all source records are retained.
 delete from goya_private.admin_notifications where created_at<now()-interval '90 days';
 return null;
end $function$
;
alter function goya_private.capture_admin_submission() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_delete_item(p_token text, p_table text, p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform public.require_session(p_token,true);if p_table='master_items' then delete from public.master_items where id=p_id;elsif p_table='internal_items' then delete from public.internal_items where id=p_id;else raise exception 'Invalid table';end if;return true;end $function$
;
alter function public.admin_delete_item(p_token text, p_table text, p_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_delete_day(p_token text, p_staff_id uuid, p_date date, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  before_day jsonb;
  before_sessions jsonb;
  d public.attendance_live_days;
begin
  perform public.require_session(p_token,true);
  if p_staff_id is null or p_date is null then raise exception 'Staff and date are required'; end if;
  if not exists(select 1 from public.staff where id=p_staff_id) then raise exception 'Staff record not found'; end if;

  select to_jsonb(x) into before_day from public.attendance_live_days x
   where x.staff_id=p_staff_id and x.operational_date=p_date;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.session_no),'[]'::jsonb) into before_sessions
    from public.attendance_live_sessions x
   where x.staff_id=p_staff_id and x.operational_date=p_date and coalesce(x.is_deleted,false)=false;

  insert into public.attendance_live_days(staff_id,operational_date,classification,is_deleted,deleted_at,deleted_reason)
  values(p_staff_id,p_date,'Day Off - Pending Review',true,now(),nullif(trim(coalesce(p_reason,'')),''))
  on conflict(branch_id,staff_id,operational_date) do update set
    is_deleted=true,
    deleted_at=now(),
    deleted_reason=nullif(trim(coalesce(p_reason,'')),''),
    updated_at=now()
  returning * into d;

  update public.attendance_live_sessions
     set is_deleted=true,deleted_at=now(),deleted_reason=nullif(trim(coalesce(p_reason,'')),''),updated_at=now()
   where staff_id=p_staff_id and operational_date=p_date and coalesce(is_deleted,false)=false;

  insert into public.attendance_live_audit(staff_id,operational_date,actor_type,action,before_data,after_data)
  values(p_staff_id,p_date,'admin','ARCHIVE_LIVE_ATTENDANCE_DAY',
    jsonb_build_object('day',before_day,'sessions',before_sessions),
    jsonb_build_object('is_deleted',true,'deleted_at',now(),'reason',p_reason));

  return jsonb_build_object('ok',true,'staff_id',p_staff_id,'operational_date',p_date,'archived',true,'server_now',now());
end $function$
;
alter function public.attendance_live_admin_delete_day(p_token text, p_staff_id uuid, p_date date, p_reason text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_update_orders(p_token text, p_ids bigint[], p_status text, p_notes text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer;
begin
  perform public.require_session(p_token,true);
  update public.orders
  set status=p_status, notes=coalesce(p_notes,notes)
  where id=any(p_ids);
  get diagnostics n=row_count;
  return n;
end;
$function$
;
alter function public.admin_update_orders(p_token text, p_ids bigint[], p_status text, p_notes text) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.staff_notice_off(r goya_private.off_balance_events)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 perform goya_private.staff_notice_emit(r.staff_id,'off:'||r.id,'balance',case when r.delta>0 then '+' else '' end||r.delta||' Paid Off day(s)',
 r.notice||E'\nBalance after update: '||r.balance_after||E'\nManagement',jsonb_build_object('view','balance','id',r.id),r.created_at);
end $function$
;
alter function goya_private.staff_notice_off(r goya_private.off_balance_events) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.staff_notice_day(d jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select case when d is null or d='null'::jsonb then 'Not scheduled'
 when d->>'off_source'='advance' then 'Advance Off' when d ? 'off_source' then 'Paid Off'
 when d->>'kind'='Shift' then coalesce(nullif(d->>'label','')||' | ','')||coalesce((select string_agg(s->>'start'||'–'||(s->>'end')||case when s->>'end'<s->>'start' then ' (+1 day)' else '' end,' / ' order by i) from jsonb_array_elements(d->'segments') with ordinality t(s,i)),'Shift')
 else coalesce(d->>'kind','Not scheduled') end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_delete_orders(p_token text, p_ids bigint[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer;
begin
  perform public.require_session(p_token,true);
  delete from public.orders where id=any(p_ids);
  get diagnostics n=row_count;
  return n;
end;
$function$
;
alter function public.admin_delete_orders(p_token text, p_ids bigint[]) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.set_received_date()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.status='Received' and old.status is distinct from new.status then new.received_date=current_date;
  elsif new.status<>'Received' then new.received_date=null; end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION goya_private.staff_notice_emit(employee uuid, event_key text, kind text, title text, body text, target jsonb, at_time timestamp with time zone DEFAULT clock_timestamp())
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 insert into goya_private.staff_notifications(staff_id,event_key,kind,title,body,target,created_at)
 select employee,event_key,kind,left(title,250),left(body,4000),target,at_time
 where exists(select 1 from public.staff where id=employee)
 and not exists(select 1 from goya_private.staff_notifications n where n.staff_id=$1 and n.event_key=$2)
 on conflict(staff_id,event_key) do nothing;
$function$
;
alter function goya_private.staff_notice_emit(employee uuid, event_key text, kind text, title text, body text, target jsonb, at_time timestamp with time zone) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_dashboard(p_token text, p_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d date:=coalesce(p_date,public.attendance_live_operational_date(now())); begin
  perform public.require_session(p_token,true);
  return jsonb_build_object(
    'server_now',now(),'operational_date',d,'rules',public.attendance_live_rules(),
    'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'sections',s.sections,'active',s.active) order by s.name) from goya_private.branch_staff_history s where s.active=true and goya_private.employed_on(s.id,d) and goya_private.branch_employee_on(s.id,d)),'[]'::jsonb),
    'days',coalesce((select jsonb_agg(to_jsonb(x)) from public.attendance_live_days x where x.operational_date=d and goya_private.employed_on(x.staff_id,d) and coalesce(x.is_deleted,false)=false),'[]'::jsonb),
    'sessions',coalesce((select jsonb_agg(to_jsonb(x) order by x.staff_id,x.session_no) from public.attendance_live_sessions x where x.operational_date=d and goya_private.employed_on(x.staff_id,d) and coalesce(x.is_deleted,false)=false),'[]'::jsonb)
  );
end $function$
;
alter function public.attendance_live_admin_dashboard(p_token text, p_date date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_save_settings(p_token text, p_settings jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k text; v jsonb;
begin
 perform public.require_session(p_token,true);
 for k,v in select key,value from jsonb_each(p_settings) loop
   insert into public.settings(key,value,updated_at) values(k,v,now())
   on conflict(branch_id,key) do update set value=excluded.value,updated_at=now();
 end loop;
 return true;
end; $function$
;
alter function public.admin_save_settings(p_token text, p_settings jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_delete_info_page(p_token text, p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin perform public.require_session(p_token,true); delete from public.info_pages where id=p_id; return true; end; $function$
;
alter function public.admin_delete_info_page(p_token text, p_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_delete_staff(p_token text, p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform public.require_session(p_token,true); delete from public.staff where id=p_id; return true; end;
$function$
;
alter function public.admin_delete_staff(p_token text, p_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_notification_count(p_token text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin perform public.require_session(p_token,true);return (select count(*) from goya_private.admin_notifications where read_at is null and created_at>=now()-interval '90 days');end $function$
;
alter function public.goya_admin_notification_count(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_notifications_read(p_token text, p_through bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin perform public.require_session(p_token,true);update goya_private.admin_notifications set read_at=now() where id<=p_through and read_at is null;end $function$
;
alter function public.goya_admin_notifications_read(p_token text, p_through bigint) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_roster_push_claim()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with jobs as (
    select d.week_start,d.revision,d.subscription_id,p.subscription
    from goya_private.roster_push_deliveries d
    join goya_private.push_subscriptions p on p.id=d.subscription_id and p.staff_id=d.staff_id and p.active
    join goya_private.branch_staff s on s.id=d.staff_id and s.active
    join goya_private.roster_weeks w on w.week_start=d.week_start and w.published_revision=d.revision
    where d.sent_at is null and d.attempts<3 and d.created_at>now()-interval '1 day'
      and (d.claimed_at is null or d.claimed_at<now()-interval '3 minutes')
    order by d.created_at for update of d skip locked limit 30
  ), claimed as (
    update goya_private.roster_push_deliveries d set claimed_at=now(),attempts=attempts+1 from jobs j
    where (d.week_start,d.revision,d.subscription_id)=(j.week_start,j.revision,j.subscription_id)
    returning j.*
  ) select coalesce(jsonb_agg(to_jsonb(claimed)),'[]'::jsonb) from claimed;
$function$
;
alter function public.goya_roster_push_claim() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_roster_push_check(p_week date, p_revision integer, p_subscription uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(select 1 from goya_private.roster_push_deliveries d
    join goya_private.push_subscriptions p on p.id=d.subscription_id and p.staff_id=d.staff_id and p.active
    join goya_private.branch_staff s on s.id=d.staff_id and s.active
    join goya_private.roster_weeks w on w.week_start=d.week_start and w.published_revision=d.revision
    where (d.week_start,d.revision,d.subscription_id)=(p_week,p_revision,p_subscription) and d.sent_at is null);
$function$
;
alter function public.goya_roster_push_check(p_week date, p_revision integer, p_subscription uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_roster_push_result(p_week date, p_revision integer, p_subscription uuid, p_sent boolean, p_expired boolean)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  update goya_private.roster_push_deliveries set sent_at=case when p_sent then now() else sent_at end,
    attempts=case when p_expired then 3 else attempts end
    where (week_start,revision,subscription_id)=(p_week,p_revision,p_subscription);
$function$
;
alter function public.goya_roster_push_result(p_week date, p_revision integer, p_subscription uuid, p_sent boolean, p_expired boolean) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_recalculate_day_internal(p_staff_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  first_in timestamptz;
  sh jsonb;
  d public.attendance_live_days;
begin
  select min(check_in_at) into first_in
  from public.attendance_live_sessions
  where staff_id=p_staff_id and operational_date=p_date and coalesce(is_deleted,false)=false;

  if first_in is null then
    update public.attendance_live_days
       set scheduled_start=null,
           late_minutes=0,
           updated_at=now()
     where staff_id=p_staff_id and operational_date=p_date
     returning * into d;
    return to_jsonb(d);
  end if;

  sh:=public.attendance_live_shift_info(first_in);
  insert into public.attendance_live_days(
    staff_id,operational_date,break_taken,classification,scheduled_start,late_minutes
  ) values(
    p_staff_id,p_date,true,'Duty',nullif(sh->>'scheduled_start','')::time,
    coalesce((sh->>'late_minutes')::int,0)
  )
  on conflict(branch_id,staff_id,operational_date) do update set
    scheduled_start=excluded.scheduled_start,
    late_minutes=excluded.late_minutes,
    is_deleted=false,
    deleted_at=null,
    deleted_reason=null,
    updated_at=now()
  returning * into d;
  return to_jsonb(d);
end $function$
;
alter function public.attendance_live_recalculate_day_internal(p_staff_id uuid, p_date date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_update_day(p_token text, p_staff_id uuid, p_date date, p_break_taken boolean, p_classification text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare oldv jsonb; d public.attendance_live_days; begin
  perform public.require_session(p_token,true);
  if p_classification not in ('Duty','Day Off - Pending Review','Weekly Off','Leave','Sick Leave','Unpaid Leave','Absent','Public Holiday','Other Approved') then
    raise exception 'Invalid attendance classification';
  end if;
  select to_jsonb(x) into oldv from public.attendance_live_days x where x.staff_id=p_staff_id and x.operational_date=p_date;
  insert into public.attendance_live_days(staff_id,operational_date,break_taken,classification,classification_note,is_deleted,deleted_at,deleted_reason)
  values(p_staff_id,p_date,coalesce(p_break_taken,true),p_classification,nullif(trim(coalesce(p_note,'')),''),false,null,null)
  on conflict(branch_id,staff_id,operational_date) do update set
    break_taken=excluded.break_taken,
    classification=excluded.classification,
    classification_note=excluded.classification_note,
    is_deleted=false,deleted_at=null,deleted_reason=null,updated_at=now()
  returning * into d;
  if exists(select 1 from public.attendance_live_sessions s where s.staff_id=p_staff_id and s.operational_date=p_date and coalesce(s.is_deleted,false)=false) then
    perform public.attendance_live_recalculate_day_internal(p_staff_id,p_date);
    select * into d from public.attendance_live_days where staff_id=p_staff_id and operational_date=p_date;
  end if;
  insert into public.attendance_live_audit(staff_id,operational_date,actor_type,action,before_data,after_data)
  values(p_staff_id,p_date,'admin','EDIT_DAY',oldv,to_jsonb(d));
  return to_jsonb(d);
end $function$
;
alter function public.attendance_live_admin_update_day(p_token text, p_staff_id uuid, p_date date, p_break_taken boolean, p_classification text, p_note text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_delete_session(p_token text, p_session_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare oldv jsonb; r public.attendance_live_sessions; begin
  perform public.require_session(p_token,true);
  select * into r from public.attendance_live_sessions where id=p_session_id and coalesce(is_deleted,false)=false;
  if r.id is null then raise exception 'Live attendance session not found'; end if;
  oldv:=to_jsonb(r);
  update public.attendance_live_sessions set is_deleted=true,deleted_at=now(),deleted_reason=nullif(trim(coalesce(p_reason,'')),''),updated_at=now()
  where id=p_session_id returning * into r;
  perform public.attendance_live_recalculate_day_internal(r.staff_id,r.operational_date);
  insert into public.attendance_live_audit(staff_id,operational_date,session_id,actor_type,action,before_data,after_data)
  values(r.staff_id,r.operational_date,r.id,'admin','ARCHIVE_SESSION',oldv,to_jsonb(r));
  return jsonb_build_object('ok',true,'session',to_jsonb(r));
end $function$
;
alter function public.attendance_live_admin_delete_session(p_token text, p_session_id uuid, p_reason text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_equipment_submit(p_token text, p_request_id uuid, p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.app_sessions;s public.staff;r goya_private.equipment_reports;d date;v_section text;
begin
 a:=public.require_session(p_token,false);select * into s from public.staff where id=a.staff_id and active;
 if s.id is null then raise exception 'Staff is inactive or unauthorized';end if;
 if p_request_id is null then raise exception 'Submission reference is required';end if;
 select * into r from goya_private.equipment_reports where staff_id=s.id and request_id=p_request_id;
 if r.id is not null then return jsonb_build_object('id',r.id,'saved',true);end if;
 if p_value is null or jsonb_typeof(p_value)<>'object' then raise exception 'Invalid report';end if;
 if length(trim(coalesce(p_value->>'item_name',''))) not between 1 and 160 or length(trim(coalesce(p_value->>'details',''))) not between 1 and 2000
 or length(trim(coalesce(p_value->>'quantity','')))>80 then raise exception 'Enter an equipment name and details within the allowed length';end if;
 d:=(p_value->>'incident_date')::date;v_section:=trim(coalesce(p_value->>'section',''));
 if d is null or d<date '2000-01-01' or d>(now() at time zone 'Asia/Dubai')::date then raise exception 'Choose a valid incident date, no later than today';end if;
 if not(v_section=any(coalesce(s.sections,'{}'::text[]))) and not(v_section='' and cardinality(coalesce(s.sections,'{}'::text[]))=0) then raise exception 'Choose one of your assigned sections';end if;
 insert into goya_private.equipment_reports(staff_id,staff_name,section,item_name,quantity,details,incident_date,request_id)
 values(s.id,s.name,v_section,trim(p_value->>'item_name'),trim(coalesce(p_value->>'quantity','')),trim(p_value->>'details'),d,p_request_id)
 on conflict(staff_id,request_id) do nothing returning * into r;
 if r.id is null then select * into r from goya_private.equipment_reports where staff_id=s.id and request_id=p_request_id;end if;
 return jsonb_build_object('id',r.id,'saved',true);
end $function$
;
alter function public.goya_equipment_submit(p_token text, p_request_id uuid, p_value jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_history(p_token text, p_start date, p_end date, p_staff_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rules jsonb:=public.attendance_live_rules();
  sys_start date:=coalesce((rules->>'system_start_date')::date,p_start);
  e date:=least(p_end,timezone(coalesce(rules->>'timezone','Asia/Dubai'),now())::date);
begin
  perform public.require_session(p_token,true);
  if p_start is null or p_end is null or p_end<p_start then raise exception 'Invalid date range'; end if;
  if e<p_start then return jsonb_build_object('server_now',now(),'rules',rules,'rows','[]'::jsonb); end if;
  return jsonb_build_object('server_now',now(),'rules',rules,'rows',coalesce((
    with base as (
      select s.id staff_id,s.name staff_name,s.sections,g::date operational_date from public.staff s cross join generate_series(greatest(p_start,sys_start),e,interval '1 day') g where (s.active=true or exists(select 1 from goya_private.staff_hr_profiles hp where hp.staff_id=s.id and hp.last_day is not null)) and (p_staff_id is null or s.id=p_staff_id)
      union select s.id,s.name,s.sections,d.operational_date from public.staff s join public.attendance_live_days d on d.staff_id=s.id where (s.active=true or exists(select 1 from goya_private.staff_hr_profiles hp where hp.staff_id=s.id and hp.last_day is not null)) and (p_staff_id is null or s.id=p_staff_id) and d.operational_date between p_start and e and coalesce(d.is_deleted,false)=false
      union select s.id,s.name,s.sections,x.operational_date from public.staff s join public.attendance_live_sessions x on x.staff_id=s.id where (s.active=true or exists(select 1 from goya_private.staff_hr_profiles hp where hp.staff_id=s.id and hp.last_day is not null)) and (p_staff_id is null or s.id=p_staff_id) and x.operational_date between p_start and e and coalesce(x.is_deleted,false)=false
    )
    select jsonb_agg(to_jsonb(q) order by q.operational_date desc,q.staff_name) from (
      select b.operational_date,b.staff_id,b.staff_name,b.sections,(select st.active from public.staff st where st.id=b.staff_id) staff_active,coalesce(d.break_taken,true) break_taken,coalesce(d.split_shift_allowed,false) split_shift_allowed,
        case when exists(select 1 from public.attendance_live_sessions sx where sx.staff_id=b.staff_id and sx.operational_date=b.operational_date and coalesce(sx.is_deleted,false)=false)
             then coalesce(nullif(d.classification,'Day Off - Pending Review'),'Duty') else coalesce(d.classification,'Day Off - Pending Review') end classification,
        d.classification_note,goya_private.employment_note(b.staff_id,b.operational_date) employment_note,d.ot_policy,d.scheduled_start,coalesce(d.late_minutes,0) late_minutes,
        coalesce((select jsonb_agg(to_jsonb(x) order by x.check_in_at,x.created_at) from public.attendance_live_sessions x
          where x.staff_id=b.staff_id and x.operational_date=b.operational_date and coalesce(x.is_deleted,false)=false),'[]'::jsonb) sessions
      from base b left join public.attendance_live_days d on d.staff_id=b.staff_id and d.operational_date=b.operational_date and coalesce(d.is_deleted,false)=false
      where goya_private.employed_on(b.staff_id,b.operational_date)
    ) q
  ),'[]'::jsonb));
end $function$
;
alter function public.attendance_live_admin_history(p_token text, p_start date, p_end date, p_staff_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.run_roster_notifications()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare token text; result bigint;
begin
 if not exists (
   select 1 from goya_private.roster_push_deliveries d
   join goya_private.roster_weeks w on w.week_start=d.week_start and w.published_revision=d.revision
   where d.sent_at is null and d.attempts<3 and d.created_at>now()-interval '1 day'
     and (d.claimed_at is null or d.claimed_at<now()-interval '3 minutes')
 ) then return null; end if;
 select worker_token into token from goya_private.push_config where id;
 if token is null then return null; end if;
 select net.http_post(
   url:='https://yudrsojnfucvdigehkku.supabase.co/functions/v1/roster-notifications',
   headers:=jsonb_build_object('Content-Type','application/json','x-goya-worker',token),
   body:='{}'::jsonb,timeout_milliseconds:=15000
 ) into result;
 return result;
end $function$
;
alter function goya_private.run_roster_notifications() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_management_notice_draft(p_token text, p_id uuid, p_title text, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result goya_private.notices;
begin
 perform public.require_session(p_token,true);
 if length(btrim(coalesce(p_title,'')))=0 then raise exception 'Enter a title for your draft'; end if;
 if p_id is not null then raise exception 'Use Save Notice to update an existing notice'; end if;
 insert into goya_private.notices(title,body,active,published_at,is_draft) values(p_title,coalesce(p_body,''),false,now(),true) returning * into result;
 return to_jsonb(result);
end $function$
;
alter function public.goya_management_notice_draft(p_token text, p_id uuid, p_title text, p_body text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_live_attendance_set_split(p_token text, p_split_shift boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  od date:=public.attendance_live_operational_date(now());
  rules jsonb:=public.attendance_live_rules();
begin
  sess:=public.require_session(p_token,false);

  if coalesce(p_split_shift,false)
     and coalesce((rules->>'split_shift_enabled')::boolean,true)=false then
    raise exception 'Split Shift is disabled by Admin';
  end if;

  update public.attendance_live_days
     set split_shift_allowed=coalesce(p_split_shift,false),
         updated_at=now()
   where staff_id=sess.staff_id
     and operational_date=od
     and coalesce(is_deleted,false)=false;

  -- If today's day row does not exist yet, create it safely so the staff choice
  -- can be stored before/around the duty flow without deleting any existing data.
  if not found then
    insert into public.attendance_live_days(
      staff_id,
      operational_date,
      break_taken,
      classification,
      split_shift_allowed
    )
    values(
      sess.staff_id,
      od,
      true,
      'Duty',
      coalesce(p_split_shift,false)
    )
    on conflict(branch_id,staff_id, operational_date) do update
      set split_shift_allowed=excluded.split_shift_allowed,
          updated_at=now();
  end if;

  return true;
end $function$
;
alter function public.staff_live_attendance_set_split(p_token text, p_split_shift boolean) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_management_notice_status(p_token text, p_id uuid, p_active boolean, p_expected timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.require_session(p_token,true);
 if p_active and exists(select 1 from goya_private.notices where id=p_id and (length(btrim(body))=0 or expires_at<=now())) then raise exception 'Edit the notice content and expiry before publishing'; end if;
 update goya_private.notices set active=p_active,updated_at=clock_timestamp() where id=p_id and deleted_at is null and updated_at=p_expected;
 if not found then raise exception 'Notice changed. Reload before saving.'; end if;
 if not p_active then update goya_private.notice_push_jobs set cancelled_at=coalesce(cancelled_at,now()) where notice_id=p_id; end if;
end $function$
;
alter function public.goya_management_notice_status(p_token text, p_id uuid, p_active boolean, p_expected timestamp with time zone) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_update_day_v26(p_token text, p_staff_id uuid, p_date date, p_break_taken boolean, p_split_shift boolean, p_classification text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare oldv jsonb; d public.attendance_live_days;
begin
  perform public.require_session(p_token,true);
  if p_classification not in ('Duty','Day Off - Pending Review','Weekly Off','Leave','Sick Leave','Unpaid Leave','Absent','Public Holiday','Other Approved') then raise exception 'Invalid attendance classification'; end if;
  select to_jsonb(x) into oldv from public.attendance_live_days x where x.staff_id=p_staff_id and x.operational_date=p_date;
  insert into public.attendance_live_days(staff_id,operational_date,break_taken,split_shift_allowed,classification,classification_note,is_deleted,deleted_at,deleted_reason)
  values(p_staff_id,p_date,coalesce(p_break_taken,true),coalesce(p_split_shift,false),p_classification,nullif(trim(coalesce(p_note,'')),''),false,null,null)
  on conflict(branch_id,staff_id,operational_date) do update set
    break_taken=excluded.break_taken,split_shift_allowed=excluded.split_shift_allowed,classification=excluded.classification,
    classification_note=excluded.classification_note,is_deleted=false,deleted_at=null,deleted_reason=null,updated_at=now()
  returning * into d;
  if exists(select 1 from public.attendance_live_sessions s where s.staff_id=p_staff_id and s.operational_date=p_date and coalesce(s.is_deleted,false)=false) then
    perform public.attendance_live_recalculate_day_internal(p_staff_id,p_date);
    select * into d from public.attendance_live_days where staff_id=p_staff_id and operational_date=p_date;
  end if;
  insert into public.attendance_live_audit(staff_id,operational_date,actor_type,action,before_data,after_data)
  values(p_staff_id,p_date,'admin','EDIT_DAY_V26',oldv,to_jsonb(d));
  return to_jsonb(d);
end $function$
;
alter function public.attendance_live_admin_update_day_v26(p_token text, p_staff_id uuid, p_date date, p_break_taken boolean, p_split_shift boolean, p_classification text, p_note text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_equipment_list(p_token text, p_month date, p_page integer DEFAULT 1, p_admin boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.app_sessions;total bigint;pg integer;rows jsonb;m date;
begin
 a:=public.require_session(p_token,p_admin);
 if not p_admin and not exists(select 1 from public.staff where id=a.staff_id and active) then raise exception 'Staff is inactive or unauthorized';end if;
 if p_month is null then raise exception 'Select a month';end if;m:=date_trunc('month',p_month)::date;
 select count(*) into total from goya_private.equipment_reports where incident_date>=m and incident_date<(m+interval '1 month') and (p_admin or staff_id=a.staff_id);
 pg:=greatest(1,least(coalesce(p_page,1),greatest(1,ceil(total/30.0)::integer)));
 select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into rows from
 (select id,staff_name,section,item_name,quantity,details,incident_date,created_at,status,admin_note,version,updated_at from goya_private.equipment_reports
 where incident_date>=m and incident_date<(m+interval '1 month') and (p_admin or staff_id=a.staff_id) order by created_at desc,id desc limit 30 offset (pg-1)*30)q;
 return jsonb_build_object('rows',rows,'total',total,'page',pg);
end $function$
;
alter function public.goya_equipment_list(p_token text, p_month date, p_page integer, p_admin boolean) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_equipment_review(p_token text, p_id uuid, p_version bigint, p_status text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r goya_private.equipment_reports;
begin
 perform public.require_session(p_token,true);
 if p_status is null or p_status not in ('Pending','Reviewed','Repaired','Replaced','Closed') or length(coalesce(p_note,''))>1000 then raise exception 'Invalid status or note';end if;
 update goya_private.equipment_reports set status=p_status,admin_note=coalesce(p_note,''),version=version+1,updated_at=now() where id=p_id and version=p_version returning * into r;
 if r.id is null then raise exception 'Record changed or is unavailable. Refresh and review again';end if;
 insert into goya_private.equipment_status_history(report_id,status,note) values(r.id,r.status,r.admin_note);
 return jsonb_build_object('saved',true);
end $function$
;
alter function public.goya_equipment_review(p_token text, p_id uuid, p_version bigint, p_status text, p_note text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_notifications(p_token text, p_page integer DEFAULT 1, p_unread boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare total bigint;unread bigint;pg integer;rows jsonb;last_id bigint;
begin
 perform public.require_session(p_token,true);
 select count(*) filter(where not p_unread or read_at is null),count(*) filter(where read_at is null),coalesce(max(id),0) into total,unread,last_id from goya_private.admin_notifications where created_at>=now()-interval '90 days';
 pg:=greatest(1,least(coalesce(p_page,1),greatest(1,ceil(total/30.0)::integer)));
 select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into rows from (select id,kind,staff_name,created_at,read_at from goya_private.admin_notifications where created_at>=now()-interval '90 days' and (not p_unread or read_at is null) order by id desc limit 30 offset (pg-1)*30)q;
 return jsonb_build_object('rows',rows,'total',total,'unread',unread,'page',pg,'last_id',last_id);
end $function$
;
alter function public.goya_admin_notifications(p_token text, p_page integer, p_unread boolean) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_legacy_admin_history(p_token text, p_start date, p_end date, p_staff_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.require_session(p_token,true);
  if p_start is null or p_end is null or p_end < p_start then
    raise exception 'Invalid date range';
  end if;

  return jsonb_build_object(
    'rows', coalesce((
      with candidates as (
        select a.id attendance_staff_id, a.portal_staff_id staff_id, s.name staff_name, r.operational_date
          from public.attendance_staff a
          join public.staff s on s.id=a.portal_staff_id
          join public.attendance_records r on r.attendance_staff_id=a.id
         where r.operational_date between p_start and p_end
           and (p_staff_id is null or a.portal_staff_id=p_staff_id)
        union
        select a.id, a.portal_staff_id, s.name, x.operational_date
          from public.attendance_staff a
          join public.staff s on s.id=a.portal_staff_id
          join public.attendance_staff_submissions x on x.attendance_staff_id=a.id
         where x.operational_date between p_start and p_end
           and (p_staff_id is null or a.portal_staff_id=p_staff_id)
      )
      select jsonb_agg(jsonb_build_object(
        'staff_id',c.staff_id,
        'staff_name',c.staff_name,'staff_active',(select st.active from public.staff st where st.id=c.staff_id),'employment_note',goya_private.employment_note(c.staff_id,c.operational_date),
        'operational_date',c.operational_date,
        'record',(select to_jsonb(r) from public.attendance_records r
                  where r.attendance_staff_id=c.attendance_staff_id and r.operational_date=c.operational_date
                  limit 1),
        'submission',(select to_jsonb(x) from public.attendance_staff_submissions x
                      where x.attendance_staff_id=c.attendance_staff_id and x.operational_date=c.operational_date
                      order by x.submitted_at desc nulls last limit 1)
      ) order by c.operational_date desc,c.staff_name)
      from candidates c where goya_private.employed_on(c.staff_id,c.operational_date)
    ),'[]'::jsonb)
  );
end $function$
;
alter function public.attendance_legacy_admin_history(p_token text, p_start date, p_end date, p_staff_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_management_key(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb;
begin
  perform public.require_session(p_token,true);
  select value into v from public.attendance_settings where key='management_share';
  if v is null then raise exception 'Management share is not configured'; end if;
  return jsonb_build_object('key',v->>'key','enabled',coalesce((v->>'enabled')::boolean,true));
end $function$
;
alter function public.attendance_live_management_key(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_notification_detail(p_token text, p_id bigint, p_page integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n goya_private.admin_notifications;items jsonb;total bigint;pg integer:=greatest(1,least(coalesce(p_page,1),100000));offst integer;ref jsonb;
begin
 perform public.require_session(p_token,true);select * into n from goya_private.admin_notifications where id=p_id;
 if n.id is null then raise exception 'Notification is unavailable; open the original module to view its records';end if;
 ref:=n.source_ref;offst:=(pg-1)*30;
 if n.kind='orders' then
  select count(*) into total from public.orders where order_group_id=(ref->>'group_id')::uuid;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into items from(select name,sku,quantity,unit,supplier,status,notes,created_at from public.orders where order_group_id=(ref->>'group_id')::uuid order by id limit 30 offset offst)q;
 elsif n.kind='production' then
  select count(*) into total from public.production_batches where batch_group_id=(ref->>'group_id')::uuid;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into items from(select name,sku,storage_quantity,ingredients_quantity,quantity,unit,admin_status,created_at from public.production_batches where batch_group_id=(ref->>'group_id')::uuid order by id limit 30 offset offst)q;
 elsif n.kind='wastage' then
  select count(*) into total from public.wastage_entries where wastage_group_id=(ref->>'group_id')::uuid;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into items from(select name,sku,storage_quantity,ingredients_quantity,quantity,unit,reason,admin_status,created_at from public.wastage_entries where wastage_group_id=(ref->>'group_id')::uuid order by id limit 30 offset offst)q;
 elsif n.kind='feedback' then
  select coalesce(jsonb_agg(jsonb_build_object('type',type,'details',details,'staff_name',case when hide_identity then 'Anonymous' else staff_name end,'created_at',created_at)),'[]') into items from public.complaint_feedback where id=(ref->>'id')::bigint;total:=jsonb_array_length(items);
 elsif n.kind='equipment' then
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into items from(select item_name,quantity,details,section,incident_date,status,admin_note from goya_private.equipment_reports where id=(ref->>'id')::uuid)q;total:=jsonb_array_length(items);
 elsif n.kind='inventory_shared' then
  select coalesce(jsonb_array_length(f.items),0) into total from goya_private.inventory_shared_finals f where id=(ref->>'id')::uuid;
  select coalesce(jsonb_agg(q.value),'[]') into items from(select e.value from goya_private.inventory_shared_finals f cross join lateral jsonb_array_elements(f.items) with ordinality e(value,ord) where f.id=(ref->>'id')::uuid order by e.ord limit 30 offset offst)q;
 else
  select count(*) into total from public.inventory_counts where session_id=(ref->>'session_id')::uuid and staff_id=(ref->>'staff_id')::uuid and section=ref->>'section';
  select coalesce(jsonb_agg(to_jsonb(q)),'[]') into items from(select item_name,sku,section,storage_quantity,ingredients_quantity,counted_by,counted_at from public.inventory_counts where session_id=(ref->>'session_id')::uuid and staff_id=(ref->>'staff_id')::uuid and section=ref->>'section' order by id limit 30 offset offst)q;
 end if;
 update goya_private.admin_notifications set read_at=coalesce(read_at,now()) where id=n.id;
 return jsonb_build_object('kind',n.kind,'rows',items,'total',coalesce(total,0),'page',pg,'source_ref',ref);
end $function$
;
alter function public.goya_admin_notification_detail(p_token text, p_id bigint, p_page integer) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_management_rejoin(p_token text, p_staff uuid, p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.goya_hr_rejoin(p_token,p_staff,p_date);
 update goya_private.staff_resignations set cancelled_at=clock_timestamp() where staff_id=p_staff;
end $function$
;
alter function public.goya_management_rejoin(p_token text, p_staff uuid, p_date date) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.employed_on(employee uuid, day date)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.staff s left join goya_private.staff_hr_profiles p on p.staff_id=s.id
 left join goya_private.staff_resignations r on r.staff_id=s.id and r.cancelled_at is null
 where s.id=employee and (p.joining_date is null or day>=p.joining_date)
 and (coalesce(p.last_day,r.last_working_day) is null or day<=coalesce(p.last_day,r.last_working_day))
 and not exists(select 1 from goya_private.staff_hr_audit a where a.staff_id=employee and a.event='Rejoined'
 and day>(a.details->>'last_day')::date and day<(a.details->>'rejoined_on')::date));
$function$
;
alter function goya_private.employed_on(employee uuid, day date) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.employment_note(employee uuid, day date)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select concat_ws(' · ',case when p.joining_date=day or exists(select 1 from goya_private.staff_hr_audit a where a.staff_id=employee and a.event='Rejoined' and a.details->>'rejoined_on'=day::text) then 'Joining Day' end,
 case when coalesce(p.last_day,r.last_working_day)=day then 'Resigned' end)
 from goya_private.staff_hr_profiles p left join goya_private.staff_resignations r on r.staff_id=p.staff_id and r.cancelled_at is null where p.staff_id=employee;
$function$
;
alter function goya_private.employment_note(employee uuid, day date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_management_validate(p_key text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(
    select 1 from public.attendance_settings
    where key='management_share'
      and coalesce((value->>'enabled')::boolean,true)=true
      and length(coalesce(p_key,'')) >= 32
      and value->>'key'=p_key
  )
$function$
;
alter function public.attendance_live_management_validate(p_key text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_management_key(p_token text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select public.attendance_live_management_key(p_token) $function$
;
alter function public.attendance_live_admin_management_key(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.revoke_saved_admin()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 update public.app_sessions a set expires_at=least(a.expires_at,now()) where a.is_admin and exists(select 1 from goya_private.admin_remembered_sessions r where r.session_token=a.token);
 update goya_private.admin_push_devices set active=false,updated_at=now();
 return new;
end $function$
;
alter function goya_private.revoke_saved_admin() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_management_dashboard(p_key text, p_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  d date:=coalesce(p_date,public.attendance_live_operational_date(now()));
  rules jsonb:=public.attendance_live_rules();
begin
  if not public.attendance_live_management_validate(p_key) then
    raise exception 'Invalid or expired management link';
  end if;
  return jsonb_build_object(
    'server_now',now(),
    'operational_date',d,
    'rules',jsonb_build_object(
      'duty_presence_minutes',coalesce((rules->>'duty_presence_minutes')::int,540),
      'regular_net_minutes',coalesce((rules->>'regular_net_minutes')::int,480),
      'break_minutes',coalesce((rules->>'break_minutes')::int,60),
      'timezone',coalesce(rules->>'timezone','Asia/Dubai')
    ),
    'staff',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name)
                      from goya_private.branch_staff_history s where s.active=true and goya_private.employed_on(s.id,d) and goya_private.branch_employee_on(s.id,d)),'[]'::jsonb),
    'days',coalesce((select jsonb_agg(jsonb_build_object(
                       'staff_id',x.staff_id,'operational_date',x.operational_date,
                       'break_taken',x.break_taken,'classification',x.classification,
                       'classification_note',x.classification_note,'ot_policy',x.ot_policy,'scheduled_start',x.scheduled_start,
                       'late_minutes',x.late_minutes))
                      from public.attendance_live_days x
                      where x.operational_date=d and goya_private.employed_on(x.staff_id,d) and coalesce(x.is_deleted,false)=false),'[]'::jsonb),
    'sessions',coalesce((select jsonb_agg(jsonb_build_object(
                           'id',x.id,'staff_id',x.staff_id,'operational_date',x.operational_date,
                           'session_no',x.session_no,'check_in_at',x.check_in_at,'check_out_at',x.check_out_at,
                           'check_in_verified',x.check_in_verified,'check_out_verified',x.check_out_verified)
                         order by x.staff_id,x.session_no)
                        from public.attendance_live_sessions x
                        where x.operational_date=d and goya_private.employed_on(x.staff_id,d) and coalesce(x.is_deleted,false)=false),'[]'::jsonb)
  );
end $function$
;
alter function public.attendance_live_management_dashboard(p_key text, p_date date) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.queue_admin_push()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 insert into goya_private.admin_push_deliveries(notification_id,device_id)
 select n.id,d.id from new_notifications n cross join goya_private.admin_push_devices d join public.app_sessions s on s.token=d.session_token and s.is_admin and s.expires_at>now() where d.active on conflict do nothing;
 return null;
end $function$
;
alter function goya_private.queue_admin_push() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_public_month(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sd date:=date_trunc('month',p_month)::date;
  ed date:=(date_trunc('month',p_month)+interval '1 month - 1 day')::date;
  rules jsonb:=public.attendance_live_rules();
  today_local date:=timezone(coalesce(rules->>'timezone','Asia/Dubai'),now())::date;
  sys_start date:=coalesce((rules->>'system_start_date')::date,sd);
begin
  if p_month is null then raise exception 'Month is required'; end if;
  sd:=greatest(sd,sys_start);
  ed:=least(ed,today_local);
  if ed<sd then return jsonb_build_object('server_now',now(),'rules',rules,'rows','[]'::jsonb); end if;
  return jsonb_build_object(
    'server_now',now(),
    'rules',jsonb_build_object(
      'duty_presence_minutes',coalesce((rules->>'duty_presence_minutes')::int,540),
      'regular_net_minutes',coalesce((rules->>'regular_net_minutes')::int,480),
      'break_minutes',coalesce((rules->>'break_minutes')::int,60),
      'timezone',coalesce(rules->>'timezone','Asia/Dubai')
    ),
    'rows',coalesce((
      select jsonb_agg(to_jsonb(q) order by q.operational_date desc,q.staff_name)
      from (
        select g::date operational_date,s.id staff_id,s.name staff_name,
          coalesce(d.break_taken,true) break_taken,
          case when exists(select 1 from public.attendance_live_sessions sx
                           where sx.staff_id=s.id and sx.operational_date=g::date and coalesce(sx.is_deleted,false)=false)
               then coalesce(nullif(d.classification,'Day Off - Pending Review'),'Duty')
               else coalesce(d.classification,'Day Off - Pending Review') end classification,
          d.ot_policy,d.scheduled_start,coalesce(d.late_minutes,0) late_minutes,
          coalesce((select jsonb_agg(jsonb_build_object(
                     'session_no',x.session_no,'check_in_at',x.check_in_at,'check_out_at',x.check_out_at,
                     'check_in_verified',x.check_in_verified,'check_out_verified',x.check_out_verified)
                     order by x.session_no)
                    from public.attendance_live_sessions x
                    where x.staff_id=s.id and x.operational_date=g::date and coalesce(x.is_deleted,false)=false),'[]'::jsonb) sessions
        from goya_private.branch_staff_history s
        cross join generate_series(sd,ed,interval '1 day') g
        left join public.attendance_live_days d
          on d.staff_id=s.id and d.operational_date=g::date and coalesce(d.is_deleted,false)=false
        where (s.active=true or exists(select 1 from goya_private.staff_hr_profiles hp where hp.staff_id=s.id and hp.last_day is not null)) and goya_private.employed_on(s.id,g::date) and goya_private.branch_employee_on(s.id,g::date)
      ) q
    ),'[]'::jsonb)
  );
end $function$
;
alter function public.attendance_live_public_month(p_month date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_set_break(p_token text, p_staff_id uuid, p_date date, p_break_taken boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  beforev jsonb; afterv jsonb; a_id uuid; r_id uuid;
begin
  perform public.require_session(p_token,true);
  if p_staff_id is null or p_date is null then raise exception 'Staff and date are required'; end if;

  if exists(select 1 from public.attendance_live_days where staff_id=p_staff_id and operational_date=p_date)
     or exists(select 1 from public.attendance_live_sessions where staff_id=p_staff_id and operational_date=p_date and coalesce(is_deleted,false)=false) then
    select to_jsonb(d) into beforev from public.attendance_live_days d where d.staff_id=p_staff_id and d.operational_date=p_date;
    insert into public.attendance_live_days(staff_id,operational_date,break_taken,classification,is_deleted)
    values(p_staff_id,p_date,coalesce(p_break_taken,true),'Duty',false)
    on conflict(branch_id,staff_id,operational_date) do update set break_taken=excluded.break_taken,updated_at=now(),is_deleted=false,deleted_at=null,deleted_reason=null
    returning to_jsonb(attendance_live_days.*) into afterv;
    perform public.attendance_live_recalculate_day_internal(p_staff_id,p_date);
    select to_jsonb(d) into afterv from public.attendance_live_days d where d.staff_id=p_staff_id and d.operational_date=p_date;
  else
    select id into a_id from public.attendance_staff where portal_staff_id=p_staff_id order by active desc,updated_at desc limit 1;
    if a_id is null then raise exception 'Attendance staff mapping not found'; end if;
    select id,to_jsonb(r) into r_id,beforev from public.attendance_records r where r.attendance_staff_id=a_id and r.operational_date=p_date limit 1;
    if r_id is null then raise exception 'Previous attendance record not found'; end if;
    update public.attendance_records set break_taken=coalesce(p_break_taken,true),updated_at=now() where id=r_id;
    perform public.attendance_recalc(r_id);
    select to_jsonb(r) into afterv from public.attendance_records r where r.id=r_id;
  end if;

  insert into public.attendance_live_audit(staff_id,operational_date,actor_type,action,before_data,after_data)
  values(p_staff_id,p_date,'admin','EDIT_BREAK',beforev,afterv);
  return jsonb_build_object('ok',true,'staff_id',p_staff_id,'operational_date',p_date,'break_taken',coalesce(p_break_taken,true));
end $function$
;
alter function public.attendance_live_admin_set_break(p_token text, p_staff_id uuid, p_date date, p_break_taken boolean) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_update_previous_record(p_token text, p_staff_id uuid, p_date date, p_punch_in timestamp with time zone, p_punch_out timestamp with time zone, p_break_taken boolean, p_split_shift boolean, p_shift2_in timestamp with time zone, p_shift2_out timestamp with time zone, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a_id uuid; r_id uuid; beforev jsonb; afterv jsonb;
  pin timestamp; pout timestamp; s2in timestamp; s2out timestamp;
begin
  perform public.require_session(p_token,true);
  select id into a_id from public.attendance_staff where portal_staff_id=p_staff_id order by active desc,updated_at desc limit 1;
  if a_id is null then raise exception 'Attendance staff mapping not found'; end if;
  if p_punch_in is null then raise exception 'Check In is required'; end if;
  pin:=p_punch_in at time zone 'Asia/Dubai';
  pout:=case when p_punch_out is null then null else p_punch_out at time zone 'Asia/Dubai' end;
  s2in:=case when p_shift2_in is null then null else p_shift2_in at time zone 'Asia/Dubai' end;
  s2out:=case when p_shift2_out is null then null else p_shift2_out at time zone 'Asia/Dubai' end;
  if pout is not null and pout<=pin then raise exception 'Check Out must be after Check In'; end if;
  if coalesce(p_split_shift,false) and (s2in is null or s2out is null or s2out<=s2in) then raise exception 'Valid Session 2 In/Out is required'; end if;

  select id,to_jsonb(r) into r_id,beforev from public.attendance_records r where r.attendance_staff_id=a_id and r.operational_date=p_date limit 1;
  if r_id is null then
    insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,day_off,split_shift,shift2_in,shift2_out,entry_origin)
    values(a_id,p_date,pin,pout,coalesce(p_break_taken,true),nullif(trim(coalesce(p_note,'')),''),'manual',false,coalesce(p_split_shift,false),s2in,s2out,'admin_manual') returning id into r_id;
  else
    update public.attendance_records set punch_in=pin,punch_out=pout,break_taken=coalesce(p_break_taken,true),note=coalesce(nullif(trim(coalesce(p_note,'')),''),note),source='manual',day_off=false,split_shift=coalesce(p_split_shift,false),shift2_in=case when coalesce(p_split_shift,false) then s2in else null end,shift2_out=case when coalesce(p_split_shift,false) then s2out else null end,entry_origin='admin_manual',updated_at=now() where id=r_id;
  end if;
  perform public.attendance_recalc(r_id);
  select to_jsonb(r) into afterv from public.attendance_records r where r.id=r_id;
  insert into public.attendance_live_audit(staff_id,operational_date,actor_type,action,before_data,after_data)
  values(p_staff_id,p_date,'admin','EDIT_PREVIOUS_RECORD',beforev,afterv);
  return jsonb_build_object('ok',true,'record',afterv);
end $function$
;
alter function public.attendance_live_admin_update_previous_record(p_token text, p_staff_id uuid, p_date date, p_punch_in timestamp with time zone, p_punch_out timestamp with time zone, p_break_taken boolean, p_split_shift boolean, p_shift2_in timestamp with time zone, p_shift2_out timestamp with time zone, p_note text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_remember(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.require_session(p_token,true);
 insert into goya_private.admin_remembered_sessions(session_token) values(p_token) on conflict do nothing;
 update public.app_sessions set expires_at=now()+interval '30 days' where token=p_token and is_admin;
 return jsonb_build_object('token',p_token);
end $function$
;
alter function public.goya_admin_remember(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_resume(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.require_session(p_token,true);
 if not exists(select 1 from goya_private.admin_remembered_sessions where session_token=p_token) then raise exception using message='DEVICE_LOGIN_REQUIRED',errcode='28000';end if;
 update public.app_sessions set expires_at=now()+interval '30 days' where token=p_token and is_admin;
 return jsonb_build_object('token',p_token,'is_admin',true);
end $function$
;
alter function public.goya_admin_resume(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_push_state(p_token text, p_endpoint text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.require_session(p_token,true);
 return jsonb_build_object('public_key',(select public_key from goya_private.push_config where id), 'enabled',exists(select 1 from goya_private.admin_push_devices d join public.app_sessions s on s.token=d.session_token and s.is_admin and s.expires_at>now() where d.endpoint=p_endpoint and d.session_token=p_token and d.active));
end $function$
;
alter function public.goya_admin_push_state(p_token text, p_endpoint text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_save_reason(p_token text, p_name text, p_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare x public.wastage_reasons;
begin
 perform public.require_session(p_token,true);
 if p_id is null then insert into public.wastage_reasons(name) values(trim(p_name)) returning * into x;
 else update public.wastage_reasons set name=trim(p_name),active=true where id=p_id returning * into x; end if;
 return to_jsonb(x);
end; $function$
;
alter function public.admin_save_reason(p_token text, p_name text, p_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_push_save(p_token text, p_subscription jsonb, p_enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ep text:=p_subscription->>'endpoint';
begin
 perform public.require_session(p_token,true);
 if not p_enabled then update goya_private.admin_push_deliveries set cancelled_at=now() where device_id in(select id from goya_private.admin_push_devices where session_token=p_token and endpoint=ep) and sent_at is null;update goya_private.admin_push_devices set active=false,updated_at=now() where session_token=p_token and endpoint=ep;return;end if;
 if not exists(select 1 from goya_private.admin_remembered_sessions where session_token=p_token) then raise exception 'Remember this device before enabling notifications';end if;
 if ep is null or ep!~'^https://' or length(ep)>4096 or length(coalesce(p_subscription#>>'{keys,p256dh}','')) not between 40 and 256 or length(coalesce(p_subscription#>>'{keys,auth}','')) not between 16 and 128 then raise exception 'Invalid push subscription';end if;
 -- Rebinding this browser cancels pending alerts from its previous session.
 update goya_private.admin_push_deliveries set cancelled_at=now() where device_id in(select id from goya_private.admin_push_devices where endpoint=ep and session_token<>p_token) and sent_at is null;
 insert into goya_private.admin_push_devices(session_token,endpoint,subscription,active) values(p_token,ep,p_subscription,true) on conflict(endpoint) do update set session_token=excluded.session_token,subscription=excluded.subscription,active=true,updated_at=now();
end $function$
;
alter function public.goya_admin_push_save(p_token text, p_subscription jsonb, p_enabled boolean) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_correct_pw(p_token text, p_kind text, p_id bigint, p_expected jsonb, p_quantity numeric, p_bucket text, p_reason text, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare tab text;oldv jsonb;newv jsonb;u text;sunit text;iunit text;prev goya_private.pw_quantity_audit;
begin
 perform public.require_session(p_token,true);
 if p_kind is null or p_kind not in ('production','wastage') then raise exception 'Invalid record type';end if;
 if p_quantity is null or p_quantity<=0 or p_quantity>99999999999.999 or p_quantity<>round(p_quantity,3) or p_quantity::text in ('NaN','Infinity','-Infinity') or p_bucket is null or p_bucket not in ('storage','ingredients') or p_request is null or length(trim(coalesce(p_reason,''))) not between 1 and 500 then raise exception 'Enter a positive quantity (up to 3 decimals), quantity type and correction reason';end if;
 select * into prev from goya_private.pw_quantity_audit where request_id=p_request;
 if found then if prev.kind<>p_kind or prev.row_id<>p_id or (prev.new_values->>'quantity')::numeric<>p_quantity then raise exception 'Correction reference already used';end if;return jsonb_build_object('saved',true);end if;
 tab:=case when p_kind='production' then 'production_batches' else 'wastage_entries' end;
 execute format('select to_jsonb(x) from public.%I x where id=$1 for update',tab) into oldv using p_id;
 if oldv is null then raise exception 'Record no longer available';end if;
 if (oldv->'quantity') is distinct from (p_expected->'quantity') or (oldv->'unit') is distinct from (p_expected->'unit') or (oldv->'storage_quantity') is distinct from (p_expected->'storage_quantity') or (oldv->'ingredients_quantity') is distinct from (p_expected->'ingredients_quantity') then raise exception 'Quantity changed. Reload and review again';end if;
 select storage_unit,ingredient_unit into sunit,iunit from public.internal_items where sku=oldv->>'sku' limit 1;
 u:=case when p_bucket='storage' then sunit else iunit end;
 if nullif(u,'') is null and (case when p_bucket='storage' then oldv->>'storage_quantity' else oldv->>'ingredients_quantity' end) is not null then u:=oldv->>'unit';end if;
 if nullif(u,'') is null then raise exception 'Unit unavailable. Restore the item catalog before changing quantity type';end if;
 execute format('update public.%I set quantity=$1,unit=$2,storage_quantity=$3,ingredients_quantity=$4 where id=$5 returning to_jsonb(%I.*)',tab,tab) into newv using p_quantity,u,case when p_bucket='storage' then p_quantity else null end,case when p_bucket='ingredients' then p_quantity else null end,p_id;
 insert into goya_private.pw_quantity_audit(request_id,kind,row_id,old_values,new_values,reason) values(p_request,p_kind,p_id,oldv,newv,trim(p_reason));
 return jsonb_build_object('saved',true);
end $function$
;
alter function public.goya_admin_correct_pw(p_token text, p_kind text, p_id bigint, p_expected jsonb, p_quantity numeric, p_bucket text, p_reason text, p_request uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_pw_corrections(p_token text, p_kind text, p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin perform public.require_session(p_token,true);return (select coalesce(jsonb_agg(to_jsonb(q)),'[]') from(select id,old_values,new_values,reason,created_at from goya_private.pw_quantity_audit where kind=p_kind and row_id=p_id order by id desc limit 50)q);end $function$
;
alter function public.goya_admin_pw_corrections(p_token text, p_kind text, p_id bigint) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_push_claim()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record;outv jsonb:='[]';
begin
 for r in select x.notification_id,x.device_id,d.subscription,n.kind,n.staff_name from goya_private.admin_push_deliveries x join goya_private.admin_push_devices d on d.id=x.device_id and d.active join public.app_sessions s on s.token=d.session_token and s.is_admin and s.expires_at>now() join goya_private.admin_notifications n on n.id=x.notification_id
 where x.sent_at is null and x.cancelled_at is null and x.attempts<3 and n.created_at>now()-interval '1 day' and (x.claimed_at is null or x.claimed_at<now()-interval '3 minutes') order by x.notification_id for update of x skip locked limit 30 loop
 update goya_private.admin_push_deliveries set claimed_at=now(),attempts=attempts+1 where notification_id=r.notification_id and device_id=r.device_id;outv:=outv||jsonb_build_array(to_jsonb(r));
 end loop;return outv;
end $function$
;
alter function public.goya_admin_push_claim() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_push_check(p_notification bigint, p_device uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from goya_private.admin_push_deliveries x join goya_private.admin_push_devices d on d.id=x.device_id and d.active join public.app_sessions s on s.token=d.session_token and s.is_admin and s.expires_at>now() join goya_private.admin_notifications n on n.id=x.notification_id and n.created_at>now()-interval '1 day' where x.notification_id=p_notification and x.device_id=p_device and x.sent_at is null and x.cancelled_at is null);
$function$
;
alter function public.goya_admin_push_check(p_notification bigint, p_device uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_push_result(p_notification bigint, p_device uuid, p_ok boolean, p_expired boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 update goya_private.admin_push_deliveries set sent_at=case when p_ok then now() else sent_at end,error=case when p_ok then null else 'Push delivery failed' end,attempts=case when p_expired then 3 else attempts end where notification_id=p_notification and device_id=p_device;
 if p_expired then update goya_private.admin_push_devices set active=false,updated_at=now() where id=p_device;end if;
end $function$
;
alter function public.goya_admin_push_result(p_notification bigint, p_device uuid, p_ok boolean, p_expired boolean) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_admin_annual_sources(p_token text, p_staff uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.require_session(p_token,true);
  return (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'leave_from',r.approved_from,
    'leave_to',r.approved_to,'note',r.review_note) order by r.approved_from desc),'[]')
    from goya_private.staff_leave_requests r
    where r.staff_id=p_staff and r.kind='Annual Leave' and r.state='Approved'
      and r.approved_to < (now() at time zone 'Asia/Dubai')::date
      and not exists (select 1 from goya_private.staff_annual_history h where h.source_id=r.id));
end $function$
;
alter function public.goya_hr_admin_annual_sources(p_token text, p_staff uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_delete_supplier(p_token text, p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin perform public.require_session(p_token,true);delete from public.suppliers where id=p_id;return true;end $function$
;
alter function public.admin_delete_supplier(p_token text, p_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.run_admin_notifications()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare token text;request_id bigint;
begin
 if not exists(select 1 from goya_private.admin_push_deliveries x join goya_private.admin_push_devices d on d.id=x.device_id and d.active join public.app_sessions s on s.token=d.session_token and s.is_admin and s.expires_at>now() join goya_private.admin_notifications n on n.id=x.notification_id and n.created_at>now()-interval '1 day' where x.sent_at is null and x.cancelled_at is null and x.attempts<3 and (x.claimed_at is null or x.claimed_at<now()-interval '3 minutes')) then return null;end if;
 select worker_token into token from goya_private.push_config where id;
 select net.http_post(url:='https://yudrsojnfucvdigehkku.supabase.co/functions/v1/admin-notifications',headers:=jsonb_build_object('Content-Type','application/json','x-goya-worker',token),body:='{}'::jsonb,timeout_milliseconds:=15000) into request_id;
 return request_id;
end $function$
;
alter function goya_private.run_admin_notifications() owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.assign_staff_employee_code()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee_number text;
begin
  new.branch := 'GOYA';
  if tg_op = 'UPDATE' and btrim(old.employee_code) <> '' then
    new.employee_code := old.employee_code;
  end if;
  if btrim(new.employee_code) = '' then
    loop
      employee_number := nextval('goya_private.staff_employee_number')::text;
      new.employee_code := 'GY-' || lpad(employee_number, greatest(3, length(employee_number)), '0');
      exit when not exists (select 1 from goya_private.staff_hr_profiles where employee_code=new.employee_code);
    end loop;
  end if;
  return new;
end $function$
;
alter function goya_private.assign_staff_employee_code() owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.allow_unused_staff_deletion()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if exists (select 1 from goya_private.staff_hr_audit where staff_id=old.id)
     or exists (select 1 from goya_private.staff_hr_profiles where staff_id=old.id
       and (joining_date is not null or last_day is not null or position<>'' or manager_notes<>'')) then
    raise exception 'This staff member has employment history. Use Inactive or record their last working day.';
  end if;
  delete from goya_private.staff_hr_profiles where staff_id=old.id;
  return old;
end $function$
;
alter function goya_private.allow_unused_staff_deletion() owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.protect_withdrawn_leave()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if old.state='Withdrawn' and new.state<>'Withdrawn' then
    raise exception 'This request was withdrawn';
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_live_attendance_status(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  s public.staff;
  od date := public.attendance_live_operational_date(now());
  active_od date := od;
  rules jsonb := public.attendance_live_rules();
  open_row public.attendance_live_sessions;
  cutoff_at timestamptz;
  d public.attendance_live_days;
begin
  sess := public.require_session(p_token,false);
  select * into s from public.staff where id=sess.staff_id;

  -- Find the real active session regardless of midnight rollover.
  select * into open_row
    from public.attendance_live_sessions x
   where x.staff_id=s.id
     and x.check_out_at is null
     and coalesce(x.is_deleted,false)=false
   order by x.check_in_at desc
   limit 1;

  if open_row.id is not null then
    cutoff_at := public.attendance_live_cutoff_at(open_row.operational_date);

    if now() <= cutoff_at then
      active_od := open_row.operational_date;
    else
      -- Only close it when the cutoff is after the actual check-in.
      if cutoff_at >= open_row.check_in_at then
        update public.attendance_live_sessions
           set check_out_at=cutoff_at,
               check_out_location_name='Auto Day Close',
               check_out_verified=false,
               updated_at=now()
         where id=open_row.id
           and check_out_at is null;

        begin
          perform public.attendance_live_recalculate_day_internal(s.id,open_row.operational_date);
        exception when undefined_function then
          null;
        end;
      end if;
      open_row := null;
    end if;
  end if;

  select * into d
    from public.attendance_live_days x
   where x.staff_id=s.id
     and x.operational_date=active_od
     and coalesce(x.is_deleted,false)=false;

  return jsonb_build_object(
    'server_now',now(),
    'operational_date',active_od,
    'staff',jsonb_build_object('id',s.id,'name',s.name,'sections',s.sections,'active',s.active),
    'rules',rules,
    'day',to_jsonb(d),
    'sessions',coalesce((
      select jsonb_agg(to_jsonb(x) order by x.session_no)
        from public.attendance_live_sessions x
       where x.staff_id=s.id
         and x.operational_date=active_od
         and coalesce(x.is_deleted,false)=false
    ),'[]'::jsonb)
  );
end;
$function$
;
alter function public.staff_live_attendance_status(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.document_staff(p_token text, p_staff uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid;
begin
  if p_staff is not null then
    perform public.require_session(p_token,true);
    return p_staff;
  end if;
  employee := (public.require_session(p_token,false)).staff_id;
  if not exists (select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized'; end if;
  return employee;
end $function$
;
alter function goya_private.document_staff(p_token text, p_staff uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_auto_close_stale_sessions(p_staff_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r public.attendance_live_sessions;
  current_od date := public.attendance_live_operational_date(now());
  cutoff_at timestamptz;
  before_row jsonb;
  closed_count integer := 0;
begin
  for r in
    select x.*
      from public.attendance_live_sessions x
     where x.check_out_at is null
       and coalesce(x.is_deleted,false)=false
       and (p_staff_id is null or x.staff_id=p_staff_id)
       and x.operational_date < current_od
     order by x.staff_id, x.operational_date, x.session_no
     for update
  loop
    cutoff_at := public.attendance_live_cutoff_at(r.operational_date);

    -- Never create an impossible checkout earlier than the real check-in.
    -- If the configured cutoff is somehow before the check-in, leave the row
    -- open for normal status/check-out handling instead of corrupting it.
    if now() > cutoff_at and cutoff_at >= r.check_in_at then
      before_row := to_jsonb(r);

      update public.attendance_live_sessions
         set check_out_at=cutoff_at,
             check_out_location_name='Auto Day Close',
             check_out_verified=false,
             updated_at=now()
       where id=r.id
         and check_out_at is null;

      insert into public.attendance_live_audit(
        staff_id, operational_date, session_id, actor_type, action,
        before_data, after_data
      ) values (
        r.staff_id, r.operational_date, r.id, 'system', 'AUTO_DAY_CLOSE',
        before_row,
        jsonb_build_object(
          'session_id', r.id,
          'check_out_at', cutoff_at,
          'reason', 'Operational day cutoff'
        )
      );

      begin
        perform public.attendance_live_recalculate_day_internal(r.staff_id, r.operational_date);
      exception when undefined_function then
        null;
      end;

      closed_count := closed_count + 1;
    end if;
  end loop;

  return closed_count;
end;
$function$
;
alter function public.attendance_live_auto_close_stale_sessions(p_staff_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_management_requests(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.require_session(p_token,true);
 return coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('name',s.name,'sections',s.sections,
  'management_history',coalesce((select jsonb_agg(to_jsonb(d)-'session_ref' order by d.id desc)
   from goya_private.staff_management_decisions d where d.request_id=r.id),'[]'::jsonb)) order by r.created_at desc)
 from goya_private.staff_leave_requests r join public.staff s on s.id=r.staff_id
 where p_month is null or (coalesce(r.approved_to,r.requested_to)>=p_month and coalesce(r.approved_from,r.requested_from)<p_month+interval '1 month')),'[]'::jsonb);
end $function$
;
alter function public.goya_management_requests(p_token text, p_month date) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.notice_published_state()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin if new.active then new.is_draft:=false; end if;return new;end $function$
;
CREATE OR REPLACE FUNCTION public.attendance_live_cutoff_at(p_operational_date date)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  rules jsonb := public.attendance_live_rules();
  tz text := coalesce(nullif(rules->>'timezone',''),'Asia/Dubai');
  cutoff_text text := coalesce(nullif(rules->>'operational_cutoff',''),'02:00');
  cutoff_time time;
begin
  begin
    cutoff_time := cutoff_text::time;
  exception when others then
    cutoff_time := '02:00'::time;
  end;

  return (((p_operational_date + 1)::text || ' ' || cutoff_time::text)::timestamp at time zone tz);
end;
$function$
;
alter function public.attendance_live_cutoff_at(p_operational_date date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_management_journey(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid:=(public.require_session(p_token,false)).staff_id; result jsonb;
begin
 result:=public.goya_hr_my_journey(p_token);
 return result||jsonb_build_object('off_balance',goya_private.off_snapshot(employee));
end $function$
;
alter function public.goya_management_journey(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_live_attendance_check_out(p_token text, p_lat double precision, p_lon double precision, p_public_ip text, p_break_taken boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  s public.staff;
  verify jsonb;
  r public.attendance_live_sessions;
  before_row jsonb;
  cutoff_at timestamptz;
begin
  sess := public.require_session(p_token,false);
  select * into s from public.staff where id=sess.staff_id;
  perform pg_advisory_xact_lock(hashtext(s.id::text));

  select * into r
    from public.attendance_live_sessions
   where staff_id=s.id
     and check_out_at is null
     and coalesce(is_deleted,false)=false
   order by check_in_at desc
   limit 1;

  if r.id is null then
    raise exception 'No active Check In found';
  end if;

  cutoff_at := public.attendance_live_cutoff_at(r.operational_date);
  if now() > cutoff_at then
    if cutoff_at >= r.check_in_at then
      update public.attendance_live_sessions
         set check_out_at=cutoff_at,
             check_out_location_name='Auto Day Close',
             check_out_verified=false,
             updated_at=now()
       where id=r.id and check_out_at is null;

      begin
        perform public.attendance_live_recalculate_day_internal(s.id,r.operational_date);
      exception when undefined_function then
        null;
      end;
    end if;
    raise exception 'Check Out window closed at %',
      to_char(cutoff_at at time zone coalesce((public.attendance_live_rules()->>'timezone'),'Asia/Dubai'),'HH24:MI');
  end if;

  verify := public.attendance_live_verify_workplace(p_lat,p_lon,p_public_ip);
  if not coalesce((verify->>'ok')::boolean,false) then
    raise exception '%',coalesce(verify->>'reason','Workplace verification failed');
  end if;

  before_row := to_jsonb(r);

  update public.attendance_live_sessions
     set check_out_at=now(),
         check_out_lat=p_lat,
         check_out_lon=p_lon,
         check_out_public_ip=p_public_ip,
         check_out_location_name=verify->>'location_name',
         check_out_distance_m=nullif(verify->>'distance_m','')::numeric,
         check_out_verified=true,
         updated_at=now()
   where id=r.id
   returning * into r;

  update public.attendance_live_days
     set break_taken=coalesce(p_break_taken,true),
         is_deleted=false,
         deleted_at=null,
         deleted_reason=null,
         updated_at=now()
   where staff_id=s.id and operational_date=r.operational_date;

  begin
    perform public.attendance_live_recalculate_day_internal(s.id,r.operational_date);
  exception when undefined_function then
    null;
  end;

  insert into public.attendance_live_audit(
    staff_id,operational_date,session_id,actor_type,action,before_data,after_data
  ) values(
    s.id,r.operational_date,r.id,'staff','CHECK_OUT',before_row,
    jsonb_build_object('session',to_jsonb(r),'verification',verify,'break_taken',p_break_taken)
  );

  return jsonb_build_object('ok',true,'session',to_jsonb(r),'verification',verify,'server_now',now());
end;
$function$
;
alter function public.staff_live_attendance_check_out(p_token text, p_lat double precision, p_lon double precision, p_public_ip text, p_break_taken boolean) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_admin_profile(p_token text, p_staff uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.require_session(p_token,true);
  return (select to_jsonb(p) from goya_private.staff_hr_profiles p where p.staff_id=p_staff);
end $function$
;
alter function public.goya_hr_admin_profile(p_token text, p_staff uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_save_staff(p_token text, p_row jsonb, p_profile jsonb, p_expected timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := nullif(p_row->>'id','')::uuid;
  previous goya_private.staff_hr_profiles;
  cessation date := nullif(p_profile->>'last_day','')::date;
  saved jsonb;
begin
  perform public.require_session(p_token,true);
  if employee is not null then
    perform 1 from public.staff where id=employee for update;
    if not found then raise exception 'Staff member was not found'; end if;
    select * into previous from goya_private.staff_hr_profiles where staff_id=employee;
    if previous.updated_at is distinct from p_expected then
      raise exception 'The employment profile changed. Open it again before saving.';
    end if;
  end if;
  if cessation is not null then
    p_row := p_row || jsonb_build_object('active',false);
  end if;
  saved := public.admin_save_staff(p_token,p_row);
  if employee is null and cessation is null and coalesce(nullif(p_profile->>'joining_date',''),
    nullif(p_profile->>'position',''),nullif(p_profile->>'manager_notes','')) is null then
    insert into goya_private.staff_hr_profiles(staff_id) values((saved->>'id')::uuid);
    return;
  end if;
  perform public.goya_hr_save_profile(p_token,(saved->>'id')::uuid,
    p_profile || jsonb_build_object('employee_code',coalesce(previous.employee_code,''),'branch','GOYA'));
end $function$
;
alter function public.goya_hr_save_staff(p_token text, p_row jsonb, p_profile jsonb, p_expected timestamp with time zone) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_pnl_history(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.require_session(p_token,true);
  return coalesce((select jsonb_agg(to_jsonb(r) order by start_date desc,end_date desc)
    from goya_private.pnl_reports r),'[]'::jsonb);
end;
$function$
;
alter function public.goya_pnl_history(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_pnl_save(p_token text, p_start date, p_end date, p_payload jsonb, p_expected timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.require_session(p_token,true);
  if p_expected is null then
    insert into goya_private.pnl_reports(start_date,end_date,payload)
    values(p_start,p_end,p_payload) on conflict do nothing;
  else
    update goya_private.pnl_reports set payload=p_payload,updated_at=clock_timestamp()
    where start_date=p_start and end_date=p_end and updated_at=p_expected;
  end if;
  if not found then raise exception 'This period already exists or changed. Reload Report History.'; end if;
  return true;
end;
$function$
;
alter function public.goya_pnl_save(p_token text, p_start date, p_end date, p_payload jsonb, p_expected timestamp with time zone) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_pnl_delete(p_token text, p_start date, p_end date, p_expected timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.require_session(p_token,true);
  delete from goya_private.pnl_reports where start_date=p_start and end_date=p_end and updated_at=p_expected;
  if not found then raise exception 'This report changed. Reload Report History.'; end if;
  return true;
end;
$function$
;
alter function public.goya_pnl_delete(p_token text, p_start date, p_end date, p_expected timestamp with time zone) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_withdraw_request(p_token text, p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := (public.require_session(p_token,false)).staff_id;
begin
  perform 1 from public.staff where id=employee and active for update;
  if not found then raise exception 'Unauthorized'; end if;
  update goya_private.staff_leave_requests set state='Withdrawn',updated_at=clock_timestamp()
    where id=p_id and staff_id=employee and state='Pending';
  if not found then raise exception 'Only your pending requests can be withdrawn'; end if;
  insert into goya_private.staff_hr_audit(staff_id,event,details)
    values(employee,'Leave withdrawn',jsonb_build_object('request',p_id));
end $function$
;
alter function public.goya_hr_withdraw_request(p_token text, p_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_documents(p_token text, p_staff uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := goya_private.document_staff(p_token,p_staff);
begin
  return (with versions as (
    select d.id,d.category,d.file_name,d.mime_type,d.byte_size,d.uploaded_at,d.custom_title,d.expires_on,
      row_number() over (partition by d.category order by d.uploaded_at desc,d.id desc) as version_rank
    from goya_private.staff_document_versions d where d.staff_id=employee and d.uploaded_at is not null)
  select coalesce(jsonb_agg(to_jsonb(v) order by v.category,v.version_rank),'[]'::jsonb)
  from versions v where p_staff is not null or v.version_rank=1);
end
$function$
;
alter function public.goya_hr_documents(p_token text, p_staff uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.submit_production(p_token text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; s public.staff; gid uuid; it jsonb; n int:=0;
begin
  sess := public.require_session(p_token,false);
  select * into s from public.staff where id=sess.staff_id;
  if not s.can_production then raise exception 'Production access disabled'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'No production items'; end if;
  gid:=gen_random_uuid();
  for it in select * from jsonb_array_elements(p_items) loop
    insert into public.production_batches(batch_group_id,name,sku,quantity,unit,storage_quantity,ingredients_quantity,logged_by)
    values(gid,trim(it->>'name'),trim(it->>'sku'),(it->>'quantity')::numeric,trim(it->>'unit'),
      nullif(it->>'storage_quantity','')::numeric,nullif(it->>'ingredients_quantity','')::numeric,s.name);
    n:=n+1;
  end loop;
  return jsonb_build_object('group_id',gid,'count',n);
end;
$function$
;
alter function public.submit_production(p_token text, p_items jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_complaints(p_token text, p_month date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sd date;ed date;
begin perform public.require_session(p_token,true);sd:=date_trunc('month',p_month)::date;ed:=(sd+interval '1 month')::date;return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.complaint_feedback x where x.created_at>=sd and x.created_at<ed),'[]'::jsonb);end $function$
;
alter function public.admin_complaints(p_token text, p_month date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_document_reserve(p_token text, p_id uuid, p_category text, p_name text, p_type text, p_size integer, p_sha text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := goya_private.document_staff(p_token,null);
  folder text;
  version goya_private.staff_document_versions;
begin
  select employee_code into folder from goya_private.staff_hr_profiles where staff_id=employee;
  if folder is null or folder !~ '^GY-[0-9]{3,}$' then
    folder := left(coalesce(nullif(regexp_replace(folder,'[^A-Za-z0-9_-]','-','g'),''),'Staff'),80)
      ||'--'||employee::text;
  end if;
  insert into goya_private.staff_document_versions(id,staff_id,category,file_name,mime_type,byte_size,sha256,folder_key)
    values(p_id,employee,p_category,p_name,p_type,p_size,p_sha,folder)
    on conflict(id) do nothing;
  select * into version from goya_private.staff_document_versions where id=p_id and staff_id=employee;
  if not found or (version.category,version.file_name,version.mime_type,version.byte_size,version.sha256)
    is distinct from (p_category,p_name,p_type,p_size,p_sha) then
    raise exception 'Upload ID already used';
  end if;
  return jsonb_build_object('folder',version.folder_key,'complete',version.uploaded_at is not null);
end $function$
;
alter function public.goya_hr_document_reserve(p_token text, p_id uuid, p_category text, p_name text, p_type text, p_size integer, p_sha text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_document_complete(p_token text, p_id uuid, p_drive text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := goya_private.document_staff(p_token,null);
begin
  perform 1 from public.staff where id=employee and active for update;
  if not found then raise exception 'Unauthorized'; end if;
  update goya_private.staff_document_versions
    set drive_file_id=p_drive,uploaded_at=coalesce(uploaded_at,clock_timestamp())
    where id=p_id and staff_id=employee and (drive_file_id is null or drive_file_id=p_drive)
      and p_drive is not null;
  if not found then raise exception 'Upload is unavailable'; end if;
end $function$
;
alter function public.goya_hr_document_complete(p_token text, p_id uuid, p_drive text) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.prevent_resigned_staff_activation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.active and exists(select 1 from goya_private.staff_hr_profiles p where p.staff_id=new.id and p.last_day is not null) then
    raise exception 'Rejoin the staff member from Staff Records before activating';
  end if;
  return new;
end $function$
;
alter function goya_private.prevent_resigned_staff_activation() owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.staff_leave_email_recipients()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(
    (select jsonb_build_object('owner_email',owner_email,'hr_email',hr_email,'revision',revision)
      from goya_private.staff_leave_email_settings where id),
    jsonb_build_object('owner_email',null,'hr_email',null,'revision',0)
  );
$function$
;
CREATE OR REPLACE FUNCTION public.goya_hr_admin_requests(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.require_session(p_token,true);
  return coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('name',s.name) order by r.created_at desc)
    from goya_private.staff_leave_requests r join public.staff s on s.id=r.staff_id
    where p_month is null or (coalesce(approved_to,requested_to)>=p_month
      and coalesce(approved_from,requested_from)<p_month+interval '1 month')),'[]'::jsonb);
end $function$
;
alter function public.goya_hr_admin_requests(p_token text, p_month date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_document_private_file(p_token text, p_id uuid, p_staff uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := goya_private.document_staff(p_token,p_staff);
begin
  return (select to_jsonb(d) from goya_private.staff_document_versions d
    where d.id=p_id and d.staff_id=employee and d.uploaded_at is not null
    and (p_staff is not null or not exists (
      select 1 from goya_private.staff_document_versions newer
      where newer.staff_id=employee and newer.category=d.category and newer.uploaded_at is not null
      and (newer.uploaded_at,newer.id)>(d.uploaded_at,d.id))));
end $function$
;
alter function public.goya_hr_document_private_file(p_token text, p_id uuid, p_staff uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_my_journey(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := (public.require_session(p_token,false)).staff_id;
begin
  if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized'; end if;
  return jsonb_build_object('profile',(select jsonb_build_object('joining_date',joining_date,'employee_code',employee_code,
    'position',position,'branch',branch,'mobile',mobile,'email',email,'address',address,'nationality',nationality,'date_of_birth',date_of_birth,'employment_type',employment_type,'probation_end',probation_end,'emergency_name',emergency_name,'emergency_relationship',emergency_relationship,'emergency_phone',emergency_phone) from goya_private.staff_hr_profiles where staff_id=employee),
    'archived_pending_off',(select jsonb_build_object('value',pending_off,'week',source_week)
      from goya_private.roster_excel_archive where staff_id=employee and pending_off<>'' order by source_week desc,source_row desc limit 1),
    'archived_annual_days',coalesce((select jsonb_agg(distinct item->>'date')
      from goya_private.roster_excel_archive a cross join lateral jsonb_array_elements(a.shifts) item
      where a.staff_id=employee and lower(btrim(item->>'value'))='annual leave'),'[]'::jsonb),
    'requests',coalesce((select jsonb_agg(to_jsonb(r)-'drive_file_id'-'staff_id' order by requested_from desc,created_at desc)
      from goya_private.staff_leave_requests r where r.staff_id=employee),'[]'::jsonb));
end $function$
;
alter function public.goya_hr_my_journey(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_review(p_token text, p_id uuid, p_expected timestamp with time zone, p_state text, p_from date, p_to date, p_payroll text, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare previous goya_private.staff_leave_requests;
begin
  perform public.require_session(p_token,true);
  select * into previous from goya_private.staff_leave_requests where id=p_id;
  if p_state is null or p_state not in ('Approved','Declined') or length(coalesce(p_note,''))>2000
    or (p_state='Approved' and (p_from is null or p_to is null or p_to<p_from or p_payroll is null or p_payroll not in ('Paid','Unpaid')))
    or (p_state='Declined' and p_payroll is distinct from 'Absent' and p_payroll is not null)
    or (p_payroll='Absent' and previous.kind<>'Sick Leave') then raise exception 'Invalid leave decision'; end if;
  perform 1 from public.staff where id=previous.staff_id for update;
  if p_state='Approved' and exists(select 1 from goya_private.staff_leave_requests other
    where other.staff_id=previous.staff_id and other.id<>p_id and other.state='Approved'
      and other.approved_from<=p_to and other.approved_to>=p_from) then
    raise exception 'There is already approved leave for part of this period';
  end if;
  update goya_private.staff_leave_requests set state=p_state, approved_from=case when p_state='Approved' then p_from end,
    approved_to=case when p_state='Approved' then p_to end,payroll=p_payroll,review_note=coalesce(p_note,''),updated_at=clock_timestamp()
    where id=p_id and updated_at=p_expected;
  if not found then raise exception 'Request changed. Reload before saving.'; end if;
  insert into goya_private.staff_hr_audit(staff_id,event,details) values(previous.staff_id,'Leave reviewed',
    jsonb_build_object('request',p_id,'prior_state',previous.state,'prior_from',previous.approved_from,'prior_to',previous.approved_to,
      'prior_payroll',previous.payroll,'prior_note',previous.review_note));
end $function$
;
alter function public.goya_hr_review(p_token text, p_id uuid, p_expected timestamp with time zone, p_state text, p_from date, p_to date, p_payroll text, p_note text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_delete_inventory_session(p_token text, p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin perform public.require_session(p_token,true); delete from public.inventory_sessions where id=p_id; return true; end; $function$
;
alter function public.admin_delete_inventory_session(p_token text, p_id uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_admin_classify_day(p_token text, p_staff_id uuid, p_date date, p_classification text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare oldv jsonb; newv public.attendance_live_days; begin
  perform public.require_session(p_token,true);
  if not goya_private.employed_on(p_staff_id,p_date) then raise exception 'The day is outside employment dates'; end if;
  if p_classification not in ('Duty','Day Off - Pending Review','Weekly Off','Annual Leave','Leave','Sick Leave','Unpaid Leave','Absent','Public Holiday','Other Approved') then
    raise exception 'Invalid attendance classification';
  end if;
  select to_jsonb(d) into oldv from public.attendance_live_days d where d.staff_id=p_staff_id and d.operational_date=p_date;
  insert into public.attendance_live_days(staff_id,operational_date,classification,classification_note)
  values(p_staff_id,p_date,p_classification,nullif(trim(coalesce(p_note,'')),''))
  on conflict(branch_id,staff_id,operational_date) do update set classification=excluded.classification,classification_note=excluded.classification_note,is_deleted=false,deleted_at=null,deleted_reason=null,updated_at=now()
  returning * into newv;
  insert into public.attendance_live_audit(staff_id,operational_date,actor_type,action,before_data,after_data)
  values(p_staff_id,p_date,'admin','CLASSIFY_DAY',oldv,to_jsonb(newv));
  return to_jsonb(newv);
end $function$
;
alter function public.attendance_live_admin_classify_day(p_token text, p_staff_id uuid, p_date date, p_classification text, p_note text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_staff_dashboard(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare sess public.app_sessions; current_day jsonb; month_start date;
begin
 sess:=public.require_session(p_token,false);
 current_day:=public.staff_live_attendance_status(p_token);
 month_start:=date_trunc('month',timezone('Asia/Dubai',now()))::date;
 return jsonb_build_object('server_now',now(),'today',current_day,'month',month_start,
 'attendance',public.staff_live_attendance_history(p_token,month_start),
 'legacy',public.staff_attendance_month_v12(p_token,month_start),
 'notices',(select coalesce(jsonb_agg(to_jsonb(n) order by n.important desc,n.published_at desc),'[]'::jsonb) from goya_private.notices n where active and published_at<=now() and (expires_at is null or expires_at>now())),
 'orders',jsonb_build_object('Pending',(select count(*) from public.orders where status='Pending'),'Ordered',(select count(*) from public.orders where status='Ordered'),'Received',(select count(*) from public.orders where status='Received' and created_at>=month_start),'Not Received',(select count(*) from public.orders where status='Not Received' and created_at>=month_start)),
 'operations',jsonb_build_object('production',(select count(*) from public.production_batches where created_at>=month_start),'wastage',(select count(*) from public.wastage_entries where created_at>=month_start)),
 'push_public_key',(select public_key from goya_private.push_config where id));
end $function$
;
alter function public.goya_staff_dashboard(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_management_profiles(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.require_session(p_token,true);
 return coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'active',s.active,'sections',s.sections,'profile',to_jsonb(p),
 'off_balance',goya_private.off_snapshot(s.id),'resignation',to_jsonb(r),
 'history',coalesce((select jsonb_agg(to_jsonb(a) order by a.id desc) from goya_private.staff_hr_audit a where a.staff_id=s.id),'[]'::jsonb)) order by s.active desc,s.name)
 from public.staff s left join goya_private.staff_hr_profiles p on p.staff_id=s.id
 left join goya_private.staff_resignations r on r.staff_id=s.id),'[]'::jsonb);
end $function$
;
alter function public.goya_management_profiles(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_save_supplier(p_token text, p_row jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare x public.suppliers;
begin perform public.require_session(p_token,true);if nullif(p_row->>'id','') is null then insert into public.suppliers(name,phone,email,active) values(trim(p_row->>'name'),nullif(trim(p_row->>'phone'),''),nullif(trim(p_row->>'email'),''),coalesce((p_row->>'active')::boolean,true)) returning * into x;else update public.suppliers set name=trim(p_row->>'name'),phone=nullif(trim(p_row->>'phone'),''),email=nullif(trim(p_row->>'email'),''),active=coalesce((p_row->>'active')::boolean,active),updated_at=now() where id=(p_row->>'id')::uuid returning * into x;end if;return to_jsonb(x);end $function$
;
alter function public.admin_save_supplier(p_token text, p_row jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_live_attendance_history(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  sd date:=date_trunc('month',p_month)::date;
  ed date:=(date_trunc('month',p_month)+interval '1 month - 1 day')::date;
  rules jsonb:=public.attendance_live_rules();
  sys_start date:=coalesce((rules->>'system_start_date')::date,sd);
  today_local date:=timezone(coalesce(rules->>'timezone','Asia/Dubai'),now())::date;
begin
  sess:=public.require_session(p_token,false);
  ed:=least(ed,today_local);
  if ed<sd then return jsonb_build_object('server_now',now(),'rows','[]'::jsonb,'rules',rules); end if;
  return jsonb_build_object('server_now',now(),'rules',rules,'rows',coalesce((
    with dates as (
      select g::date operational_date from generate_series(greatest(sd,sys_start),ed,interval '1 day') g
      union select d.operational_date from public.attendance_live_days d where d.staff_id=sess.staff_id and d.operational_date between sd and ed and coalesce(d.is_deleted,false)=false
      union select x.operational_date from public.attendance_live_sessions x where x.staff_id=sess.staff_id and x.operational_date between sd and ed and coalesce(x.is_deleted,false)=false
    )
    select jsonb_agg(to_jsonb(q) order by q.operational_date desc) from (
      select z.operational_date,coalesce(d.break_taken,true) break_taken,coalesce(d.split_shift_allowed,false) split_shift_allowed,
        case when exists(select 1 from public.attendance_live_sessions sx where sx.staff_id=sess.staff_id and sx.operational_date=z.operational_date and coalesce(sx.is_deleted,false)=false)
             then coalesce(nullif(d.classification,'Day Off - Pending Review'),'Duty') else coalesce(d.classification,'Day Off - Pending Review') end classification,
        d.classification_note,d.ot_policy,d.scheduled_start,coalesce(d.late_minutes,0) late_minutes,
        coalesce((select jsonb_agg(to_jsonb(x) order by x.check_in_at,x.created_at) from public.attendance_live_sessions x
          where x.staff_id=sess.staff_id and x.operational_date=z.operational_date and coalesce(x.is_deleted,false)=false),'[]'::jsonb) sessions
      from dates z left join public.attendance_live_days d on d.staff_id=sess.staff_id and d.operational_date=z.operational_date and coalesce(d.is_deleted,false)=false
      where goya_private.employed_on(sess.staff_id,z.operational_date)
    ) q
  ),'[]'::jsonb));
end $function$
;
alter function public.staff_live_attendance_history(p_token text, p_month date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_staff_open_orders(p_token text, p_status text DEFAULT 'Pending'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.require_session(p_token,false);
 if p_status not in ('Pending','Ordered') then raise exception 'Invalid open order status'; end if;
 return jsonb_build_object('orders',(select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb) from (select o.id,g.order_no,o.name,o.sku,o.quantity,o.unit,o.supplier,o.status,o.received_date,o.logged_by,o.notes,o.created_at from public.orders o join public.order_groups g on g.id=o.order_group_id where o.status=p_status)q));
end $function$
;
alter function public.goya_staff_open_orders(p_token text, p_status text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_admin_save_notice(p_token text, p_value jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n goya_private.notices; nid uuid:=nullif(p_value->>'id','')::uuid;
begin
 perform public.require_session(p_token,true);
 if nid is not null and exists(select 1 from goya_private.notices where id=nid and deleted_at is not null) then raise exception 'This notice was deleted. Create a new notice instead.';end if;
 if length(trim(coalesce(p_value->>'title','')))=0 or length(trim(coalesce(p_value->>'body','')))=0 then raise exception 'Title and notice are required'; end if;
 if nullif(p_value->>'expires_at','')::timestamptz <= coalesce(nullif(p_value->>'published_at','')::timestamptz,case when nid is not null then (select published_at from goya_private.notices where id=nid) end,now()) then raise exception 'Expiry must be after the published date'; end if;
 if nid is null then
 insert into goya_private.notices(title,body,important,active,expires_at,published_at) values(trim(p_value->>'title'),trim(p_value->>'body'),coalesce((p_value->>'important')::boolean,false),coalesce((p_value->>'active')::boolean,true),nullif(p_value->>'expires_at','')::timestamptz,coalesce(nullif(p_value->>'published_at','')::timestamptz,now())) returning * into n;
 else
 update goya_private.notices set title=trim(p_value->>'title'),body=trim(p_value->>'body'),important=coalesce((p_value->>'important')::boolean,false),active=coalesce((p_value->>'active')::boolean,true),expires_at=nullif(p_value->>'expires_at','')::timestamptz,published_at=coalesce(nullif(p_value->>'published_at','')::timestamptz,published_at),updated_at=now() where id=nid and deleted_at is null returning * into n;
 if not found then raise exception 'Notice not found';end if;
 end if;
 
 if coalesce((p_value->>'send_push')::boolean,false) then
  if not n.active or not n.important then raise exception 'Mobile notification requires an Important, published notice';end if;
  if n.expires_at is not null and n.expires_at<=now() then raise exception 'Expired notices cannot send notifications';end if;
  insert into goya_private.notice_push_jobs(notice_id) values(n.id) on conflict(notice_id) do nothing;
 end if;
 if not n.active or not n.important then
  update goya_private.notice_push_jobs set cancelled_at=coalesce(cancelled_at,now()) where notice_id=n.id;
 end if;
 return to_jsonb(n)||jsonb_build_object('push_requested',exists(select 1 from goya_private.notice_push_jobs where notice_id=n.id));

end $function$
;
alter function public.goya_admin_save_notice(p_token text, p_value jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_change_pin(p_token text, p_current_pin text, p_new_pin text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare h text;
begin
  perform public.require_session(p_token,true);
  select pin_hash into h from public.admin_credentials where id=1;
  if h<>extensions.crypt(trim(p_current_pin),h) then raise exception 'Current admin PIN is incorrect'; end if;
  if trim(p_new_pin)!~ '^\d{4,12}$' then raise exception 'New admin PIN must be 4 to 12 digits'; end if;
  update public.admin_credentials set pin_hash=extensions.crypt(trim(p_new_pin),extensions.gen_salt('bf')),updated_at=now() where id=1;
  return true;
end $function$
;
alter function public.admin_change_pin(p_token text, p_current_pin text, p_new_pin text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_update_order_quantity(p_token text, p_id bigint, p_quantity numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare x public.orders;
begin
  perform public.require_session(p_token,true);
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;
  update public.orders
     set quantity=p_quantity
   where id=p_id
   returning * into x;
  if x.id is null then raise exception 'Order item not found'; end if;
  return to_jsonb(x);
end $function$
;
alter function public.admin_update_order_quantity(p_token text, p_id bigint, p_quantity numeric) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_push_worker_config()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ select to_jsonb(c) from goya_private.push_config c where id $function$
;
alter function public.goya_push_worker_config() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_save_info_page(p_token text, p_row jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare x public.info_pages;u text:=nullif(trim(p_row->>'url'),'');
begin perform public.require_session(p_token,true);if u is not null and u!~* '^https?://' then raise exception 'URL must start with http:// or https://';end if;if nullif(p_row->>'id','') is null then insert into public.info_pages(title,body,url,active,sort_order) values(trim(p_row->>'title'),coalesce(p_row->>'body',''),u,coalesce((p_row->>'active')::boolean,true),coalesce((p_row->>'sort_order')::int,0)) returning * into x;else update public.info_pages set title=trim(p_row->>'title'),body=coalesce(p_row->>'body',''),url=u,active=coalesce((p_row->>'active')::boolean,active),sort_order=coalesce((p_row->>'sort_order')::int,sort_order),updated_at=now() where id=(p_row->>'id')::uuid returning * into x;end if;return to_jsonb(x);end $function$
;
alter function public.admin_save_info_page(p_token text, p_row jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.require_session(p_token text, p_admin boolean DEFAULT false)
 RETURNS app_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.app_sessions;
begin
  select * into s from public.app_sessions
  where token = p_token and expires_at > now() and is_admin = p_admin;
  if s.token is null then raise exception 'Session expired or unauthorized'; end if;
  if not p_admin and not exists(select 1 from goya_private.branch_members b where b.branch_id=goya_private.current_branch() and b.staff_id=s.staff_id) then raise exception 'You do not have access to this branch';end if; return s;
end;
$function$
;
alter function public.require_session(p_token text, p_admin boolean) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_login(p_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare s public.staff;t text;
begin
  select * into s from public.staff where active=true and pin_hash=extensions.crypt(trim(p_pin),pin_hash) limit 1;
  if s.id is null then raise exception 'Invalid PIN or staff is inactive'; end if;
  delete from public.app_sessions where expires_at<now();
  t:=encode(extensions.gen_random_bytes(32),'hex');
  insert into public.app_sessions(token,staff_id,is_admin) values(t,s.id,false);
  return jsonb_build_object('token',t,'staff_id',s.id,'name',s.name,'access',jsonb_build_object('order',s.can_order,'production',s.can_production,'wastage',s.can_wastage,'inventory',s.can_inventory,'sections',s.sections));
end $function$
;
alter function public.staff_login(p_pin text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_login(p_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare t text;h text;
begin
  select pin_hash into h from public.admin_credentials where id=1;
  if h is null or h<>extensions.crypt(trim(p_pin),h) then raise exception 'Invalid admin PIN'; end if;
  delete from public.app_sessions where expires_at<now();
  t:=encode(extensions.gen_random_bytes(32),'hex');
  insert into public.app_sessions(token,staff_id,is_admin) values(t,null,true);
  return jsonb_build_object('token',t,'is_admin',true);
end $function$
;
alter function public.admin_login(p_pin text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.submit_wastage(p_token text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; s public.staff; gid uuid; it jsonb; n int:=0; sq numeric; iq numeric;
begin
  sess := public.require_session(p_token,false);
  select * into s from public.staff where id=sess.staff_id;
  if not s.can_wastage then raise exception 'Wastage access disabled'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'No wastage items'; end if;
  gid:=gen_random_uuid();
  for it in select * from jsonb_array_elements(p_items) loop
    sq := nullif(it->>'storage_quantity','')::numeric;
    iq := nullif(it->>'ingredients_quantity','')::numeric;
    insert into public.wastage_entries(wastage_group_id,name,sku,quantity,unit,storage_quantity,ingredients_quantity,reason,logged_by)
    values(gid,trim(it->>'name'),trim(it->>'sku'),(it->>'quantity')::numeric,trim(it->>'unit'),sq,iq,trim(it->>'reason'),s.name);
    n:=n+1;
  end loop;
  return jsonb_build_object('group_id',gid,'count',n);
end;
$function$
;
alter function public.submit_wastage(p_token text, p_items jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_orders(p_token text, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_status text DEFAULT NULL::text, p_supplier text DEFAULT NULL::text, p_search text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.require_session(p_token,true);
  return coalesce((
    select jsonb_agg(to_jsonb(q) order by q.created_at desc)
    from (
      select o.*, g.order_no,g.branch_snapshot, g.submitted_at, g.notes as group_notes
      from public.orders o join public.order_groups g on g.id=o.order_group_id
      where (p_from is null or o.created_at>=p_from)
        and (p_to is null or o.created_at<p_to)
        and (p_status is null or p_status='' or o.status=p_status)
        and (p_supplier is null or p_supplier='' or coalesce(o.supplier,'')=p_supplier)
        and (p_search is null or p_search='' or lower(o.name) like '%'||lower(p_search)||'%' or lower(o.sku) like '%'||lower(p_search)||'%')
    ) q
  ),'[]'::jsonb);
end;
$function$
;
alter function public.admin_orders(p_token text, p_from timestamp with time zone, p_to timestamp with time zone, p_status text, p_supplier text, p_search text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_save_master_items(p_token text, p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it jsonb; n int:=0;
begin
  perform public.require_session(p_token,true);
  for it in select * from jsonb_array_elements(p_rows) loop
    insert into public.master_items(row_id,name,sku,storage_unit,ingredient_unit,supplier,items_type,active)
    values(coalesce(nullif(it->>'row_id','')::bigint,nextval('public.master_items_row_seq')),trim(it->>'name'),trim(it->>'sku'),trim(it->>'storage_unit'),trim(it->>'ingredient_unit'),nullif(trim(it->>'supplier'),''),trim(it->>'items_type'),coalesce((it->>'active')::boolean,true))
    on conflict(sku) do update set
      row_id=excluded.row_id,name=excluded.name,storage_unit=excluded.storage_unit,ingredient_unit=excluded.ingredient_unit,
      supplier=excluded.supplier,items_type=excluded.items_type,active=excluded.active,updated_at=now();
    n:=n+1;
  end loop;
  return n;
end;
$function$
;
alter function public.admin_save_master_items(p_token text, p_rows jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_save_internal_items(p_token text, p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it jsonb; n int:=0;
begin
  perform public.require_session(p_token,true);
  for it in select * from jsonb_array_elements(p_rows) loop
    insert into public.internal_items(row_id,name,sku,storage_unit,ingredient_unit,items_type,active)
    values(coalesce(nullif(it->>'row_id','')::bigint,nextval('public.internal_items_row_seq')),trim(it->>'name'),trim(it->>'sku'),trim(it->>'storage_unit'),trim(it->>'ingredient_unit'),trim(it->>'items_type'),coalesce((it->>'active')::boolean,true))
    on conflict(sku) do update set
      row_id=excluded.row_id,name=excluded.name,storage_unit=excluded.storage_unit,ingredient_unit=excluded.ingredient_unit,
      items_type=excluded.items_type,active=excluded.active,updated_at=now();
    n:=n+1;
  end loop;
  return n;
end;
$function$
;
alter function public.admin_save_internal_items(p_token text, p_rows jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.submit_order(p_token text, p_notes text, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions;s public.staff;gid uuid;it jsonb;n int:=0;order_no text;
begin
  sess:=public.require_session(p_token,false);select * into s from public.staff where id=sess.staff_id;
  if not s.can_order then raise exception 'Order access disabled'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'No items in order'; end if;
  gid:=gen_random_uuid();order_no:=case when goya_private.current_branch()='00000000-0000-0000-0000-000000000001' then 'GOYA-' else 'EVENT-' end||to_char(now(),'YYYYMMDD-HH24MISS')||'-'||substr(replace(gid::text,'-',''),1,5);
  insert into public.order_groups(id,order_no,submitted_by,staff_name,notes) values(gid,order_no,s.id,s.name,null);
  for it in select * from jsonb_array_elements(p_items) loop
    insert into public.orders(order_group_id,name,sku,quantity,unit,supplier,logged_by,notes) values(gid,trim(it->>'name'),trim(it->>'sku'),(it->>'quantity')::numeric,trim(it->>'unit'),nullif(trim(it->>'supplier'),''),s.name,nullif(trim(it->>'notes'),''));n:=n+1;
  end loop;
  return jsonb_build_object('order_group_id',gid,'order_no',order_no,'count',n);
end $function$
;
alter function public.submit_order(p_token text, p_notes text, p_items jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.submit_complaint_feedback(p_token text, p_type text, p_details text, p_hide_identity boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions;s public.staff;x public.complaint_feedback;
begin sess:=public.require_session(p_token,false);select * into s from public.staff where id=sess.staff_id;if p_type not in ('Complain','Feedback') then raise exception 'Invalid type';end if;if nullif(trim(p_details),'') is null then raise exception 'Details are required';end if;insert into public.complaint_feedback(staff_id,staff_name,type,details,hide_identity) values(s.id,s.name,p_type,trim(p_details),coalesce(p_hide_identity,false)) returning * into x;return jsonb_build_object('id',x.id,'submitted',true);end $function$
;
alter function public.submit_complaint_feedback(p_token text, p_type text, p_details text, p_hide_identity boolean) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_bootstrap(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.require_session(p_token,true);
  return jsonb_build_object(
    'master_items',(select coalesce(jsonb_agg(to_jsonb(x) order by lower(x.name)),'[]'::jsonb) from public.master_items x),
    'internal_items',(select coalesce(jsonb_agg(to_jsonb(x) order by lower(x.name)),'[]'::jsonb) from public.internal_items x),
    'suppliers',(select coalesce(jsonb_agg(to_jsonb(x) order by lower(x.name)),'[]'::jsonb) from public.suppliers x),
    'staff',(select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'pin_code',x.pin_code,'active',x.active,'can_order',x.can_order,'can_production',x.can_production,'can_wastage',x.can_wastage,'can_inventory',x.can_inventory,'sections',x.sections) order by lower(x.name)),'[]'::jsonb) from public.staff x),
    'settings',(select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) from public.settings),
    'info_pages',(select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.title),'[]'::jsonb) from public.info_pages x),
    'inventory_sessions',(select coalesce(jsonb_agg(to_jsonb(q) order by q.month desc),'[]'::jsonb) from (select v.*,(select coalesce(array_agg(s.name order by s.name),'{}'::text[]) from public.staff s where s.id=any(v.assigned_staff_ids)) assigned_names from public.inventory_sessions v)q)
  );
end $function$
;
alter function public.admin_bootstrap(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_save_master_item(p_token text, p_row jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare x public.master_items;
begin perform public.require_session(p_token,true);if nullif(p_row->>'id','') is null then insert into public.master_items(name,sku,storage_unit,ingredient_unit,supplier,items_type,active) values(trim(p_row->>'name'),trim(p_row->>'sku'),trim(p_row->>'storage_unit'),trim(p_row->>'ingredient_unit'),nullif(trim(p_row->>'supplier'),''),trim(p_row->>'items_type'),true) returning * into x;else update public.master_items set name=trim(p_row->>'name'),sku=trim(p_row->>'sku'),storage_unit=trim(p_row->>'storage_unit'),ingredient_unit=trim(p_row->>'ingredient_unit'),supplier=nullif(trim(p_row->>'supplier'),''),items_type=trim(p_row->>'items_type'),active=true,updated_at=now() where id=(p_row->>'id')::uuid returning * into x;end if;return to_jsonb(x);end $function$
;
alter function public.admin_save_master_item(p_token text, p_row jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_save_internal_item(p_token text, p_row jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare x public.internal_items;
begin perform public.require_session(p_token,true);if nullif(p_row->>'id','') is null then insert into public.internal_items(name,sku,storage_unit,ingredient_unit,items_type,active) values(trim(p_row->>'name'),trim(p_row->>'sku'),trim(p_row->>'storage_unit'),trim(p_row->>'ingredient_unit'),trim(p_row->>'items_type'),true) returning * into x;else update public.internal_items set name=trim(p_row->>'name'),sku=trim(p_row->>'sku'),storage_unit=trim(p_row->>'storage_unit'),ingredient_unit=trim(p_row->>'ingredient_unit'),items_type=trim(p_row->>'items_type'),active=true,updated_at=now() where id=(p_row->>'id')::uuid returning * into x;end if;return to_jsonb(x);end $function$
;
alter function public.admin_save_internal_item(p_token text, p_row jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_save_staff(p_token text, p_row jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$ declare x public.staff;newpin text:=trim(p_row->>'pin');
begin
  perform public.require_session(p_token,true);if newpin!~ '^\d{4}$' then raise exception 'Staff PIN must be 4 digits';end if;
  if nullif(p_row->>'id','') is null then insert into public.staff(name,pin_hash,pin_code,active,can_order,can_production,can_wastage,can_inventory,sections) values(trim(p_row->>'name'),extensions.crypt(newpin,extensions.gen_salt('bf')),newpin,coalesce((p_row->>'active')::boolean,true),coalesce((p_row->>'can_order')::boolean,true),coalesce((p_row->>'can_production')::boolean,true),coalesce((p_row->>'can_wastage')::boolean,true),coalesce((p_row->>'can_inventory')::boolean,false),coalesce(array(select jsonb_array_elements_text(coalesce(p_row->'sections','[]'::jsonb))),'{}')) returning * into x;
  else update public.staff set name=trim(p_row->>'name'),pin_hash=extensions.crypt(newpin,extensions.gen_salt('bf')),pin_code=newpin,active=coalesce((p_row->>'active')::boolean,active),can_order=coalesce((p_row->>'can_order')::boolean,can_order),can_production=coalesce((p_row->>'can_production')::boolean,can_production),can_wastage=coalesce((p_row->>'can_wastage')::boolean,can_wastage),can_inventory=coalesce((p_row->>'can_inventory')::boolean,can_inventory),sections=coalesce(array(select jsonb_array_elements_text(coalesce(p_row->'sections','[]'::jsonb))),sections),updated_at=now() where id=(p_row->>'id')::uuid returning * into x;end if;
  return jsonb_build_object('id',x.id,'name',x.name,'pin_code',x.pin_code,'active',x.active,'sections',x.sections);
end $function$
;
alter function public.admin_save_staff(p_token text, p_row jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_inventory_counts(p_token text, p_month date DEFAULT CURRENT_DATE, p_section text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform public.require_session(p_token,true);return coalesce((select jsonb_agg(to_jsonb(q) order by q.counted_at desc) from (select c.*,s.month,s.title from public.inventory_counts c join public.inventory_sessions s on s.id=c.session_id where date_trunc('month',s.month)=date_trunc('month',p_month) and (p_section is null or p_section='' or lower(c.section)=lower(p_section)))q),'[]'::jsonb);end $function$
;
alter function public.admin_inventory_counts(p_token text, p_month date, p_section text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_production_wastage(p_token text, p_kind text, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin perform public.require_session(p_token,true);if p_kind='production' then return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.production_batches x where (p_from is null or x.created_at>=p_from) and (p_to is null or x.created_at<=p_to) and (p_status is null or p_status='' or x.admin_status=p_status)),'[]'::jsonb);elsif p_kind='wastage' then return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.wastage_entries x where (p_from is null or x.created_at>=p_from) and (p_to is null or x.created_at<=p_to) and (p_status is null or p_status='' or x.admin_status=p_status)),'[]'::jsonb);else raise exception 'Invalid kind';end if;end $function$
;
alter function public.admin_production_wastage(p_token text, p_kind text, p_from timestamp with time zone, p_to timestamp with time zone, p_status text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_update_pw_status(p_token text, p_kind text, p_ids bigint[], p_status text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare n int;
begin perform public.require_session(p_token,true);if p_status not in ('Pending','Done') then raise exception 'Invalid status';end if;if p_kind='production' then update public.production_batches set admin_status=p_status where id=any(p_ids);get diagnostics n=row_count;elsif p_kind='wastage' then update public.wastage_entries set admin_status=p_status where id=any(p_ids);get diagnostics n=row_count;else raise exception 'Invalid kind';end if;return n;end $function$
;
alter function public.admin_update_pw_status(p_token text, p_kind text, p_ids bigint[], p_status text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_inventory_save_session(p_token text, p_row jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare x public.inventory_sessions;nid uuid:=nullif(p_row->>'id','')::uuid;begin
 perform public.require_session(p_token,true);
 if nid is null then
  insert into public.inventory_sessions(month,title,notice_text,active,sections,assigned_staff_ids,shared_count,counting_date) values((p_row->>'month')::date,nullif(p_row->>'title',''),nullif(p_row->>'notice_text',''),coalesce((p_row->>'active')::boolean,false),array(select jsonb_array_elements_text(coalesce(p_row->'sections','[]'))),array(select jsonb_array_elements_text(coalesce(p_row->'assigned_staff_ids','[]'))::uuid),true,coalesce(nullif(p_row->>'counting_date','')::date,timezone('Asia/Dubai',now())::date)) returning * into x;
 else
  select * into x from public.inventory_sessions where id=nid for update;if not found then raise exception 'Session not found';end if;
  if exists(select 1 from goya_private.inventory_shared_sheets where session_id=nid) and (coalesce(nullif(p_row->>'counting_date','')::date,x.counting_date) is distinct from x.counting_date or (p_row->>'month')::date is distinct from x.month) then raise exception 'Counting date/month is fixed after a shared sheet starts. Create a new session for a new count.';end if;
  update public.inventory_sessions set month=(p_row->>'month')::date,title=nullif(p_row->>'title',''),notice_text=nullif(p_row->>'notice_text',''),active=coalesce((p_row->>'active')::boolean,active),sections=array(select jsonb_array_elements_text(coalesce(p_row->'sections','[]'))),assigned_staff_ids=array(select jsonb_array_elements_text(coalesce(p_row->'assigned_staff_ids','[]'))::uuid),counting_date=coalesce(nullif(p_row->>'counting_date','')::date,counting_date),updated_at=now() where id=nid returning * into x;
 end if;return to_jsonb(x);
end $function$
;
alter function public.admin_inventory_save_session(p_token text, p_row jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_export_dataset(p_token text, p_dataset text, p_month date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare sd date;ed date;
begin
  perform public.require_session(p_token,true);if p_month is not null then sd:=date_trunc('month',p_month)::date;ed:=(sd+interval '1 month')::date;end if;
  case p_dataset
    when 'orders' then return coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from (select g.order_no,g.branch_snapshot,o.name,o.sku,o.quantity,o.unit,o.supplier,o.status,o.received_date,o.logged_by,o.notes,o.created_at from public.orders o join public.order_groups g on g.id=o.order_group_id where p_month is null or (o.created_at>=sd and o.created_at<ed))q),'[]'::jsonb);
    when 'production' then return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.production_batches x where p_month is null or (x.created_at>=sd and x.created_at<ed)),'[]'::jsonb);
    when 'wastage' then return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.wastage_entries x where p_month is null or (x.created_at>=sd and x.created_at<ed)),'[]'::jsonb);
    when 'inventory' then return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.inventory_counts x where p_month is null or (x.created_at>=sd and x.created_at<ed)),'[]'::jsonb);
    when 'complaints' then return coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from public.complaint_feedback x where p_month is null or (x.created_at>=sd and x.created_at<ed)),'[]'::jsonb);
    when 'master_items' then return coalesce((select jsonb_agg(to_jsonb(x) order by lower(x.name)) from public.master_items x),'[]'::jsonb);
    when 'internal_items' then return coalesce((select jsonb_agg(to_jsonb(x) order by lower(x.name)) from public.internal_items x),'[]'::jsonb);
    when 'staff' then return coalesce((select jsonb_agg(jsonb_build_object('name',x.name,'pin',x.pin_code,'active',x.active,'orders',x.can_order,'production',x.can_production,'wastage',x.can_wastage,'inventory',x.can_inventory,'sections',array_to_string(x.sections,', ')) order by lower(x.name)) from public.staff x),'[]'::jsonb);
    when 'suppliers' then return coalesce((select jsonb_agg(to_jsonb(x) order by lower(x.name)) from public.suppliers x),'[]'::jsonb);
    when 'equipment' then return coalesce((select jsonb_agg(to_jsonb(q) order by q."Submitted at" desc) from
      (select incident_date as "Incident date",item_name as "Item",quantity as "Quantity",section as "Section",staff_name as "Reported by",details as "Reason / details",status as "Status",admin_note as "Resolution / admin note",created_at as "Submitted at",updated_at as "Updated at"
       from goya_private.equipment_reports where p_month is null or (incident_date>=sd and incident_date<ed))q),'[]'::jsonb);
    else raise exception 'Invalid dataset';
  end case;
end $function$
;
alter function public.admin_export_dataset(p_token text, p_dataset text, p_month date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_delete_history_rows(p_token text, p_kind text, p_ids bigint[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  n integer:=0;
  affected jsonb:='[]'::jsonb;
  r record;
begin
  perform public.require_session(p_token,true);
  if coalesce(array_length(p_ids,1),0)=0 then return 0; end if;

  case lower(trim(p_kind))
    when 'production' then
      delete from public.production_batches where id=any(p_ids);
      get diagnostics n=row_count;
    when 'wastage' then
      delete from public.wastage_entries where id=any(p_ids);
      get diagnostics n=row_count;
    when 'inventory' then
      select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb)
      into affected
      from (
        select distinct session_id,staff_id,section
        from public.inventory_counts
        where id=any(p_ids)
      ) q;

      delete from public.inventory_counts where id=any(p_ids);
      get diagnostics n=row_count;

      -- If all count rows for a submitted staff/session/section were deleted,
      -- also clear its completion marker so Staff Portal no longer shows Done.
      for r in
        select * from jsonb_to_recordset(affected)
        as x(session_id uuid,staff_id uuid,section text)
      loop
        if not exists(
          select 1 from public.inventory_counts c
          where c.session_id=r.session_id
            and c.staff_id=r.staff_id
            and lower(c.section)=lower(r.section)
        ) then
          delete from public.inventory_submissions s
          where s.session_id=r.session_id
            and s.staff_id=r.staff_id
            and lower(s.section)=lower(r.section);
          delete from public.inventory_drafts d
          where d.session_id=r.session_id
            and d.staff_id=r.staff_id
            and lower(d.section)=lower(r.section);
        end if;
      end loop;
    when 'complaints' then
      delete from public.complaint_feedback where id=any(p_ids);
      get diagnostics n=row_count;
    else
      raise exception 'Invalid history type';
  end case;
  return n;
end $function$
;
alter function public.admin_delete_history_rows(p_token text, p_kind text, p_ids bigint[]) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.due_reminders()
 RETURNS TABLE(subscription_id uuid, staff_id uuid, operational_date date, target_minutes integer, remaining_minutes integer, subscription jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with rules as (select public.attendance_live_rules() r),
 active as (select s.staff_id,s.operational_date,sum(extract(epoch from(coalesce(s.check_out_at,now())-s.check_in_at))/60) worked,
 bool_or(s.check_out_at is null) is_open from public.attendance_live_sessions s join public.staff st on st.id=s.staff_id and st.active
 where not s.is_deleted and s.operational_date>=public.attendance_live_operational_date(now())-1
 group by s.staff_id,s.operational_date),
 due as (select a.*,case when coalesce((r.r->>'force_no_break')::boolean,false) then 480 when coalesce(d.break_taken,true) then 540 else 480 end target
 from active a cross join rules r left join public.attendance_live_days d using(staff_id,operational_date)
 where a.is_open and now()<=public.attendance_live_cutoff_at(a.operational_date))
 select p.id,p.staff_id,a.operational_date,a.target,greatest(0,ceil(a.target-a.worked)::int),p.subscription
 from due a join goya_private.push_subscriptions p on p.staff_id=a.staff_id and p.active
 where a.worked>=a.target-15 and a.worked<a.target
$function$
;
alter function goya_private.due_reminders() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.admin_inventory_reset_count(p_token text, p_session_id uuid, p_staff_id uuid, p_section text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  deleted_counts integer:=0;
  deleted_drafts integer:=0;
  deleted_submissions integer:=0;
begin
  perform public.require_session(p_token,true);
  if exists(select 1 from public.inventory_sessions where id=p_session_id and shared_count) then return public.goya_admin_inventory_reopen(p_token,p_session_id,p_section);end if;

  if not exists(select 1 from public.inventory_sessions where id=p_session_id) then
    raise exception 'Inventory session not found';
  end if;
  if not exists(select 1 from public.staff where id=p_staff_id) then
    raise exception 'Staff not found';
  end if;
  if coalesce(trim(p_section),'')='' then
    raise exception 'Section is required';
  end if;

  delete from public.inventory_counts
  where session_id=p_session_id
    and staff_id=p_staff_id
    and lower(section)=lower(trim(p_section));
  get diagnostics deleted_counts=row_count;

  delete from public.inventory_drafts
  where session_id=p_session_id
    and staff_id=p_staff_id
    and lower(section)=lower(trim(p_section));
  get diagnostics deleted_drafts=row_count;

  delete from public.inventory_submissions
  where session_id=p_session_id
    and staff_id=p_staff_id
    and lower(section)=lower(trim(p_section));
  get diagnostics deleted_submissions=row_count;

  return jsonb_build_object(
    'ok',true,
    'deleted_counts',deleted_counts,
    'deleted_drafts',deleted_drafts,
    'deleted_submissions',deleted_submissions
  );
end $function$
;
alter function public.admin_inventory_reset_count(p_token text, p_session_id uuid, p_staff_id uuid, p_section text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_annual_history(p_token text, p_staff uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := goya_private.document_staff(p_token,p_staff);
begin
  return (select coalesce(jsonb_agg(to_jsonb(h)-'staff_id' order by h.service_year desc,h.leave_from desc nulls last,h.id),'[]')
    from goya_private.staff_annual_history h where h.staff_id=employee);
end $function$
;
alter function public.goya_hr_annual_history(p_token text, p_staff uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_save_annual_history(p_token text, p_staff uuid, p_id uuid, p_expected timestamp with time zone, p_source uuid, p_year date, p_from date, p_to date, p_note text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare joined date;
  today date := (now() at time zone 'Asia/Dubai')::date;
  result uuid;
begin
  perform public.require_session(p_token,true);
  perform 1 from public.staff where id=p_staff for update;
  if not found then raise exception 'Staff record unavailable.'; end if;
  select joining_date into joined from goya_private.staff_hr_profiles where staff_id=p_staff;
  if joined is null then raise exception 'Add a joining date in Staff Management first.'; end if;
  if p_year is null or p_year < joined or p_year > today or
     p_year <> (joined + make_interval(years=>extract(year from p_year)::int-extract(year from joined)::int))::date
  then raise exception 'Choose a valid service year.'; end if;
  if (p_from is null) <> (p_to is null) or p_to < p_from or p_from < joined or p_to >= today
     or (p_from is null and (joined + make_interval(years=>extract(year from p_year)::int-extract(year from joined)::int+1))::date > today)
  then raise exception 'Enter both past leave dates, or leave dates blank for an earlier service year.'; end if;
  if p_source is not null and not exists (select 1 from goya_private.staff_leave_requests r
    where r.id=p_source and r.staff_id=p_staff and r.kind='Annual Leave' and r.state='Approved' and r.approved_to < today)
  then raise exception 'This annual leave record is unavailable.'; end if;
  if p_expected is null then
    insert into goya_private.staff_annual_history(id,staff_id,source_id,service_year,leave_from,leave_to,note)
      values(p_id,p_staff,p_source,p_year,p_from,p_to,coalesce(p_note,''))
      on conflict do nothing returning id into result;
    if result is null then
      select id into result from goya_private.staff_annual_history h where h.id=p_id and h.staff_id=p_staff
      and (h.source_id,h.service_year,h.leave_from,h.leave_to,h.note)
        is not distinct from (p_source,p_year,p_from,p_to,coalesce(p_note,''));
    end if;
  else
    update goya_private.staff_annual_history h set service_year=p_year,leave_from=p_from,leave_to=p_to,
      note=coalesce(p_note,''),updated_at=clock_timestamp() where h.id=p_id and h.staff_id=p_staff
      and h.updated_at=p_expected returning id into result;
  end if;
  if result is null then raise exception 'The record changed. Reopen the staff card and try again.'; end if;
  return result;
end $function$
;
alter function public.goya_hr_save_annual_history(p_token text, p_staff uuid, p_id uuid, p_expected timestamp with time zone, p_source uuid, p_year date, p_from date, p_to date, p_note text) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.apply_resignations()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare plan record; total integer:=0;
begin
 for plan in select * from goya_private.staff_resignations where applied_at is null and cancelled_at is null
  and last_working_day<(now() at time zone 'Asia/Dubai')::date loop
  perform 1 from public.staff where id=plan.staff_id for update;
  select * into plan from goya_private.staff_resignations where staff_id=plan.staff_id and applied_at is null and cancelled_at is null and last_working_day<(now() at time zone 'Asia/Dubai')::date for update;
  if not found then continue; end if;
  insert into goya_private.staff_hr_profiles(staff_id,last_day) values(plan.staff_id,plan.last_working_day)
  on conflict(staff_id) do update set last_day=excluded.last_day,updated_at=clock_timestamp();
  update public.staff set active=false where id=plan.staff_id;
  update public.app_sessions set expires_at=now() where staff_id=plan.staff_id and not is_admin and expires_at>now();
  update goya_private.staff_resignations set applied_at=clock_timestamp() where staff_id=plan.staff_id;
  insert into goya_private.staff_hr_audit(staff_id,event,details) values(plan.staff_id,'Resignation',
   jsonb_build_object('last_day',plan.last_working_day,'actor',plan.actor,'note',plan.note));
  total:=total+1;
 end loop;
 return total;
end $function$
;
alter function goya_private.apply_resignations() owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_management_balances(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.require_session(p_token,true);
 return coalesce((select jsonb_object_agg(id::text,goya_private.off_snapshot(id)) from public.staff),'{}'::jsonb);
end $function$
;
alter function public.goya_management_balances(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_management_cancel_resignation(p_token text, p_staff uuid, p_expected timestamp with time zone, p_actor text, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.require_session(p_token,true);
 if length(btrim(coalesce(p_actor,''))) not between 1 and 100 or length(btrim(coalesce(p_note,''))) not between 1 and 2000 then raise exception 'Management name and reason required'; end if;
 perform 1 from public.staff where id=p_staff for update;
 update goya_private.staff_resignations set cancelled_at=clock_timestamp(),updated_at=clock_timestamp()
 where staff_id=p_staff and updated_at=p_expected and applied_at is null and cancelled_at is null;
 if not found then raise exception 'Resignation changed or already effective. Reopen profile.'; end if;
 insert into goya_private.staff_hr_audit(staff_id,event,details) values(p_staff,'Resignation cancelled',jsonb_build_object('actor',p_actor,'note',p_note));
end $function$
;
alter function public.goya_management_cancel_resignation(p_token text, p_staff uuid, p_expected timestamp with time zone, p_actor text, p_note text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_management_resignation(p_token text, p_staff uuid, p_day date, p_note text, p_actor text, p_expected timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare prior goya_private.staff_resignations; joined date;
begin
 perform public.require_session(p_token,true);
 if p_day is null or length(btrim(coalesce(p_actor,''))) not between 1 and 100 or length(coalesce(p_note,''))>4000 then raise exception 'Enter last working day and management name'; end if;
 perform 1 from public.staff where id=p_staff for update;
 if not found then raise exception 'Staff not found'; end if;
 select joining_date into joined from goya_private.staff_hr_profiles where staff_id=p_staff;
 if p_day<joined then raise exception 'Last working day must be on or after joining date'; end if;
 select * into prior from goya_private.staff_resignations where staff_id=p_staff;
 if prior.updated_at is distinct from p_expected then raise exception 'Resignation changed. Reopen profile.'; end if;
 if p_day >= (now() at time zone 'Asia/Dubai')::date and exists(select 1 from goya_private.staff_hr_profiles where staff_id=p_staff and last_day is not null) then raise exception 'Use Rejoin before scheduling a new resignation'; end if;
 insert into goya_private.staff_resignations(staff_id,last_working_day,note,actor) values(p_staff,p_day,coalesce(p_note,''),p_actor)
 on conflict(staff_id) do update set last_working_day=excluded.last_working_day,note=excluded.note,actor=excluded.actor,
 updated_at=clock_timestamp(),cancelled_at=null,applied_at=null;
 insert into goya_private.staff_hr_audit(staff_id,event,details) values(p_staff,'Resignation scheduled',
 jsonb_build_object('before',to_jsonb(prior),'last_day',p_day,'actor',p_actor,'note',p_note,'session_ref',md5(p_token)));
end $function$
;
alter function public.goya_management_resignation(p_token text, p_staff uuid, p_day date, p_note text, p_actor text, p_expected timestamp with time zone) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_management_review(p_token text, p_id uuid, p_expected timestamp with time zone, p_state text, p_from date, p_to date, p_payroll text, p_note text, p_actor text, p_private_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare prior goya_private.staff_leave_requests; after_row goya_private.staff_leave_requests;
 old_days integer:=0; new_days integer:=0; balance jsonb; plan goya_private.staff_resignations;
begin
 perform public.require_session(p_token,true);
 if length(btrim(coalesce(p_actor,''))) not between 1 and 100 or length(coalesce(p_private_note,''))>2000
  or length(coalesce(p_note,''))>2000
  or (p_state='Declined' and length(btrim(coalesce(p_note,'')))=0) then raise exception 'Management name and a staff-visible rejection reason are required (maximum 2000 characters)'; end if;
 select * into prior from goya_private.staff_leave_requests where id=p_id;
 if not found then raise exception 'Request not found'; end if;
 perform 1 from public.staff where id=prior.staff_id for update;
 select * into prior from goya_private.staff_leave_requests where id=p_id for update;
 if prior.state in ('Withdrawn','Recorded') then raise exception 'This request cannot be reviewed'; end if;
 if prior.updated_at is distinct from p_expected then raise exception 'Request changed. Reload before saving.'; end if;
 if p_state='Approved' and prior.kind<>'Resignation' then
  perform goya_private.apply_off_credits(prior.staff_id);
  perform goya_private.release_roster_off(p_token,prior.staff_id,p_from,p_to,p_actor);
 end if;
 if prior.kind='Resignation' then
  if p_state not in ('Approved','Declined') or (p_state='Approved' and (p_from is null or p_from is distinct from p_to)) then raise exception 'Choose one last working day'; end if;
  if p_state='Approved' then
   select * into plan from goya_private.staff_resignations where staff_id=prior.staff_id;
   perform public.goya_management_resignation(p_token,prior.staff_id,p_from,p_private_note,p_actor,plan.updated_at);
  elsif prior.state='Approved' then raise exception 'Use Cancel resignation or Rejoin in the staff profile'; end if;
  update goya_private.staff_leave_requests set state=p_state,approved_from=case when p_state='Approved' then p_from end,
   approved_to=case when p_state='Approved' then p_from end,payroll=case when p_state='Approved' then 'Unpaid' end,
   review_note=coalesce(p_note,''),updated_at=clock_timestamp() where id=p_id;
 else
  if prior.kind in ('Pending Off','Advance Off') then
   if prior.state='Approved' then old_days:=prior.approved_to-prior.approved_from+1; end if;
   if p_state='Approved' then new_days:=p_to-p_from+1; end if;
   balance:=goya_private.off_snapshot(prior.staff_id);
   if prior.kind='Pending Off' and new_days>old_days and new_days-old_days>(balance->>'balance')::integer then raise exception 'Not enough pending off. Use Advance Off or correct the balance.'; end if;
  end if;
  perform public.goya_hr_review(p_token,p_id,p_expected,p_state,p_from,p_to,p_payroll,p_note);
  if new_days is distinct from old_days then
   perform public.goya_management_save_balance(p_token,prior.staff_id,(balance->>'balance')::integer+old_days-new_days,
    (balance->>'revision')::integer,'Request '||p_id::text||' · '||p_private_note,p_actor);
  end if;
 end if;
 select * into after_row from goya_private.staff_leave_requests where id=p_id;
 insert into goya_private.staff_management_decisions(request_id,actor,session_ref,note,before_data,after_data)
 values(p_id,p_actor,md5(p_token),coalesce(p_private_note,''),to_jsonb(prior),to_jsonb(after_row));
end $function$
;
alter function public.goya_management_review(p_token text, p_id uuid, p_expected timestamp with time zone, p_state text, p_from date, p_to date, p_payroll text, p_note text, p_actor text, p_private_note text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_people_document_expiry(p_token text, p_id uuid, p_staff uuid, p_expires date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid:=goya_private.document_staff(p_token,p_staff);
begin
 update goya_private.staff_document_versions set expires_on=p_expires where id=p_id and staff_id=employee;
 if not found then raise exception 'Document not found'; end if;
end $function$
;
alter function public.goya_people_document_expiry(p_token text, p_id uuid, p_staff uuid, p_expires date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_portal_export_summary(p_token text, p_dataset text, p_month date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare total bigint; sd date:=date_trunc('month',p_month)::date; ed date:=(sd+interval '1 month')::date;
begin
 perform public.require_session(p_token,true);
 case p_dataset
 when 'orders' then select count(*) into total from public.orders o join public.order_groups g on g.id=o.order_group_id where p_month is null or (o.created_at>=sd and o.created_at<ed);
 when 'production' then select count(*) into total from public.production_batches where p_month is null or (created_at>=sd and created_at<ed);
 when 'wastage' then select count(*) into total from public.wastage_entries where p_month is null or (created_at>=sd and created_at<ed);
 when 'inventory' then select count(*) into total from public.inventory_counts where p_month is null or (created_at>=sd and created_at<ed);
 when 'complaints' then select count(*) into total from public.complaint_feedback where p_month is null or (created_at>=sd and created_at<ed);
 when 'equipment' then select count(*) into total from goya_private.equipment_reports where p_month is null or (incident_date>=sd and incident_date<ed);
 when 'master_items' then select count(*) into total from public.master_items;
 when 'internal_items' then select count(*) into total from public.internal_items;
 when 'staff' then select count(*) into total from public.staff;
 when 'suppliers' then select count(*) into total from public.suppliers;
 else raise exception 'Invalid dataset'; end case;
 return jsonb_build_object('count',total,'month',case when p_dataset in ('master_items','internal_items','staff','suppliers') then null else sd end);
end $function$
;
alter function public.goya_portal_export_summary(p_token text, p_dataset text, p_month date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_people_email_draft(p_token text, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid:=(public.require_session(p_token,false)).staff_id; request goya_private.staff_leave_requests; recipients jsonb;
begin
 select * into request from goya_private.staff_leave_requests where id=p_request and staff_id=employee and kind in ('Annual Leave','Resignation') and state not in ('Withdrawn','Declined');
 if not found then raise exception 'Request is not available for email'; end if;
 if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized'; end if;
 recipients:=public.goya_hr_worker_email_settings();
 return jsonb_build_object('owner',recipients->>'owner_email','hr',recipients->>'hr_email','manager',recipients->>'manager_email',
 'staff',(select jsonb_build_object('name',s.name,'code',p.employee_code,'position',p.position,'mobile',p.mobile) from public.staff s left join goya_private.staff_hr_profiles p on p.staff_id=s.id where s.id=employee),
 'request',to_jsonb(request)-'drive_file_id'-'review_note'-'staff_id');
end $function$
;
alter function public.goya_people_email_draft(p_token text, p_request uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.attendance_live_management_month(p_key text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sd date:=date_trunc('month',p_month)::date;
  ed date:=(date_trunc('month',p_month)+interval '1 month - 1 day')::date;
  rules jsonb:=public.attendance_live_rules();
  today_local date:=timezone(coalesce(rules->>'timezone','Asia/Dubai'),now())::date;
  sys_start date:=coalesce((rules->>'system_start_date')::date,sd);
begin
  if not public.attendance_live_management_validate(p_key) then
    raise exception 'Invalid or expired management link';
  end if;
  sd:=greatest(sd,sys_start);
  ed:=least(ed,today_local);
  if ed<sd then return jsonb_build_object('server_now',now(),'rows','[]'::jsonb); end if;

  return jsonb_build_object(
    'server_now',now(),
    'rules',jsonb_build_object(
      'duty_presence_minutes',coalesce((rules->>'duty_presence_minutes')::int,540),
      'regular_net_minutes',coalesce((rules->>'regular_net_minutes')::int,480),
      'break_minutes',coalesce((rules->>'break_minutes')::int,60)
    ),
    'rows',coalesce((
      select jsonb_agg(to_jsonb(q) order by q.operational_date desc,q.staff_name)
      from (
        select g::date operational_date,s.id staff_id,s.name staff_name,
          coalesce(d.break_taken,true) break_taken,
          case when exists(select 1 from public.attendance_live_sessions sx
                           where sx.staff_id=s.id and sx.operational_date=g::date and coalesce(sx.is_deleted,false)=false)
               then coalesce(nullif(d.classification,'Day Off - Pending Review'),'Duty')
               else coalesce(d.classification,'Day Off - Pending Review') end classification,
          d.ot_policy,d.scheduled_start,coalesce(d.late_minutes,0) late_minutes,
          coalesce((select jsonb_agg(jsonb_build_object(
                     'session_no',x.session_no,'check_in_at',x.check_in_at,'check_out_at',x.check_out_at,
                     'check_in_verified',x.check_in_verified,'check_out_verified',x.check_out_verified)
                     order by x.session_no)
                    from public.attendance_live_sessions x
                    where x.staff_id=s.id and x.operational_date=g::date and coalesce(x.is_deleted,false)=false),'[]'::jsonb) sessions
        from goya_private.branch_staff_history s
        cross join generate_series(sd,ed,interval '1 day') g
        left join public.attendance_live_days d
          on d.staff_id=s.id and d.operational_date=g::date and coalesce(d.is_deleted,false)=false
        where (s.active=true or exists(select 1 from goya_private.staff_hr_profiles hp where hp.staff_id=s.id and hp.last_day is not null)) and goya_private.employed_on(s.id,g::date) and goya_private.branch_employee_on(s.id,g::date)
      ) q
    ),'[]'::jsonb)
  );
end $function$
;
alter function public.attendance_live_management_month(p_key text, p_month date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_roster_my_week(p_token text, p_week date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_staff_id uuid;
begin
  v_staff_id := (public.require_session(p_token,false)).staff_id;
  if not exists(select 1 from goya_private.branch_staff s where s.id=v_staff_id and s.active) then
    raise exception using message='Not authorized',errcode='28000';
  end if;
  return jsonb_build_object('week',(select jsonb_build_object(
      'days',(select jsonb_agg(case when goya_private.employed_on(v_staff_id,p_week+ord::int-1) then value else 'null'::jsonb end order by ord) from jsonb_array_elements(p.schedule->'staff'->v_staff_id::text) with ordinality days(value,ord)),'notes',p.schedule->>'notes','published_at',p.published_at)
    from goya_private.roster_weeks w join goya_private.roster_publications p
      on p.week_start=w.week_start and p.revision=w.published_revision
    where w.week_start=p_week and (p.schedule->'staff')?v_staff_id::text),
    'latest_publication',(select jsonb_build_object('week',w.week_start,'published_at',p.published_at,'revision',p.revision)
      from goya_private.roster_weeks w join goya_private.roster_publications p
      on p.week_start=w.week_start and p.revision=w.published_revision
      where w.week_start+6 >= (now() at time zone 'Asia/Dubai')::date and (p.schedule->'staff') ? v_staff_id::text
      order by p.published_at desc limit 1),
    'weeks',coalesce((select jsonb_agg(w.week_start order by w.week_start desc)
    from goya_private.roster_weeks w join goya_private.roster_publications p
      on p.week_start=w.week_start and p.revision=w.published_revision
    where (p.schedule->'staff')?v_staff_id::text),'[]'::jsonb));
end $function$
;
alter function public.goya_roster_my_week(p_token text, p_week date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_attendance_month_v12(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; sd date; ed date; a public.attendance_staff; rules jsonb;
begin
 sess:=public.require_session(p_token,false);
 select * into a from public.attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a.id is null then return jsonb_build_object('records','[]'::jsonb,'submissions','[]'::jsonb,'staff','{}'::jsonb); end if;
 a_id:=a.id; sd:=date_trunc('month',p_month)::date; ed:=(sd+interval '1 month')::date;
 select coalesce(value,'{}'::jsonb) into rules from public.attendance_settings where key='rules';
 return jsonb_build_object(
   'staff',to_jsonb(a) || jsonb_build_object(
      'late_grace_minutes',coalesce((rules->>'late_grace_minutes')::int,15),
      'shift_start_times',coalesce(rules->'shift_start_times',jsonb_build_array(coalesce(rules->>'operational_start','08:00')))
   ),
   'records',coalesce((select jsonb_agg(to_jsonb(r) order by r.operational_date) from public.attendance_records r where goya_private.employed_on(sess.staff_id,r.operational_date) and r.attendance_staff_id=a_id and r.operational_date>=sd and r.operational_date<ed),'[]'::jsonb),
   'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.operational_date,s.submitted_at desc) from public.attendance_staff_submissions s where goya_private.employed_on(sess.staff_id,s.operational_date) and s.attendance_staff_id=a_id and s.operational_date>=sd and s.operational_date<ed),'[]'::jsonb)
 );
end $function$
;
alter function public.staff_attendance_month_v12(p_token text, p_month date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.staff_live_attendance_check_in(p_token text, p_lat double precision, p_lon double precision, p_public_ip text, p_rejoin boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  sess public.app_sessions;
  s public.staff;
  od date := public.attendance_live_operational_date(now());
  verify jsonb;
  sh jsonb;
  open_row public.attendance_live_sessions;
  prior_count int := 0;
  next_no int := 1;
  new_row public.attendance_live_sessions;
  d public.attendance_live_days;
  cutoff_at timestamptz;
begin
  sess := public.require_session(p_token,false);
  select * into s from public.staff where id=sess.staff_id and active=true;
  if s.id is null then raise exception 'Staff account is inactive or unavailable'; end if;
  if not goya_private.employed_on(s.id,od) then raise exception 'Attendance is available only within your employment dates'; end if;
  perform pg_advisory_xact_lock(hashtext(s.id::text));

  select * into open_row
    from public.attendance_live_sessions
   where staff_id=s.id
     and check_out_at is null
     and coalesce(is_deleted,false)=false
   order by check_in_at desc
   limit 1;

  if open_row.id is not null then
    cutoff_at := public.attendance_live_cutoff_at(open_row.operational_date);
    if now() <= cutoff_at then
      return jsonb_build_object(
        'ok',true,'duplicate',true,'message','Already checked in',
        'session',to_jsonb(open_row),'server_now',now()
      );
    elsif cutoff_at >= open_row.check_in_at then
      update public.attendance_live_sessions
         set check_out_at=cutoff_at,
             check_out_location_name='Auto Day Close',
             check_out_verified=false,
             updated_at=now()
       where id=open_row.id
         and check_out_at is null;

      begin
        perform public.attendance_live_recalculate_day_internal(s.id,open_row.operational_date);
      exception when undefined_function then
        null;
      end;
      open_row := null;
    else
      raise exception 'An older live session needs Admin review before a new Check In.';
    end if;
  end if;

  select count(*) into prior_count
    from public.attendance_live_sessions
   where staff_id=s.id
     and operational_date=od
     and coalesce(is_deleted,false)=false;

  if p_rejoin and prior_count=0 then
    raise exception 'No completed duty session found to rejoin';
  end if;
  if not p_rejoin and prior_count>0 then
    raise exception 'You already worked today. Use Rejoin for a new split-shift session.';
  end if;

  verify := public.attendance_live_verify_workplace(p_lat,p_lon,p_public_ip);
  if not coalesce((verify->>'ok')::boolean,false) then
    raise exception '%',coalesce(verify->>'reason','Workplace verification failed');
  end if;

  sh := public.attendance_live_shift_info(now());
  next_no := prior_count+1;

  insert into public.attendance_live_sessions(
    staff_id,operational_date,session_no,check_in_at,
    check_in_lat,check_in_lon,check_in_public_ip,check_in_location_name,
    check_in_distance_m,check_in_verified,is_deleted
  ) values(
    s.id,od,next_no,now(),p_lat,p_lon,p_public_ip,verify->>'location_name',
    nullif(verify->>'distance_m','')::numeric,true,false
  ) returning * into new_row;

  insert into public.attendance_live_days(
    staff_id,operational_date,break_taken,classification,scheduled_start,
    late_minutes,is_deleted,deleted_at,deleted_reason
  ) values(
    s.id,od,true,'Duty',nullif(sh->>'scheduled_start','')::time,
    case when next_no=1 then coalesce((sh->>'late_minutes')::int,0) else 0 end,
    false,null,null
  )
  on conflict(branch_id,staff_id,operational_date) do update set
    classification='Duty',
    is_deleted=false,
    deleted_at=null,
    deleted_reason=null,
    scheduled_start=case when next_no=1 then excluded.scheduled_start else coalesce(public.attendance_live_days.scheduled_start,excluded.scheduled_start) end,
    late_minutes=case when next_no=1 then excluded.late_minutes else public.attendance_live_days.late_minutes end,
    updated_at=now()
  returning * into d;

  insert into public.attendance_live_audit(staff_id,operational_date,session_id,actor_type,action,after_data)
  values(
    s.id,od,new_row.id,'staff',case when p_rejoin then 'REJOIN' else 'CHECK_IN' end,
    jsonb_build_object('session',to_jsonb(new_row),'verification',verify)
  );

  return jsonb_build_object(
    'ok',true,'duplicate',false,'session',to_jsonb(new_row),
    'day',to_jsonb(d),'verification',verify,'server_now',now()
  );
end;
$function$
;
alter function public.staff_live_attendance_check_in(p_token text, p_lat double precision, p_lon double precision, p_public_ip text, p_rejoin boolean) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_management_report(p_token text, p_staff uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.require_session(p_token,true);
 return jsonb_build_object(
 'attendance',coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('sessions',coalesce((select jsonb_agg(jsonb_build_object('check_in_at',s.check_in_at,'check_out_at',s.check_out_at) order by s.check_in_at) from public.attendance_live_sessions s where s.staff_id=d.staff_id and s.operational_date=d.operational_date and not s.is_deleted),'[]'::jsonb)) order by d.operational_date desc) from public.attendance_live_days d where d.staff_id=p_staff and goya_private.employed_on(d.staff_id,d.operational_date) and not d.is_deleted),'[]'::jsonb),
 'rosters',coalesce((select jsonb_agg(jsonb_build_object('week',r.week_start,'revision',r.revision,'days',r.schedule->'staff'->p_staff::text) order by r.week_start desc,r.revision desc) from goya_private.roster_publications r where r.schedule->'staff' ? p_staff::text),'[]'::jsonb),
 'documents',coalesce((select jsonb_agg(jsonb_build_object('category',d.category,'title',d.custom_title,'file_name',d.file_name,'drive_file_id',d.drive_file_id,'uploaded_at',d.uploaded_at) order by d.uploaded_at desc) from goya_private.staff_document_versions d where d.staff_id=p_staff and d.uploaded_at is not null),'[]'::jsonb),
 'legacy_attendance',coalesce((select jsonb_agg(to_jsonb(a) order by a.operational_date desc) from public.attendance_records a join public.attendance_staff s on s.id=a.attendance_staff_id where s.portal_staff_id=p_staff and goya_private.employed_on(p_staff,a.operational_date)),'[]'::jsonb),
 'archive',coalesce((select jsonb_agg(to_jsonb(a) order by a.source_week desc,a.source_row) from goya_private.roster_excel_archive a where a.staff_id=p_staff),'[]'::jsonb),
 'annual_history',public.goya_hr_annual_history(p_token,p_staff));
end $function$
;
alter function public.goya_management_report(p_token text, p_staff uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_people_save_staff(p_token text, p_row jsonb, p_profile jsonb, p_expected timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid:=nullif(p_row->>'id','')::uuid; previous goya_private.staff_hr_profiles; saved jsonb;
begin
 perform public.require_session(p_token,true);
 if nullif(btrim(p_row->>'name'),'') is null then raise exception 'Full name is required'; end if;
 if employee is null and (nullif(p_profile->>'joining_date','') is null or nullif(btrim(p_profile->>'mobile'),'') is null
 or nullif(btrim(p_profile->>'position'),'') is null or jsonb_array_length(coalesce(p_row->'sections','[]'))=0) then
 raise exception 'Full name, joining date, mobile, position, section and PIN are required'; end if;
 if nullif(p_profile->>'date_of_birth','')::date>(now() at time zone 'Asia/Dubai')::date then raise exception 'Check date of birth'; end if;
 if nullif(p_profile->>'probation_end','')::date<nullif(p_profile->>'joining_date','')::date then raise exception 'Probation must end on or after joining'; end if;
 if employee is not null then
  perform 1 from public.staff where id=employee for update;
  if not found then raise exception 'Staff member not found'; end if;
  select * into previous from goya_private.staff_hr_profiles where staff_id=employee;
  if previous.updated_at is distinct from p_expected then raise exception 'Profile changed. Reopen it before saving.'; end if;
  if previous.last_day is not null and coalesce((p_row->>'active')::boolean,false) then raise exception 'Use Rejoin staff to reactivate'; end if;
 end if;
 if nullif(p_profile->>'last_day','') is distinct from previous.last_day::text then raise exception 'Use the resignation action to change last working day'; end if;
 saved:=public.admin_save_staff(p_token,p_row); employee:=(saved->>'id')::uuid;
 perform public.goya_hr_save_profile(p_token,employee,p_profile||jsonb_build_object('employee_code',coalesce(previous.employee_code,''),'branch','GOYA'));
 update goya_private.staff_hr_profiles set roster_group=coalesce(p_profile->>'roster_group',roster_group),mobile=left(coalesce(p_profile->>'mobile',mobile),60),email=left(coalesce(p_profile->>'email',email),254),address=left(coalesce(p_profile->>'address',address),1000),
 nationality=left(coalesce(p_profile->>'nationality',nationality),100),date_of_birth=nullif(p_profile->>'date_of_birth','')::date,
 employment_type=left(coalesce(p_profile->>'employment_type',employment_type),80),probation_end=nullif(p_profile->>'probation_end','')::date,
 emergency_name=left(coalesce(p_profile->>'emergency_name',emergency_name),120),emergency_relationship=left(coalesce(p_profile->>'emergency_relationship',emergency_relationship),80),
 emergency_phone=left(coalesce(p_profile->>'emergency_phone',emergency_phone),60) where staff_id=employee;
 return jsonb_build_object('id',employee,'profile',(select to_jsonb(p) from goya_private.staff_hr_profiles p where p.staff_id=employee));
end $function$
;
alter function public.goya_people_save_staff(p_token text, p_row jsonb, p_profile jsonb, p_expected timestamp with time zone) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_roster_published_export(p_token text, p_week date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare publication goya_private.roster_publications;
begin
  perform public.require_session(p_token,true);
  if p_week is null or extract(isodow from p_week)<>1 then raise exception 'Choose a valid roster week'; end if;
  select p.* into publication from goya_private.roster_weeks w
    join goya_private.roster_publications p on p.week_start=w.week_start and p.revision=w.published_revision
    where w.week_start=p_week;
  if not found then raise exception 'Publish this roster before downloading the PDF'; end if;
  return jsonb_build_object('week',publication.week_start,'revision',publication.revision,
    'published_at',publication.published_at,'schedule',publication.schedule,
    'staff',coalesce((select jsonb_agg(jsonb_build_object('id',m.key,'name',coalesce(s.name,'Former staff'),
      'roster_group',hp.roster_group) order by s.name,m.key)
      from jsonb_each(publication.schedule->'staff') m
      left join public.staff s on s.id::text=m.key
      left join goya_private.staff_hr_profiles hp on hp.staff_id=s.id),'[]'::jsonb));
end $function$
;
alter function public.goya_roster_published_export(p_token text, p_week date) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_portal_staff_alerts(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid; today date:=(now() at time zone 'Asia/Dubai')::date;
begin
 employee:=(public.require_session(p_token,false)).staff_id;
 if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized'; end if;
 return jsonb_build_object('staff_id',employee,'today',today,
  'requests',coalesce((select jsonb_agg(to_jsonb(q) order by q.updated_at desc) from
   (select id,kind,state,requested_from,requested_to,approved_from,approved_to,review_note,updated_at
    from goya_private.staff_leave_requests where staff_id=employee and state in ('Approved','Declined') order by updated_at desc limit 100)q),'[]'::jsonb),
  'documents',coalesce((select jsonb_agg(to_jsonb(q) order by q.expires_on) from
   (select id,category,custom_title,expires_on,expires_on-today as days_left from
    (select d.*,row_number() over(partition by category order by uploaded_at desc,id desc) rn
     from goya_private.staff_document_versions d where staff_id=employee and uploaded_at is not null)d
    where rn=1 and expires_on<=today+30)q),'[]'::jsonb));
end $function$
;
alter function public.goya_portal_staff_alerts(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_portal_admin_summary(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare today date:=(now() at time zone 'Asia/Dubai')::date;
begin
 perform public.require_session(p_token,true);
 return jsonb_build_object(
  'pending_requests',(select count(*) from goya_private.staff_leave_requests where state='Pending'),
  'unresolved_equipment',(select count(*) from goya_private.equipment_reports where status in ('Pending','Reviewed')),
  'equipment',coalesce((select jsonb_agg(jsonb_build_object('item_name',item_name,'status',status,'staff_name',staff_name,'incident_date',incident_date) order by created_at desc) from goya_private.equipment_reports where status in ('Pending','Reviewed')),'[]'::jsonb),
  'documents',coalesce((select jsonb_agg(to_jsonb(q) order by q.expires_on,q.name) from
   (select d.staff_id,s.name,d.category,d.custom_title,d.expires_on,d.expires_on-today as days_left from
    (select staff_id,category,custom_title,expires_on,row_number() over(partition by staff_id,category order by uploaded_at desc,id desc) rn
     from goya_private.staff_document_versions where uploaded_at is not null)d
    join public.staff s on s.id=d.staff_id and s.active where rn=1 and expires_on<=today+30)q),'[]'::jsonb));
end $function$
;
alter function public.goya_portal_admin_summary(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_portal_duplicate_check(p_token text, p_kind text, p_items jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.app_sessions;s public.staff; cutoff timestamptz:=now()-interval '10 minutes';
begin
 a:=public.require_session(p_token,false);select * into s from public.staff where id=a.staff_id and active;
 if s.id is null then raise exception 'Unauthorized';end if;
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>500 then raise exception 'Invalid submission';end if;
 if p_kind='equipment' then
  return exists(select 1 from goya_private.equipment_reports r where r.staff_id=s.id and r.created_at>=cutoff
   and r.item_name=btrim(p_items->0->>'item_name') and r.quantity=btrim(coalesce(p_items->0->>'quantity',''))
   and r.details=btrim(p_items->0->>'details') and r.section=coalesce(p_items->0->>'section','') and r.incident_date=(p_items->0->>'incident_date')::date);
 elsif p_kind='orders' then
  if not s.can_order then raise exception 'Order access disabled';end if;
  return exists(select 1 from public.order_groups g where g.submitted_by=s.id and g.created_at>=cutoff and
   (select jsonb_agg(jsonb_build_array(btrim(o.name),btrim(o.sku),o.quantity,btrim(o.unit),coalesce(o.supplier,''),coalesce(o.notes,'')) order by btrim(o.name),btrim(o.sku),o.quantity,btrim(o.unit),coalesce(o.supplier,''),coalesce(o.notes,'')) from public.orders o where o.order_group_id=g.id)=
   (select jsonb_agg(jsonb_build_array(btrim(i->>'name'),btrim(i->>'sku'),(i->>'quantity')::numeric,btrim(i->>'unit'),coalesce(i->>'supplier',''),coalesce(i->>'notes','')) order by btrim(i->>'name'),btrim(i->>'sku'),(i->>'quantity')::numeric,btrim(i->>'unit'),coalesce(i->>'supplier',''),coalesce(i->>'notes','')) from jsonb_array_elements(p_items)i));
 elsif p_kind in ('production','wastage') then
  if (p_kind='production' and not s.can_production) or (p_kind='wastage' and not s.can_wastage) then raise exception 'Access disabled';end if;
  return exists(with recent as (
   select batch_group_id gid,name,sku,quantity,unit,storage_quantity,ingredients_quantity,''::text reason from public.production_batches where p_kind='production' and logged_by=s.name and created_at>=cutoff
   union all select wastage_group_id,name,sku,quantity,unit,storage_quantity,ingredients_quantity,coalesce(reason,'') from public.wastage_entries where p_kind='wastage' and logged_by=s.name and created_at>=cutoff),
   grouped as(select gid,jsonb_agg(jsonb_build_array(btrim(name),btrim(sku),quantity,btrim(unit),storage_quantity,ingredients_quantity,reason) order by btrim(name),btrim(sku),quantity,btrim(unit),storage_quantity,ingredients_quantity,reason) items from recent group by gid)
   select 1 from grouped where items=(select jsonb_agg(jsonb_build_array(btrim(i->>'name'),btrim(i->>'sku'),(i->>'quantity')::numeric,btrim(i->>'unit'),nullif(i->>'storage_quantity','')::numeric,nullif(i->>'ingredients_quantity','')::numeric,case when p_kind='wastage' then btrim(coalesce(i->>'reason','')) else '' end) order by btrim(i->>'name'),btrim(i->>'sku'),(i->>'quantity')::numeric,btrim(i->>'unit'),nullif(i->>'storage_quantity','')::numeric,nullif(i->>'ingredients_quantity','')::numeric,case when p_kind='wastage' then btrim(coalesce(i->>'reason','')) else '' end) from jsonb_array_elements(p_items)i));
 else raise exception 'Invalid submission type';end if;
end $function$
;
alter function public.goya_portal_duplicate_check(p_token text, p_kind text, p_items jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_off_roster_preview(p_token text, p_week date, p_schedule jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb:='[]';employee record;b jsonb;debits int;refunds int;normal_debits int;begin
 perform public.require_session(p_token,true);
 for employee in select id,name from goya_private.branch_staff where id::text in(select key from jsonb_each(p_schedule->'staff')) or id in(select staff_id from goya_private.roster_off_charges where charged and off_date between p_week and p_week+6) order by id loop
  b:=goya_private.off_snapshot(employee.id);
  select count(*) filter(where want in ('balance','advance') and not charged),count(*) filter(where charged and (want is null or want not in ('balance','advance'))),count(*) filter(where want='balance' and not charged)
  into debits,refunds,normal_debits from (select p_schedule->'staff'->employee.id::text->d->>'off_source' want,coalesce(c.charged,false) charged from generate_series(0,6)d left join goya_private.roster_off_charges c on c.staff_id=employee.id and c.off_date=p_week+d)q;
  result:=result||jsonb_build_array(jsonb_build_object('id',employee.id,'name',employee.name,'balance',(b->>'balance')::int,'debit',debits,'refund',refunds,'projected',(b->>'balance')::int+refunds-debits,'insufficient',normal_debits>0 and (b->>'balance')::int+refunds<normal_debits));
 end loop;return result;
end $function$
;
alter function public.goya_off_roster_preview(p_token text, p_week date, p_schedule jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.reconcile_roster_off(p_token text, p_week date, p_snapshot jsonb, p_revision integer, p_actor text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid;b jsonb;day_index integer;d date;want text;old goya_private.roster_off_charges;
 refunds integer;debits integer;normal_debits integer;next_balance integer;changes jsonb;
begin
 for employee in select id from goya_private.branch_staff where id::text in(select key from jsonb_each(p_snapshot->'staff'))
 or id in(select staff_id from goya_private.roster_off_charges where off_date between p_week and p_week+6 and charged) order by id loop
  perform goya_private.apply_off_credits(employee);b:=goya_private.off_snapshot(employee);refunds:=0;debits:=0;normal_debits:=0;changes:='[]';
  for day_index in 0..6 loop
   d:=p_week+day_index;want:=p_snapshot->'staff'->employee::text->day_index->>'off_source';
   select * into old from goya_private.roster_off_charges where staff_id=employee and off_date=d;
   if want in ('balance','advance') and not coalesce(old.charged,false) then
    debits:=debits+1;if want='balance' then normal_debits:=normal_debits+1;end if;
    changes:=changes||jsonb_build_array(jsonb_build_object('date',d,'delta',-1,'mode',want));
   elsif coalesce(old.charged,false) and (want is null or want not in ('balance','advance')) then
    refunds:=refunds+1;changes:=changes||jsonb_build_array(jsonb_build_object('date',d,'delta',1,'mode',old.mode));
   end if;
  end loop;
  if debits+refunds>0 then
   if length(btrim(coalesce(p_actor,''))) not between 1 and 100 then raise exception 'Management name is required for Paid Off publication';end if;
   if normal_debits>0 and (b->>'balance')::integer+refunds<normal_debits then raise exception 'Insufficient Paid Off balance. Choose Advance Off explicitly or correct the balance.';end if;
   next_balance:=(b->>'balance')::integer+refunds-debits;
   perform public.goya_management_save_balance(p_token,employee,next_balance,(b->>'revision')::integer,'Published Paid Off adjustment for week '||p_week,p_actor);
   for day_index in 0..jsonb_array_length(changes)-1 loop
    d:=(changes->day_index->>'date')::date;
    insert into goya_private.roster_off_charges(staff_id,off_date,mode,charged,revision)
    values(employee,d,changes->day_index->>'mode',(changes->day_index->>'delta')::integer=-1,p_revision)
    on conflict(branch_id,staff_id,off_date) do update set mode=excluded.mode,charged=excluded.charged,revision=excluded.revision,updated_at=clock_timestamp();
    insert into goya_private.off_balance_events(staff_id,delta,balance_after,effective_on,source,source_id,notice,actor)
    values(employee,(changes->day_index->>'delta')::integer,next_balance,d,'roster',p_week::text,
     case when (changes->day_index->>'delta')::integer=-1 then 'Paid Off used for ' else 'Paid Off returned for ' end||d::text,p_actor);
   end loop;
  end if;
 end loop;
end $function$
;
alter function goya_private.reconcile_roster_off(p_token text, p_week date, p_snapshot jsonb, p_revision integer, p_actor text) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.release_roster_off(p_token text, p_staff uuid, p_from date, p_to date, p_actor text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n integer;b jsonb;r record;begin
 select count(*) into n from goya_private.roster_off_charges where staff_id=p_staff and charged and off_date between p_from and p_to;
 if n=0 then return;end if;b:=goya_private.off_snapshot(p_staff);
 perform public.goya_management_save_balance(p_token,p_staff,(b->>'balance')::integer+n,(b->>'revision')::integer,'Paid Off transferred to approved request',p_actor);
 for r in update goya_private.roster_off_charges set charged=false,updated_at=clock_timestamp() where staff_id=p_staff and charged and off_date between p_from and p_to returning off_date loop
 insert into goya_private.off_balance_events(staff_id,delta,balance_after,effective_on,source,source_id,notice,actor)
 values(p_staff,1,(b->>'balance')::integer+n,r.off_date,'request-transfer',r.off_date::text,'Roster Paid Off returned before applying approved leave',p_actor);
 end loop;
end $function$
;
alter function goya_private.release_roster_off(p_token text, p_staff uuid, p_from date, p_to date, p_actor text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_off_credit_history(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin perform public.require_session(p_token,true);
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.created_at desc) from
 (select c.*,coalesce((select jsonb_agg(jsonb_build_object('name',s.name,'applied_at',m.applied_at) order by s.name) from goya_private.off_credit_members m join public.staff s on s.id=m.staff_id where m.batch_id=c.id),'[]'::jsonb) members
 from goya_private.off_credit_batches c order by created_at desc limit 100)q),'[]'::jsonb);
end $function$
;
alter function public.goya_off_credit_history(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_off_credit(p_token text, p_id uuid, p_staff uuid[], p_days integer, p_date date, p_reason text, p_notice text, p_actor text, p_expected jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid;b jsonb;prior goya_private.off_credit_batches;ids uuid[];
begin
 perform public.require_session(p_token,true);
 select array_agg(distinct x order by x) into ids from unnest(p_staff)x;
 if p_id is null or ids is null or cardinality(ids) not between 1 and 500 or p_days is null or p_days not between 1 and 365
 or p_date is null or p_date not between (now() at time zone 'Asia/Dubai')::date-365 and (now() at time zone 'Asia/Dubai')::date+730
 or length(btrim(coalesce(p_actor,''))) not between 1 and 100 or length(btrim(coalesce(p_reason,''))) not between 1 and 500
 or length(btrim(coalesce(p_notice,''))) not between 1 and 1000 then raise exception 'Enter staff, days, effective date, reason, staff notice and management name';end if;
 -- Stable request identity prevents repeat credits after response loss or double-clicks.
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,0));
 select * into prior from goya_private.off_credit_batches where id=p_id;
 if found then
  if prior.recipients is distinct from ids or prior.days<>p_days or prior.effective_on<>p_date or prior.reason<>btrim(p_reason) or prior.notice<>btrim(p_notice) or prior.actor<>btrim(p_actor) then raise exception 'Submission reference already used for different details';end if;
  return jsonb_build_object('id',p_id,'saved',true);
 end if;
 perform 1 from public.staff where id=any(ids) order by id for update;
 foreach employee in array ids loop
  if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Selected staff changed or is inactive. Reload.';end if;
  perform goya_private.apply_off_credits(employee);b:=goya_private.off_snapshot(employee);
  if (p_expected->>employee::text)::integer is distinct from (b->>'revision')::integer then raise exception 'A balance changed. Reopen the preview before applying.';end if;
 end loop;
 insert into goya_private.off_credit_batches(id,days,effective_on,reason,notice,actor,recipients) values(p_id,p_days,p_date,btrim(p_reason),btrim(p_notice),btrim(p_actor),ids);
 insert into goya_private.off_credit_members(batch_id,staff_id) select p_id,x from unnest(ids)x;
 foreach employee in array ids loop perform goya_private.apply_off_credits(employee);end loop;
 return jsonb_build_object('id',p_id,'saved',true);
end $function$
;
alter function public.goya_off_credit(p_token text, p_id uuid, p_staff uuid[], p_days integer, p_date date, p_reason text, p_notice text, p_actor text, p_expected jsonb) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_off_reverse_credit(p_token text, p_id uuid, p_actor text, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c goya_private.off_credit_batches;m record;b jsonb;begin
 perform public.require_session(p_token,true);
 if length(btrim(coalesce(p_actor,''))) not between 1 and 100 or length(btrim(coalesce(p_reason,''))) not between 1 and 500 then raise exception 'Enter management name and correction reason';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,0));select * into c from goya_private.off_credit_batches where id=p_id;
 if not found then raise exception 'Credit not found';end if;if c.reversed_at is not null then return;end if;
 perform 1 from public.staff where id=any(c.recipients) order by id for update;
 for m in select * from goya_private.off_credit_members where batch_id=p_id and applied_at is not null order by staff_id loop
 b:=goya_private.off_snapshot(m.staff_id);
 perform public.goya_management_save_balance(p_token,m.staff_id,(b->>'balance')::integer-c.days,(b->>'revision')::integer,'Bulk credit correction: '||p_reason,p_actor);
 insert into goya_private.off_balance_events(staff_id,delta,balance_after,effective_on,source,source_id,notice,actor)
 values(m.staff_id,-c.days,(b->>'balance')::integer-c.days,(now() at time zone 'Asia/Dubai')::date,'correction',p_id::text,'Paid Off credit corrected: '||p_reason,p_actor);
 end loop;
 update goya_private.off_credit_batches set reversed_at=clock_timestamp(),reversed_by=p_actor,reversal_reason=p_reason where id=p_id;
end $function$
;
alter function public.goya_off_reverse_credit(p_token text, p_id uuid, p_actor text, p_reason text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_off_my_events(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid:=(public.require_session(p_token,false)).staff_id;begin
 if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized';end if;
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.id desc) from
 (select id,delta,balance_after,effective_on,notice,created_at,'Management'::text approved_by from goya_private.off_balance_events where staff_id=employee order by id desc limit 100)q),'[]'::jsonb);
end $function$
;
alter function public.goya_off_my_events(p_token text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_management_save_balance(p_token text, p_staff uuid, p_value integer, p_expected integer, p_reason text, p_actor text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare prior jsonb; result jsonb;
begin
 perform public.require_session(p_token,true);
 if length(btrim(coalesce(p_actor,''))) not between 1 and 100 or length(btrim(coalesce(p_reason,''))) not between 1 and 2000
  or p_value is null or p_value not between -36500 and 36500 then raise exception 'Enter management name, reason and a valid balance'; end if;
 perform 1 from public.staff where id=p_staff for update;
 if not found then raise exception 'Staff not found'; end if;
 perform goya_private.apply_off_credits(p_staff);
 prior:=goya_private.off_snapshot(p_staff);
 if (prior->>'revision')::integer is distinct from p_expected then raise exception 'Balance changed. Reload before saving.'; end if;
 insert into goya_private.staff_off_balances(staff_id,balance) values(p_staff,p_value)
 on conflict(staff_id) do update set balance=excluded.balance,revision=staff_off_balances.revision+1,updated_at=clock_timestamp()
 returning to_jsonb(staff_off_balances) into result;
 insert into goya_private.staff_hr_audit(staff_id,event,details) values(p_staff,'Off balance changed',
 jsonb_build_object('before',prior,'after',result,'reason',p_reason,'actor',p_actor,'session_ref',md5(p_token)));
 return result;
end $function$
;
alter function public.goya_management_save_balance(p_token text, p_staff uuid, p_value integer, p_expected integer, p_reason text, p_actor text) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_hr_export_source(p_token text, p_staff uuid, p_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare hr text;files jsonb;begin
 perform public.require_session(p_token,true);
 select hr_email into hr from goya_private.staff_leave_email_settings where id;
 if hr is null or btrim(hr)='' then raise exception 'Set the HR email in Settings before exporting';end if;
 if p_ids is null or cardinality(p_ids) not between 1 and 30 or cardinality(p_ids)<>(select count(distinct x) from unnest(p_ids)x) then raise exception 'Select current documents';end if;
 select jsonb_agg(jsonb_build_object('id',d.id,'category',d.category,'title',d.custom_title,'name',d.file_name,'type',d.mime_type,'size',d.byte_size,'sha',d.sha256,'driveId',d.drive_file_id)) into files
 from goya_private.staff_document_versions d where d.staff_id=p_staff and d.id=any(p_ids) and d.uploaded_at is not null and d.category<>'profile-photo'
 and not exists(select 1 from goya_private.staff_document_versions newer where newer.staff_id=d.staff_id and newer.category=d.category and newer.uploaded_at is not null and (newer.uploaded_at,newer.id)>(d.uploaded_at,d.id));
 if coalesce(jsonb_array_length(files),0)<>cardinality(p_ids) then raise exception 'Documents changed. Reopen HR export and check the selection';end if;
 return jsonb_build_object('hr',btrim(hr),'files',files);
end $function$
;
alter function public.goya_hr_export_source(p_token text, p_staff uuid, p_ids uuid[]) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.staff_notice_reminders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare employee uuid;begin
 for employee in select id from public.staff where active order by id loop perform goya_private.staff_notice_refresh(employee);end loop;
end $function$
;
alter function goya_private.staff_notice_reminders() owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.staff_notice_request(r goya_private.staff_leave_requests)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 if r.state not in ('Approved','Declined') then return;end if;
 perform goya_private.staff_notice_emit(r.staff_id,'request:'||r.id||':'||extract(epoch from r.updated_at)::text,'request',r.kind||case when r.state='Declined' then ' — Rejected' else ' — Approved' end,
 coalesce(r.approved_from,r.requested_from)::text||' to '||coalesce(r.approved_to,r.requested_to)::text||case when coalesce(r.review_note,'')<>'' then E'\n'||r.review_note else '' end||E'\nManagement',
 jsonb_build_object('view','request','id',r.id),r.updated_at);
end $function$
;
alter function goya_private.staff_notice_request(r goya_private.staff_leave_requests) owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.staff_notice_events()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare previous jsonb;member record;i integer;before_day jsonb;after_day jsonb;before_value jsonb;after_value jsonb;label text;details text;request_row goya_private.staff_leave_requests;off_row goya_private.off_balance_events;
begin
 if tg_table_name='staff_leave_requests' then
  request_row:=new;
  if tg_op='INSERT' then perform goya_private.staff_notice_request(request_row);
  elsif (new.state,new.approved_from,new.approved_to,new.review_note) is distinct from (old.state,old.approved_from,old.approved_to,old.review_note) then perform goya_private.staff_notice_request(request_row);end if;
 elsif tg_table_name='off_balance_events' then off_row:=new;perform goya_private.staff_notice_off(off_row);
 elsif tg_table_name='staff_document_versions' then
  if new.uploaded_at is null then return new;end if;
  if tg_op='UPDATE' then if old.uploaded_at is not null then return new;end if;end if;
  label:=coalesce(nullif(new.custom_title,''),initcap(replace(new.category,'-',' ')));
  perform goya_private.staff_notice_emit(new.staff_id,'upload:'||new.id,'document','Document available: '||label,'A current version of your '||label||' is available in My Journey.',jsonb_build_object('view','document','id',new.id,'category',new.category),new.uploaded_at);
 elsif tg_table_name='roster_publications' then
  select schedule into previous from goya_private.roster_publications where week_start=new.week_start and revision<new.revision order by revision desc limit 1;
  for member in select s.id from public.staff s where s.active and (new.schedule->'staff' ? s.id::text or previous->'staff' ? s.id::text) loop
   for i in 0..6 loop
    if not goya_private.employed_on(member.id,new.week_start+i) then continue;end if;
    before_day:=previous->'staff'->member.id::text->i;after_day:=new.schedule->'staff'->member.id::text->i;
    if coalesce(before_day,'null') is not distinct from coalesce(after_day,'null') then continue;end if;
    perform goya_private.staff_notice_emit(member.id,'roster:'||new.week_start||':'||new.revision||':'||i,'roster',case when previous is null then 'Your schedule published' else 'Your schedule changed' end||' · '||(new.week_start+i)::text,
     'Before: '||goya_private.staff_notice_day(before_day)||E'\nNow: '||goya_private.staff_notice_day(after_day)||case when coalesce(after_day->>'note','')<>'' then E'\n'||(after_day->>'note') else '' end||E'\nManagement',
     jsonb_build_object('view','roster','week',new.week_start,'date',new.week_start+i),new.published_at);
   end loop;
  end loop;
 elsif tg_table_name='attendance_live_audit' and new.actor_type='admin' then
  before_value:=coalesce(new.before_data->'session',new.before_data,'{}');after_value:=coalesce(new.after_data->'session',new.after_data,'{}');
  details:='Date: '||new.operational_date::text;
  foreach label in array array['check_in_at','check_out_at','classification','break_taken','is_deleted'] loop
   if before_value->label is distinct from after_value->label then
    details:=details||E'\n'||initcap(replace(label,'_',' '))||': '||coalesce(before_value->>label,'—')||' → '||coalesce(after_value->>label,'—');
   end if;
  end loop;
  perform goya_private.staff_notice_emit(new.staff_id,'attendance:'||new.id,'attendance','Attendance updated by Management',details||E'\nManagement',jsonb_build_object('view','attendance','date',new.operational_date),new.created_at);
 end if;
 return new;
exception when others then
 -- Notification failure must never cancel attendance, uploads, requests or publishing.
 raise warning 'Staff notification unavailable (SQLSTATE %)',sqlstate;return new;
end $function$
;
alter function goya_private.staff_notice_events() owner to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.staff_notice_refresh(employee uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record;request_row goya_private.staff_leave_requests;off_row goya_private.off_balance_events;today date:=(now() at time zone 'Asia/Dubai')::date;bucket text;rules jsonb;work_seconds numeric;target_minutes integer;
begin
 for request_row in select * from (select * from goya_private.staff_leave_requests where staff_id=employee and state in ('Approved','Declined') order by updated_at desc limit 200)r order by updated_at loop
  if not exists(select 1 from goya_private.staff_notifications n where n.staff_id=employee and n.kind='request' and n.target->>'id'=request_row.id::text) then perform goya_private.staff_notice_request(request_row);end if;
 end loop;
 for off_row in select * from (select * from goya_private.off_balance_events where staff_id=employee order by id desc limit 200)r order by id loop perform goya_private.staff_notice_off(off_row);end loop;
 for r in select * from (select d.*,row_number() over(partition by category order by uploaded_at desc,id desc) rn from goya_private.staff_document_versions d where staff_id=employee and uploaded_at is not null)d where rn=1 and expires_on<=today+30 loop
  bucket:=case when r.expires_on<today then 'expired' when r.expires_on<=today+7 then '7' when r.expires_on<=today+15 then '15' else '30' end;
  perform goya_private.staff_notice_emit(employee,'document:'||r.id||':'||r.expires_on||':'||bucket,'document','Document expiry reminder',
   coalesce(r.custom_title,initcap(replace(r.category,'-',' ')))||' · '||case when r.expires_on<today then 'Expired on ' when r.expires_on=today then 'Expires today: ' else 'Expires on ' end||r.expires_on::text,
   jsonb_build_object('view','document','id',r.id,'category',r.category));
 end loop;
 rules:=public.attendance_live_rules();
 for r in select d.* from public.attendance_live_days d where d.staff_id=employee and not d.is_deleted and d.operational_date between today-1 and today
 and exists(select 1 from public.attendance_live_sessions s where s.staff_id=employee and s.operational_date=d.operational_date and not s.is_deleted and s.check_out_at is null) loop
  select coalesce(sum(extract(epoch from coalesce(s.check_out_at,now())-s.check_in_at)),0) into work_seconds from public.attendance_live_sessions s where s.staff_id=employee and s.operational_date=r.operational_date and not s.is_deleted;
  target_minutes:=coalesce((r.ot_policy->>'regular_minutes')::int,(rules->>'regular_net_minutes')::int,480)+case when coalesce((rules->>'force_no_break')::boolean,false) or r.break_taken=false then 0 else coalesce((r.ot_policy->>'break_minutes')::int,(rules->>'break_minutes')::int,60) end;
  if work_seconds>=target_minutes*60 then perform goya_private.staff_notice_emit(employee,'checkout:'||r.operational_date,'reminder','Check-out reminder','Your duty target has been reached and you are still checked in. Please check out when your work is finished.',jsonb_build_object('view','attendance','date',r.operational_date));end if;
 end loop;
end $function$
;
alter function goya_private.staff_notice_refresh(employee uuid) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_staff_inbox(p_token text, p_before bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid:=(public.require_session(p_token,false)).staff_id;settings jsonb;begin
 if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized';end if;
 perform goya_private.staff_notice_refresh(employee);
 select jsonb_build_object('value',preferences,'revision',revision) into settings from goya_private.staff_appearance where staff_id=employee;
 return jsonb_build_object('staff_id',employee,'preferences',coalesce(settings,'{"value":{"mode":"auto","accent":"default","text_size":"normal"},"revision":0}'),
 'unread',(select count(*) from goya_private.staff_notifications where staff_id=employee and read_at is null),
 'max_id',(select max(id) from goya_private.staff_notifications where staff_id=employee),
 'items',coalesce((select jsonb_agg(to_jsonb(q) order by q.id desc) from (select id,event_key,kind,title,body,target,created_at,read_at from goya_private.staff_notifications where staff_id=employee and (p_before is null or id<p_before) order by id desc limit 100)q),'[]'::jsonb));
end $function$
;
alter function public.goya_staff_inbox(p_token text, p_before bigint) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_staff_notice_read(p_token text, p_ids bigint[], p_read boolean, p_through bigint DEFAULT NULL::bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid:=(public.require_session(p_token,false)).staff_id;begin
 if not exists(select 1 from public.staff where id=employee and active) or p_read is null or coalesce(cardinality(p_ids),0)>200 or (p_through is not null and not p_read) then raise exception 'Invalid notification update';end if;
 update goya_private.staff_notifications set read_at=case when p_read then coalesce(read_at,clock_timestamp()) else null end
 where staff_id=employee and (id=any(p_ids) or (p_through is not null and id<=p_through));
end $function$
;
alter function public.goya_staff_notice_read(p_token text, p_ids bigint[], p_read boolean, p_through bigint) owner to goya_operations;
CREATE OR REPLACE FUNCTION public.goya_staff_appearance_save(p_token text, p_preferences jsonb, p_expected integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid:=(public.require_session(p_token,false)).staff_id;result jsonb;scene text;saved jsonb;sound_notification jsonb;sound_attendance jsonb;volume text;begin
 if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized';end if;
 if jsonb_typeof(p_preferences) is distinct from 'object' or p_preferences->>'mode' is null or p_preferences->>'mode' not in ('auto','light','dark') or p_preferences->>'accent' is null or p_preferences->>'accent' not in ('default','green','blue','purple','brown','teal') or p_preferences->>'text_size' is null or p_preferences->>'text_size' not in ('normal','large') or p_expected is null then raise exception 'Choose a supported theme preset';end if;
 scene:=coalesce(p_preferences->>'background',(select preferences->>'background' from goya_private.staff_appearance where staff_id=employee),'default');
 if scene not in ('default','ocean','forest','lavender','sand') then raise exception 'Choose a supported background preset';end if;
 select preferences into saved from goya_private.staff_appearance where staff_id=employee;
 sound_notification:=coalesce(p_preferences->'notification_sound',saved->'notification_sound','true'::jsonb);
 sound_attendance:=coalesce(p_preferences->'attendance_sound',saved->'attendance_sound','true'::jsonb);
 volume:=coalesce(p_preferences->>'sound_volume',saved->>'sound_volume','35');
 if jsonb_typeof(sound_notification)<>'boolean' or jsonb_typeof(sound_attendance)<>'boolean' or volume !~ '^(100|[0-9]{1,2})$' then raise exception 'Choose valid sound switches and volume (0–100)';end if;
 p_preferences:=jsonb_build_object('mode',p_preferences->>'mode','accent',p_preferences->>'accent','text_size',p_preferences->>'text_size','background',scene,'notification_sound',sound_notification,'attendance_sound',sound_attendance,'sound_volume',volume::integer);
 if p_expected=0 then insert into goya_private.staff_appearance(staff_id,preferences) values(employee,p_preferences) on conflict do nothing returning jsonb_build_object('value',preferences,'revision',revision) into result;
 else update goya_private.staff_appearance set preferences=p_preferences,revision=revision+1,updated_at=clock_timestamp() where staff_id=employee and revision=p_expected returning jsonb_build_object('value',preferences,'revision',revision) into result;end if;
 if result is null then raise exception 'Appearance changed on another device. Reopen Appearance and try again.';end if;return result;
end $function$
;
alter function public.goya_staff_appearance_save(p_token text, p_preferences jsonb, p_expected integer) owner to goya_operations;
grant execute on all functions in schema public,goya_private to goya_operations;
alter table goya_private.equipment_reports add constraint branch_parent_goya_private_equipment_reports_id unique(branch_id,id);
alter table goya_private.equipment_status_history add constraint branch_equipment_status_history_report_id_fkey foreign key(branch_id,report_id) references goya_private.equipment_reports(branch_id,id);
alter table goya_private.inventory_shared_sheets add constraint branch_parent_goya_private_inventory_shared_sheets_id unique(branch_id,id);
alter table goya_private.inventory_shared_audit add constraint branch_inventory_shared_audit_sheet_id_fkey foreign key(branch_id,sheet_id) references goya_private.inventory_shared_sheets(branch_id,id);
alter table goya_private.inventory_shared_finals add constraint branch_inventory_shared_finals_sheet_id_fkey foreign key(branch_id,sheet_id) references goya_private.inventory_shared_sheets(branch_id,id);
alter table goya_private.inventory_shared_lines add constraint branch_inventory_shared_lines_sheet_id_fkey foreign key(branch_id,sheet_id) references goya_private.inventory_shared_sheets(branch_id,id);
alter table public.inventory_sessions add constraint branch_parent_public_inventory_sessions_id unique(branch_id,id);
alter table goya_private.inventory_shared_sheets add constraint branch_inventory_shared_sheets_session_id_fkey foreign key(branch_id,session_id) references public.inventory_sessions(branch_id,id);
alter table public.attendance_live_sessions add constraint branch_parent_public_attendance_live_sessions_id unique(branch_id,id);
alter table public.attendance_live_audit add constraint branch_attendance_live_audit_session_id_fkey foreign key(branch_id,session_id) references public.attendance_live_sessions(branch_id,id);
alter table public.inventory_counts add constraint branch_inventory_counts_shared_sheet_id_fkey foreign key(branch_id,shared_sheet_id) references goya_private.inventory_shared_sheets(branch_id,id);
alter table public.inventory_counts add constraint branch_inventory_counts_session_id_fkey foreign key(branch_id,session_id) references public.inventory_sessions(branch_id,id);
alter table public.inventory_drafts add constraint branch_inventory_drafts_session_id_fkey foreign key(branch_id,session_id) references public.inventory_sessions(branch_id,id);
alter table public.inventory_submissions add constraint branch_inventory_submissions_session_id_fkey foreign key(branch_id,session_id) references public.inventory_sessions(branch_id,id);
alter table public.order_groups add constraint branch_parent_public_order_groups_id unique(branch_id,id);
alter table public.orders add constraint branch_orders_order_group_id_fkey foreign key(branch_id,order_group_id) references public.order_groups(branch_id,id);
create function goya_private.branch_management_key(p_key text) returns boolean language sql stable security definer set search_path='' as $$select length(coalesce(p_key,''))>=32 and exists(select 1 from public.attendance_settings where branch_id='00000000-0000-0000-0000-000000000001' and key='management_share' and coalesce((value->>'enabled')::boolean,true) and value->>'key'=p_key)$$;
revoke all on function goya_private.branch_management_key(text) from public;
grant execute on function goya_private.branch_management_key(text) to goya_operations;
create or replace function public.attendance_live_management_validate(p_key text) returns boolean language sql stable security definer set search_path='' as $$select goya_private.branch_management_key(p_key)$$;
create function public.goya_branch_list(p_token text default null,p_key text default null) returns jsonb language plpgsql security definer set search_path='' as $$declare sess public.app_sessions;is_manager boolean:=false;begin
 select * into sess from public.app_sessions where token=p_token and expires_at>now();
 is_manager:=coalesce(sess.is_admin,false) or goya_private.branch_management_key(p_key);
 if sess.token is null and not is_manager then return jsonb_build_object('manager',false,'branches',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'kind',kind,'archived_at',archived_at) order by created_at,id),'[]') from goya_private.branches));end if;
 return jsonb_build_object('manager',coalesce(sess.is_admin,false),'staff_id',sess.staff_id,'branches',coalesce((select jsonb_agg(to_jsonb(b)||case when sess.is_admin then jsonb_build_object('members',(select coalesce(jsonb_agg(staff_id),'[]') from goya_private.branch_members where branch_id=b.id)) else '{}'::jsonb end order by b.created_at,b.id) from goya_private.branches b where is_manager or exists(select 1 from goya_private.branch_members bm where bm.branch_id=b.id and bm.staff_id=sess.staff_id)),'[]'::jsonb));end$$;
create function public.goya_branch_save(p_token text,p_row jsonb,p_expected integer default 0) returns uuid language plpgsql security definer set search_path='' as $$declare sess public.app_sessions;b uuid;previous jsonb;oldrev integer;member uuid;begin
 select * into sess from public.app_sessions where token=p_token and expires_at>now() and is_admin;
 if sess.token is null then raise exception 'Management access required';end if;
 if jsonb_typeof(p_row) is distinct from 'object' or length(btrim(coalesce(p_row->>'name',''))) not between 1 and 100 or coalesce(p_row->>'kind','') not in('branch','event') or length(coalesce(p_row->>'address',''))>1000 or jsonb_typeof(p_row->'members') is distinct from 'array' then raise exception 'Enter a branch name, type and valid staff list';end if;
 b:=coalesce(nullif(p_row->>'id','')::uuid,gen_random_uuid());
 perform pg_advisory_xact_lock(hashtext(b::text));
 select to_jsonb(x),revision into previous,oldrev from goya_private.branches x where id=b for update;
 if coalesce(oldrev,0)<>p_expected then raise exception 'Branch changed on another device. Reload before saving';end if;
 if b='00000000-0000-0000-0000-000000000001' and (p_row->>'archived')::boolean then raise exception 'The original GOYA branch must remain available';end if;
 for member in select value::uuid from jsonb_array_elements_text(p_row->'members') loop if not exists(select 1 from public.staff where id=member) then raise exception 'Unknown staff member';end if;end loop;
 insert into goya_private.branches(id,name,kind,address,starts_on,ends_on,archived_at) values(b,btrim(p_row->>'name'),p_row->>'kind',btrim(coalesce(p_row->>'address','')),nullif(p_row->>'starts_on','')::date,nullif(p_row->>'ends_on','')::date,case when coalesce((p_row->>'archived')::boolean,false) then now() end)
 on conflict(id) do update set name=excluded.name,kind=excluded.kind,address=excluded.address,starts_on=excluded.starts_on,ends_on=excluded.ends_on,archived_at=case when excluded.archived_at is not null then coalesce(branches.archived_at,excluded.archived_at) end,revision=branches.revision+1;
 -- Membership changes do not remove any operational records or employee history.
 delete from goya_private.branch_members where branch_id=b and not(staff_id in(select value::uuid from jsonb_array_elements_text(p_row->'members')));
 insert into goya_private.branch_members(branch_id,staff_id) select b,value::uuid from jsonb_array_elements_text(p_row->'members') on conflict do nothing;
 if previous is null then
 insert into public.attendance_settings(key,value,branch_id) select key,value,b from public.attendance_settings where branch_id='00000000-0000-0000-0000-000000000001' and key<>'management_share';
 -- New locations start with no inherited GPS/IP allowlist; management must configure their own workplace.
 update public.attendance_settings set value=value||jsonb_build_object('locations','[]'::jsonb,'approved_public_ips','[]'::jsonb) where branch_id=b and key='live_rules';
 insert into public.settings(key,value,branch_id) select key,value,b from public.settings where branch_id='00000000-0000-0000-0000-000000000001';end if;
 insert into goya_private.branch_audit(branch_id,before_data,after_data) select b,previous,to_jsonb(x)||jsonb_build_object('members',p_row->'members') from goya_private.branches x where id=b;
 return b;end$$;
create table goya_private.branch_rpc_registry(name text not null,identity_args text not null,args jsonb not null,returns_set boolean not null,primary key(name,identity_args));
alter table goya_private.branch_rpc_registry enable row level security;
insert into goya_private.branch_rpc_registry values('goya_staff_push_state','p_token text, p_endpoint text','[{"name":"p_token","type":"text"},{"name":"p_endpoint","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_replace_internal_items','p_token text, p_rows jsonb','[{"name":"p_token","type":"text"},{"name":"p_rows","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_history','p_token text, p_month date','[{"name":"p_token","type":"text"},{"name":"p_month","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_draft_get','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_draft_save','p_token text, p_kind text, p_items jsonb','[{"name":"p_token","type":"text"},{"name":"p_kind","type":"text"},{"name":"p_items","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_draft_clear','p_token text, p_kind text','[{"name":"p_token","type":"text"},{"name":"p_kind","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_upsert_master_items','p_token text, p_rows jsonb','[{"name":"p_token","type":"text"},{"name":"p_rows","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_upsert_internal_items','p_token text, p_rows jsonb','[{"name":"p_token","type":"text"},{"name":"p_rows","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_replace_master_items','p_token text, p_rows jsonb','[{"name":"p_token","type":"text"},{"name":"p_rows","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_admin_profiles','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_save_profile','p_token text, p_staff uuid, p_profile jsonb','[{"name":"p_token","type":"text"},{"name":"p_staff","type":"uuid"},{"name":"p_profile","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_rejoin','p_token text, p_staff uuid, p_date date','[{"name":"p_token","type":"text"},{"name":"p_staff","type":"uuid"},{"name":"p_date","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_staff_push','p_token text, p_subscription jsonb, p_enabled boolean','[{"name":"p_token","type":"text"},{"name":"p_subscription","type":"jsonb"},{"name":"p_enabled","type":"boolean"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_staff_identity','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_archive_import','p_token text, p_rows jsonb','[{"name":"p_token","type":"text"},{"name":"p_rows","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_archive_read','p_token text, p_admin boolean, p_month date','[{"name":"p_token","type":"text"},{"name":"p_admin","type":"boolean"},{"name":"p_month","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_admin_email_settings','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_save_email_settings','p_token text, p_owner text, p_hr text, p_expected integer','[{"name":"p_token","type":"text"},{"name":"p_owner","type":"text"},{"name":"p_hr","type":"text"},{"name":"p_expected","type":"integer"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_orders_page','p_token text, p_admin boolean, p_filters jsonb, p_page integer','[{"name":"p_token","type":"text"},{"name":"p_admin","type":"boolean"},{"name":"p_filters","type":"jsonb"},{"name":"p_page","type":"integer"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_staff_history_page','p_token text, p_kind text, p_month date, p_filters jsonb, p_page integer','[{"name":"p_token","type":"text"},{"name":"p_kind","type":"text"},{"name":"p_month","type":"date"},{"name":"p_filters","type":"jsonb"},{"name":"p_page","type":"integer"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_admin_order_summary','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_bootstrap','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_sync_portal_staff','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_save_staff','p_token text, p_id uuid, p_name text, p_employee_code text, p_employment_type text, p_designation text, p_phone text, p_default_start_time time without time zone, p_expected_presence_minutes integer, p_default_break_minutes integer, p_active boolean, p_notes text','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_name","type":"text"},{"name":"p_employee_code","type":"text"},{"name":"p_employment_type","type":"text"},{"name":"p_designation","type":"text"},{"name":"p_phone","type":"text"},{"name":"p_default_start_time","type":"time without time zone"},{"name":"p_expected_presence_minutes","type":"integer"},{"name":"p_default_break_minutes","type":"integer"},{"name":"p_active","type":"boolean"},{"name":"p_notes","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_save_settings','p_token text, p_value jsonb','[{"name":"p_token","type":"text"},{"name":"p_value","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_get_document','p_token text, p_id uuid','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_admin_delete_notice','p_token text, p_id uuid','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_admin_notices','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_import_records','p_token text, p_rows jsonb, p_file_name text, p_upload_type text, p_date_from date, p_date_to date','[{"name":"p_token","type":"text"},{"name":"p_rows","type":"jsonb"},{"name":"p_file_name","type":"text"},{"name":"p_upload_type","type":"text"},{"name":"p_date_from","type":"date"},{"name":"p_date_to","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_records_range','p_token text, p_start date, p_end date','[{"name":"p_token","type":"text"},{"name":"p_start","type":"date"},{"name":"p_end","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_delete_record','p_token text, p_id uuid','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_upload_document','p_token text, p_staff_id uuid, p_title text, p_file_name text, p_mime_type text, p_file_size integer, p_base64 text, p_note text','[{"name":"p_token","type":"text"},{"name":"p_staff_id","type":"uuid"},{"name":"p_title","type":"text"},{"name":"p_file_name","type":"text"},{"name":"p_mime_type","type":"text"},{"name":"p_file_size","type":"integer"},{"name":"p_base64","type":"text"},{"name":"p_note","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_list_documents','p_token text, p_staff_id uuid','[{"name":"p_token","type":"text"},{"name":"p_staff_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_delete_document','p_token text, p_id uuid','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_roster_admin_week','p_token text, p_week date','[{"name":"p_token","type":"text"},{"name":"p_week","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_archive_upload','p_token text, p_file_name text, p_mime_type text, p_file_size integer, p_base64 text, p_upload_type text, p_date_from date, p_date_to date, p_rows_imported integer','[{"name":"p_token","type":"text"},{"name":"p_file_name","type":"text"},{"name":"p_mime_type","type":"text"},{"name":"p_file_size","type":"integer"},{"name":"p_base64","type":"text"},{"name":"p_upload_type","type":"text"},{"name":"p_date_from","type":"date"},{"name":"p_date_to","type":"date"},{"name":"p_rows_imported","type":"integer"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_upload_history','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_get_upload','p_token text, p_id uuid','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_attendance_submit','p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text','[{"name":"p_token","type":"text"},{"name":"p_operational_date","type":"date"},{"name":"p_punch_in","type":"timestamp without time zone"},{"name":"p_punch_out","type":"timestamp without time zone"},{"name":"p_break_taken","type":"boolean"},{"name":"p_day_off","type":"boolean"},{"name":"p_note","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_attendance_month','p_token text, p_month date','[{"name":"p_token","type":"text"},{"name":"p_month","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_admin_submissions','p_token text, p_status text','[{"name":"p_token","type":"text"},{"name":"p_status","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_review_submission','p_token text, p_id uuid, p_status text, p_admin_note text','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_status","type":"text"},{"name":"p_admin_note","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_finalize_month','p_token text, p_month date, p_summary jsonb, p_details jsonb','[{"name":"p_token","type":"text"},{"name":"p_month","type":"date"},{"name":"p_summary","type":"jsonb"},{"name":"p_details","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_get_finalized_month','p_token text, p_month date','[{"name":"p_token","type":"text"},{"name":"p_month","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_roster_save','p_token text, p_week date, p_expected integer, p_schedule jsonb, p_publish boolean','[{"name":"p_token","type":"text"},{"name":"p_week","type":"date"},{"name":"p_expected","type":"integer"},{"name":"p_schedule","type":"jsonb"},{"name":"p_publish","type":"boolean"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_save_manual','p_token text, p_staff_id uuid, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_note text','[{"name":"p_token","type":"text"},{"name":"p_staff_id","type":"uuid"},{"name":"p_operational_date","type":"date"},{"name":"p_punch_in","type":"timestamp without time zone"},{"name":"p_punch_out","type":"timestamp without time zone"},{"name":"p_break_taken","type":"boolean"},{"name":"p_note","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_attendance_submit_v2','p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone','[{"name":"p_token","type":"text"},{"name":"p_operational_date","type":"date"},{"name":"p_punch_in","type":"timestamp without time zone"},{"name":"p_punch_out","type":"timestamp without time zone"},{"name":"p_break_taken","type":"boolean"},{"name":"p_day_off","type":"boolean"},{"name":"p_note","type":"text"},{"name":"p_split_shift","type":"boolean"},{"name":"p_shift2_in","type":"timestamp without time zone"},{"name":"p_shift2_out","type":"timestamp without time zone"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_admin_submissions_v2','p_token text, p_status text','[{"name":"p_token","type":"text"},{"name":"p_status","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_review_submission_v2','p_token text, p_id uuid, p_status text, p_admin_note text, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone, p_note text','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_status","type":"text"},{"name":"p_admin_note","type":"text"},{"name":"p_punch_in","type":"timestamp without time zone"},{"name":"p_punch_out","type":"timestamp without time zone"},{"name":"p_break_taken","type":"boolean"},{"name":"p_day_off","type":"boolean"},{"name":"p_split_shift","type":"boolean"},{"name":"p_shift2_in","type":"timestamp without time zone"},{"name":"p_shift2_out","type":"timestamp without time zone"},{"name":"p_note","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_import_records_v2','p_token text, p_rows jsonb, p_file_name text, p_upload_type text, p_date_from date, p_date_to date','[{"name":"p_token","type":"text"},{"name":"p_rows","type":"jsonb"},{"name":"p_file_name","type":"text"},{"name":"p_upload_type","type":"text"},{"name":"p_date_from","type":"date"},{"name":"p_date_to","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_attendance_submit_v10','p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone','[{"name":"p_token","type":"text"},{"name":"p_operational_date","type":"date"},{"name":"p_punch_in","type":"timestamp without time zone"},{"name":"p_punch_out","type":"timestamp without time zone"},{"name":"p_break_taken","type":"boolean"},{"name":"p_day_off","type":"boolean"},{"name":"p_note","type":"text"},{"name":"p_split_shift","type":"boolean"},{"name":"p_shift2_in","type":"timestamp without time zone"},{"name":"p_shift2_out","type":"timestamp without time zone"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_attendance_month_v10','p_token text, p_month date','[{"name":"p_token","type":"text"},{"name":"p_month","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_import_records_v10','p_token text, p_rows jsonb, p_file_name text, p_upload_type text, p_date_from date, p_date_to date','[{"name":"p_token","type":"text"},{"name":"p_rows","type":"jsonb"},{"name":"p_file_name","type":"text"},{"name":"p_upload_type","type":"text"},{"name":"p_date_from","type":"date"},{"name":"p_date_to","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_save_finalized_report_v10','p_token text, p_file_name text, p_period_label text, p_date_from date, p_date_to date, p_rows jsonb, p_summary jsonb','[{"name":"p_token","type":"text"},{"name":"p_file_name","type":"text"},{"name":"p_period_label","type":"text"},{"name":"p_date_from","type":"date"},{"name":"p_date_to","type":"date"},{"name":"p_rows","type":"jsonb"},{"name":"p_summary","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_staff_device_compare_v10','p_token text, p_status text','[{"name":"p_token","type":"text"},{"name":"p_status","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_save_final_submission_v10','p_token text, p_id uuid, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone, p_note text','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_punch_in","type":"timestamp without time zone"},{"name":"p_punch_out","type":"timestamp without time zone"},{"name":"p_break_taken","type":"boolean"},{"name":"p_day_off","type":"boolean"},{"name":"p_split_shift","type":"boolean"},{"name":"p_shift2_in","type":"timestamp without time zone"},{"name":"p_shift2_out","type":"timestamp without time zone"},{"name":"p_note","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_finalized_report_history_v10','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_get_finalized_report_v10','p_token text, p_id uuid','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_inventory_shared_work','p_token text, p_session_id uuid, p_section text','[{"name":"p_token","type":"text"},{"name":"p_session_id","type":"uuid"},{"name":"p_section","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_attendance_month_v11','p_token text, p_month date','[{"name":"p_token","type":"text"},{"name":"p_month","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_import_records_v11','p_token text, p_rows jsonb, p_file_name text, p_upload_type text, p_date_from date, p_date_to date','[{"name":"p_token","type":"text"},{"name":"p_rows","type":"jsonb"},{"name":"p_file_name","type":"text"},{"name":"p_upload_type","type":"text"},{"name":"p_date_from","type":"date"},{"name":"p_date_to","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_delete_reason','p_token text, p_id uuid','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_update_finalized_report_v11','p_token text, p_id uuid, p_rows jsonb, p_summary jsonb','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_rows","type":"jsonb"},{"name":"p_summary","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_inventory_shared_save','p_token text, p_session_id uuid, p_section text, p_generation bigint, p_changes jsonb','[{"name":"p_token","type":"text"},{"name":"p_session_id","type":"uuid"},{"name":"p_section","type":"text"},{"name":"p_generation","type":"bigint"},{"name":"p_changes","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_inventory_shared_submit','p_token text, p_session_id uuid, p_section text, p_generation bigint, p_version bigint','[{"name":"p_token","type":"text"},{"name":"p_session_id","type":"uuid"},{"name":"p_section","type":"text"},{"name":"p_generation","type":"bigint"},{"name":"p_version","type":"bigint"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_admin_inventory_reopen','p_token text, p_session_id uuid, p_section text','[{"name":"p_token","type":"text"},{"name":"p_session_id","type":"uuid"},{"name":"p_section","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_inventory_shared_history','p_token text, p_session_id uuid, p_section text','[{"name":"p_token","type":"text"},{"name":"p_session_id","type":"uuid"},{"name":"p_section","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('inventory_work','p_token text, p_session_id uuid, p_section text','[{"name":"p_token","type":"text"},{"name":"p_session_id","type":"uuid"},{"name":"p_section","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_attendance_submit_v12','p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone','[{"name":"p_token","type":"text"},{"name":"p_operational_date","type":"date"},{"name":"p_punch_in","type":"timestamp without time zone"},{"name":"p_punch_out","type":"timestamp without time zone"},{"name":"p_break_taken","type":"boolean"},{"name":"p_day_off","type":"boolean"},{"name":"p_note","type":"text"},{"name":"p_split_shift","type":"boolean"},{"name":"p_shift2_in","type":"timestamp without time zone"},{"name":"p_shift2_out","type":"timestamp without time zone"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('inventory_save_draft','p_token text, p_session_id uuid, p_section text, p_items jsonb','[{"name":"p_token","type":"text"},{"name":"p_session_id","type":"uuid"},{"name":"p_section","type":"text"},{"name":"p_items","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('inventory_submit_final','p_token text, p_session_id uuid, p_section text, p_items jsonb','[{"name":"p_token","type":"text"},{"name":"p_session_id","type":"uuid"},{"name":"p_section","type":"text"},{"name":"p_items","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('save_inventory_count','p_token text, p_session_id uuid, p_items jsonb','[{"name":"p_token","type":"text"},{"name":"p_session_id","type":"uuid"},{"name":"p_items","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_document_reserve_v2','p_token text, p_id uuid, p_category text, p_name text, p_type text, p_size integer, p_sha text, p_staff uuid, p_title text','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_category","type":"text"},{"name":"p_name","type":"text"},{"name":"p_type","type":"text"},{"name":"p_size","type":"integer"},{"name":"p_sha","type":"text"},{"name":"p_staff","type":"uuid"},{"name":"p_title","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_bootstrap','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_document_complete_v2','p_token text, p_id uuid, p_drive text, p_staff uuid','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_drive","type":"text"},{"name":"p_staff","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_live_attendance_set_break','p_token text, p_break_taken boolean','[{"name":"p_token","type":"text"},{"name":"p_break_taken","type":"boolean"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_public_dashboard','p_date date','[{"name":"p_date","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_admin_settings','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_week_leave','p_token text, p_week date','[{"name":"p_token","type":"text"},{"name":"p_week","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_admin_update_session','p_token text, p_session_id uuid, p_check_in timestamp with time zone, p_check_out timestamp with time zone','[{"name":"p_token","type":"text"},{"name":"p_session_id","type":"uuid"},{"name":"p_check_in","type":"timestamp with time zone"},{"name":"p_check_out","type":"timestamp with time zone"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_admin_audit','p_token text, p_staff_id uuid, p_start date, p_end date','[{"name":"p_token","type":"text"},{"name":"p_staff_id","type":"uuid"},{"name":"p_start","type":"date"},{"name":"p_end","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_admin_save_settings','p_token text, p_value jsonb','[{"name":"p_token","type":"text"},{"name":"p_value","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_complaints','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_admin_manual_action','p_token text, p_staff_id uuid, p_action text, p_at timestamp with time zone, p_break_taken boolean, p_note text','[{"name":"p_token","type":"text"},{"name":"p_staff_id","type":"uuid"},{"name":"p_action","type":"text"},{"name":"p_at","type":"timestamp with time zone"},{"name":"p_break_taken","type":"boolean"},{"name":"p_note","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_delete_item','p_token text, p_table text, p_id uuid','[{"name":"p_token","type":"text"},{"name":"p_table","type":"text"},{"name":"p_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_admin_delete_day','p_token text, p_staff_id uuid, p_date date, p_reason text','[{"name":"p_token","type":"text"},{"name":"p_staff_id","type":"uuid"},{"name":"p_date","type":"date"},{"name":"p_reason","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_update_orders','p_token text, p_ids bigint[], p_status text, p_notes text','[{"name":"p_token","type":"text"},{"name":"p_ids","type":"bigint[]"},{"name":"p_status","type":"text"},{"name":"p_notes","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_delete_orders','p_token text, p_ids bigint[]','[{"name":"p_token","type":"text"},{"name":"p_ids","type":"bigint[]"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_admin_dashboard','p_token text, p_date date','[{"name":"p_token","type":"text"},{"name":"p_date","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_save_settings','p_token text, p_settings jsonb','[{"name":"p_token","type":"text"},{"name":"p_settings","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_delete_info_page','p_token text, p_id uuid','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_delete_staff','p_token text, p_id uuid','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_admin_notification_count','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_admin_notifications_read','p_token text, p_through bigint','[{"name":"p_token","type":"text"},{"name":"p_through","type":"bigint"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_admin_update_day','p_token text, p_staff_id uuid, p_date date, p_break_taken boolean, p_classification text, p_note text','[{"name":"p_token","type":"text"},{"name":"p_staff_id","type":"uuid"},{"name":"p_date","type":"date"},{"name":"p_break_taken","type":"boolean"},{"name":"p_classification","type":"text"},{"name":"p_note","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_admin_delete_session','p_token text, p_session_id uuid, p_reason text','[{"name":"p_token","type":"text"},{"name":"p_session_id","type":"uuid"},{"name":"p_reason","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_equipment_submit','p_token text, p_request_id uuid, p_value jsonb','[{"name":"p_token","type":"text"},{"name":"p_request_id","type":"uuid"},{"name":"p_value","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_admin_history','p_token text, p_start date, p_end date, p_staff_id uuid','[{"name":"p_token","type":"text"},{"name":"p_start","type":"date"},{"name":"p_end","type":"date"},{"name":"p_staff_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_management_notice_draft','p_token text, p_id uuid, p_title text, p_body text','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_title","type":"text"},{"name":"p_body","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_live_attendance_set_split','p_token text, p_split_shift boolean','[{"name":"p_token","type":"text"},{"name":"p_split_shift","type":"boolean"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_management_notice_status','p_token text, p_id uuid, p_active boolean, p_expected timestamp with time zone','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_active","type":"boolean"},{"name":"p_expected","type":"timestamp with time zone"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_admin_update_day_v26','p_token text, p_staff_id uuid, p_date date, p_break_taken boolean, p_split_shift boolean, p_classification text, p_note text','[{"name":"p_token","type":"text"},{"name":"p_staff_id","type":"uuid"},{"name":"p_date","type":"date"},{"name":"p_break_taken","type":"boolean"},{"name":"p_split_shift","type":"boolean"},{"name":"p_classification","type":"text"},{"name":"p_note","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_equipment_list','p_token text, p_month date, p_page integer, p_admin boolean','[{"name":"p_token","type":"text"},{"name":"p_month","type":"date"},{"name":"p_page","type":"integer"},{"name":"p_admin","type":"boolean"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_equipment_review','p_token text, p_id uuid, p_version bigint, p_status text, p_note text','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_version","type":"bigint"},{"name":"p_status","type":"text"},{"name":"p_note","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_admin_notifications','p_token text, p_page integer, p_unread boolean','[{"name":"p_token","type":"text"},{"name":"p_page","type":"integer"},{"name":"p_unread","type":"boolean"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_legacy_admin_history','p_token text, p_start date, p_end date, p_staff_id uuid','[{"name":"p_token","type":"text"},{"name":"p_start","type":"date"},{"name":"p_end","type":"date"},{"name":"p_staff_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_management_key','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_admin_notification_detail','p_token text, p_id bigint, p_page integer','[{"name":"p_token","type":"text"},{"name":"p_id","type":"bigint"},{"name":"p_page","type":"integer"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_management_rejoin','p_token text, p_staff uuid, p_date date','[{"name":"p_token","type":"text"},{"name":"p_staff","type":"uuid"},{"name":"p_date","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_management_validate','p_key text','[{"name":"p_key","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_admin_management_key','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_management_dashboard','p_key text, p_date date','[{"name":"p_key","type":"text"},{"name":"p_date","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_public_month','p_month date','[{"name":"p_month","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_admin_set_break','p_token text, p_staff_id uuid, p_date date, p_break_taken boolean','[{"name":"p_token","type":"text"},{"name":"p_staff_id","type":"uuid"},{"name":"p_date","type":"date"},{"name":"p_break_taken","type":"boolean"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_admin_update_previous_record','p_token text, p_staff_id uuid, p_date date, p_punch_in timestamp with time zone, p_punch_out timestamp with time zone, p_break_taken boolean, p_split_shift boolean, p_shift2_in timestamp with time zone, p_shift2_out timestamp with time zone, p_note text','[{"name":"p_token","type":"text"},{"name":"p_staff_id","type":"uuid"},{"name":"p_date","type":"date"},{"name":"p_punch_in","type":"timestamp with time zone"},{"name":"p_punch_out","type":"timestamp with time zone"},{"name":"p_break_taken","type":"boolean"},{"name":"p_split_shift","type":"boolean"},{"name":"p_shift2_in","type":"timestamp with time zone"},{"name":"p_shift2_out","type":"timestamp with time zone"},{"name":"p_note","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_admin_push_state','p_token text, p_endpoint text','[{"name":"p_token","type":"text"},{"name":"p_endpoint","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_save_reason','p_token text, p_name text, p_id uuid','[{"name":"p_token","type":"text"},{"name":"p_name","type":"text"},{"name":"p_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_admin_push_save','p_token text, p_subscription jsonb, p_enabled boolean','[{"name":"p_token","type":"text"},{"name":"p_subscription","type":"jsonb"},{"name":"p_enabled","type":"boolean"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_admin_correct_pw','p_token text, p_kind text, p_id bigint, p_expected jsonb, p_quantity numeric, p_bucket text, p_reason text, p_request uuid','[{"name":"p_token","type":"text"},{"name":"p_kind","type":"text"},{"name":"p_id","type":"bigint"},{"name":"p_expected","type":"jsonb"},{"name":"p_quantity","type":"numeric"},{"name":"p_bucket","type":"text"},{"name":"p_reason","type":"text"},{"name":"p_request","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_admin_pw_corrections','p_token text, p_kind text, p_id bigint','[{"name":"p_token","type":"text"},{"name":"p_kind","type":"text"},{"name":"p_id","type":"bigint"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_admin_annual_sources','p_token text, p_staff uuid','[{"name":"p_token","type":"text"},{"name":"p_staff","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_delete_supplier','p_token text, p_id uuid','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_live_attendance_status','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_management_requests','p_token text, p_month date','[{"name":"p_token","type":"text"},{"name":"p_month","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_management_journey','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_live_attendance_check_out','p_token text, p_lat double precision, p_lon double precision, p_public_ip text, p_break_taken boolean','[{"name":"p_token","type":"text"},{"name":"p_lat","type":"double precision"},{"name":"p_lon","type":"double precision"},{"name":"p_public_ip","type":"text"},{"name":"p_break_taken","type":"boolean"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_admin_profile','p_token text, p_staff uuid','[{"name":"p_token","type":"text"},{"name":"p_staff","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_save_staff','p_token text, p_row jsonb, p_profile jsonb, p_expected timestamp with time zone','[{"name":"p_token","type":"text"},{"name":"p_row","type":"jsonb"},{"name":"p_profile","type":"jsonb"},{"name":"p_expected","type":"timestamp with time zone"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_pnl_history','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_pnl_save','p_token text, p_start date, p_end date, p_payload jsonb, p_expected timestamp with time zone','[{"name":"p_token","type":"text"},{"name":"p_start","type":"date"},{"name":"p_end","type":"date"},{"name":"p_payload","type":"jsonb"},{"name":"p_expected","type":"timestamp with time zone"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_pnl_delete','p_token text, p_start date, p_end date, p_expected timestamp with time zone','[{"name":"p_token","type":"text"},{"name":"p_start","type":"date"},{"name":"p_end","type":"date"},{"name":"p_expected","type":"timestamp with time zone"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_withdraw_request','p_token text, p_id uuid','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_documents','p_token text, p_staff uuid','[{"name":"p_token","type":"text"},{"name":"p_staff","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('submit_production','p_token text, p_items jsonb','[{"name":"p_token","type":"text"},{"name":"p_items","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_complaints','p_token text, p_month date','[{"name":"p_token","type":"text"},{"name":"p_month","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_document_reserve','p_token text, p_id uuid, p_category text, p_name text, p_type text, p_size integer, p_sha text','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_category","type":"text"},{"name":"p_name","type":"text"},{"name":"p_type","type":"text"},{"name":"p_size","type":"integer"},{"name":"p_sha","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_document_complete','p_token text, p_id uuid, p_drive text','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_drive","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_admin_requests','p_token text, p_month date','[{"name":"p_token","type":"text"},{"name":"p_month","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_document_private_file','p_token text, p_id uuid, p_staff uuid','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_staff","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_my_journey','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_review','p_token text, p_id uuid, p_expected timestamp with time zone, p_state text, p_from date, p_to date, p_payroll text, p_note text','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_expected","type":"timestamp with time zone"},{"name":"p_state","type":"text"},{"name":"p_from","type":"date"},{"name":"p_to","type":"date"},{"name":"p_payroll","type":"text"},{"name":"p_note","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_delete_inventory_session','p_token text, p_id uuid','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_admin_classify_day','p_token text, p_staff_id uuid, p_date date, p_classification text, p_note text','[{"name":"p_token","type":"text"},{"name":"p_staff_id","type":"uuid"},{"name":"p_date","type":"date"},{"name":"p_classification","type":"text"},{"name":"p_note","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_staff_dashboard','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_management_profiles','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_save_supplier','p_token text, p_row jsonb','[{"name":"p_token","type":"text"},{"name":"p_row","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_live_attendance_history','p_token text, p_month date','[{"name":"p_token","type":"text"},{"name":"p_month","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_staff_open_orders','p_token text, p_status text','[{"name":"p_token","type":"text"},{"name":"p_status","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_admin_save_notice','p_token text, p_value jsonb','[{"name":"p_token","type":"text"},{"name":"p_value","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_change_pin','p_token text, p_current_pin text, p_new_pin text','[{"name":"p_token","type":"text"},{"name":"p_current_pin","type":"text"},{"name":"p_new_pin","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_update_order_quantity','p_token text, p_id bigint, p_quantity numeric','[{"name":"p_token","type":"text"},{"name":"p_id","type":"bigint"},{"name":"p_quantity","type":"numeric"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_save_info_page','p_token text, p_row jsonb','[{"name":"p_token","type":"text"},{"name":"p_row","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('submit_wastage','p_token text, p_items jsonb','[{"name":"p_token","type":"text"},{"name":"p_items","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_orders','p_token text, p_from timestamp with time zone, p_to timestamp with time zone, p_status text, p_supplier text, p_search text','[{"name":"p_token","type":"text"},{"name":"p_from","type":"timestamp with time zone"},{"name":"p_to","type":"timestamp with time zone"},{"name":"p_status","type":"text"},{"name":"p_supplier","type":"text"},{"name":"p_search","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_save_master_items','p_token text, p_rows jsonb','[{"name":"p_token","type":"text"},{"name":"p_rows","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_save_internal_items','p_token text, p_rows jsonb','[{"name":"p_token","type":"text"},{"name":"p_rows","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('submit_order','p_token text, p_notes text, p_items jsonb','[{"name":"p_token","type":"text"},{"name":"p_notes","type":"text"},{"name":"p_items","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('submit_complaint_feedback','p_token text, p_type text, p_details text, p_hide_identity boolean','[{"name":"p_token","type":"text"},{"name":"p_type","type":"text"},{"name":"p_details","type":"text"},{"name":"p_hide_identity","type":"boolean"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_bootstrap','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_save_master_item','p_token text, p_row jsonb','[{"name":"p_token","type":"text"},{"name":"p_row","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_save_internal_item','p_token text, p_row jsonb','[{"name":"p_token","type":"text"},{"name":"p_row","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_save_staff','p_token text, p_row jsonb','[{"name":"p_token","type":"text"},{"name":"p_row","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_inventory_counts','p_token text, p_month date, p_section text','[{"name":"p_token","type":"text"},{"name":"p_month","type":"date"},{"name":"p_section","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_production_wastage','p_token text, p_kind text, p_from timestamp with time zone, p_to timestamp with time zone, p_status text','[{"name":"p_token","type":"text"},{"name":"p_kind","type":"text"},{"name":"p_from","type":"timestamp with time zone"},{"name":"p_to","type":"timestamp with time zone"},{"name":"p_status","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_update_pw_status','p_token text, p_kind text, p_ids bigint[], p_status text','[{"name":"p_token","type":"text"},{"name":"p_kind","type":"text"},{"name":"p_ids","type":"bigint[]"},{"name":"p_status","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_inventory_save_session','p_token text, p_row jsonb','[{"name":"p_token","type":"text"},{"name":"p_row","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_export_dataset','p_token text, p_dataset text, p_month date','[{"name":"p_token","type":"text"},{"name":"p_dataset","type":"text"},{"name":"p_month","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_delete_history_rows','p_token text, p_kind text, p_ids bigint[]','[{"name":"p_token","type":"text"},{"name":"p_kind","type":"text"},{"name":"p_ids","type":"bigint[]"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('admin_inventory_reset_count','p_token text, p_session_id uuid, p_staff_id uuid, p_section text','[{"name":"p_token","type":"text"},{"name":"p_session_id","type":"uuid"},{"name":"p_staff_id","type":"uuid"},{"name":"p_section","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_annual_history','p_token text, p_staff uuid','[{"name":"p_token","type":"text"},{"name":"p_staff","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_save_annual_history','p_token text, p_staff uuid, p_id uuid, p_expected timestamp with time zone, p_source uuid, p_year date, p_from date, p_to date, p_note text','[{"name":"p_token","type":"text"},{"name":"p_staff","type":"uuid"},{"name":"p_id","type":"uuid"},{"name":"p_expected","type":"timestamp with time zone"},{"name":"p_source","type":"uuid"},{"name":"p_year","type":"date"},{"name":"p_from","type":"date"},{"name":"p_to","type":"date"},{"name":"p_note","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_management_balances','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_management_cancel_resignation','p_token text, p_staff uuid, p_expected timestamp with time zone, p_actor text, p_note text','[{"name":"p_token","type":"text"},{"name":"p_staff","type":"uuid"},{"name":"p_expected","type":"timestamp with time zone"},{"name":"p_actor","type":"text"},{"name":"p_note","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_management_resignation','p_token text, p_staff uuid, p_day date, p_note text, p_actor text, p_expected timestamp with time zone','[{"name":"p_token","type":"text"},{"name":"p_staff","type":"uuid"},{"name":"p_day","type":"date"},{"name":"p_note","type":"text"},{"name":"p_actor","type":"text"},{"name":"p_expected","type":"timestamp with time zone"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_management_review','p_token text, p_id uuid, p_expected timestamp with time zone, p_state text, p_from date, p_to date, p_payroll text, p_note text, p_actor text, p_private_note text','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_expected","type":"timestamp with time zone"},{"name":"p_state","type":"text"},{"name":"p_from","type":"date"},{"name":"p_to","type":"date"},{"name":"p_payroll","type":"text"},{"name":"p_note","type":"text"},{"name":"p_actor","type":"text"},{"name":"p_private_note","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_people_document_expiry','p_token text, p_id uuid, p_staff uuid, p_expires date','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_staff","type":"uuid"},{"name":"p_expires","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_portal_export_summary','p_token text, p_dataset text, p_month date','[{"name":"p_token","type":"text"},{"name":"p_dataset","type":"text"},{"name":"p_month","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_people_email_draft','p_token text, p_request uuid','[{"name":"p_token","type":"text"},{"name":"p_request","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('attendance_live_management_month','p_key text, p_month date','[{"name":"p_key","type":"text"},{"name":"p_month","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_roster_my_week','p_token text, p_week date','[{"name":"p_token","type":"text"},{"name":"p_week","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_attendance_month_v12','p_token text, p_month date','[{"name":"p_token","type":"text"},{"name":"p_month","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('staff_live_attendance_check_in','p_token text, p_lat double precision, p_lon double precision, p_public_ip text, p_rejoin boolean','[{"name":"p_token","type":"text"},{"name":"p_lat","type":"double precision"},{"name":"p_lon","type":"double precision"},{"name":"p_public_ip","type":"text"},{"name":"p_rejoin","type":"boolean"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_management_report','p_token text, p_staff uuid','[{"name":"p_token","type":"text"},{"name":"p_staff","type":"uuid"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_people_save_staff','p_token text, p_row jsonb, p_profile jsonb, p_expected timestamp with time zone','[{"name":"p_token","type":"text"},{"name":"p_row","type":"jsonb"},{"name":"p_profile","type":"jsonb"},{"name":"p_expected","type":"timestamp with time zone"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_roster_published_export','p_token text, p_week date','[{"name":"p_token","type":"text"},{"name":"p_week","type":"date"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_portal_staff_alerts','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_portal_admin_summary','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_portal_duplicate_check','p_token text, p_kind text, p_items jsonb','[{"name":"p_token","type":"text"},{"name":"p_kind","type":"text"},{"name":"p_items","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_off_roster_preview','p_token text, p_week date, p_schedule jsonb','[{"name":"p_token","type":"text"},{"name":"p_week","type":"date"},{"name":"p_schedule","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_off_credit_history','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_off_credit','p_token text, p_id uuid, p_staff uuid[], p_days integer, p_date date, p_reason text, p_notice text, p_actor text, p_expected jsonb','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_staff","type":"uuid[]"},{"name":"p_days","type":"integer"},{"name":"p_date","type":"date"},{"name":"p_reason","type":"text"},{"name":"p_notice","type":"text"},{"name":"p_actor","type":"text"},{"name":"p_expected","type":"jsonb"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_off_reverse_credit','p_token text, p_id uuid, p_actor text, p_reason text','[{"name":"p_token","type":"text"},{"name":"p_id","type":"uuid"},{"name":"p_actor","type":"text"},{"name":"p_reason","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_off_my_events','p_token text','[{"name":"p_token","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_management_save_balance','p_token text, p_staff uuid, p_value integer, p_expected integer, p_reason text, p_actor text','[{"name":"p_token","type":"text"},{"name":"p_staff","type":"uuid"},{"name":"p_value","type":"integer"},{"name":"p_expected","type":"integer"},{"name":"p_reason","type":"text"},{"name":"p_actor","type":"text"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_hr_export_source','p_token text, p_staff uuid, p_ids uuid[]','[{"name":"p_token","type":"text"},{"name":"p_staff","type":"uuid"},{"name":"p_ids","type":"uuid[]"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_staff_inbox','p_token text, p_before bigint','[{"name":"p_token","type":"text"},{"name":"p_before","type":"bigint"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_staff_notice_read','p_token text, p_ids bigint[], p_read boolean, p_through bigint','[{"name":"p_token","type":"text"},{"name":"p_ids","type":"bigint[]"},{"name":"p_read","type":"boolean"},{"name":"p_through","type":"bigint"}]'::jsonb,false);
insert into goya_private.branch_rpc_registry values('goya_staff_appearance_save','p_token text, p_preferences jsonb, p_expected integer','[{"name":"p_token","type":"text"},{"name":"p_preferences","type":"jsonb"},{"name":"p_expected","type":"integer"}]'::jsonb,false);
create function public.goya_branch_call(p_branch uuid,p_operation text,p_args jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare sess public.app_sessions;reg record;arg jsonb;pieces text[]:='{}';expr text;result jsonb;archived boolean;begin
 if p_operation ~ '^goya_(push|notice_push|roster_push|admin_push)_(claim|check|result)$' then raise exception 'Unsupported branch operation';end if;
 if jsonb_typeof(p_args) is distinct from 'object' then raise exception 'Invalid request';end if;
 select archived_at is not null into archived from goya_private.branches where id=p_branch;
 if not found then raise exception 'Branch unavailable';end if;
 if p_operation in('attendance_live_public_dashboard','attendance_live_public_month') then null;
 elsif p_operation like 'attendance_live_management_%' then if not goya_private.branch_management_key(p_args->>'p_key') then raise exception 'Invalid management link';end if;
 else
 select * into sess from public.app_sessions where token=p_args->>'p_token' and expires_at>now();
 if sess.token is null then raise exception 'Session expired or unauthorized';end if;
 if not sess.is_admin and (not exists(select 1 from public.staff where id=sess.staff_id and active) or not exists(select 1 from goya_private.branch_members where branch_id=p_branch and staff_id=sess.staff_id)) then raise exception 'You do not have access to this branch';end if;
 end if;
 if p_operation='staff_live_attendance_check_in' and exists(select 1 from public.attendance_live_sessions where staff_id=sess.staff_id and branch_id<>p_branch and check_out_at is null and not coalesce(is_deleted,false)) then raise exception 'You are checked in at another branch. Check out there before starting this duty.';end if;
 if archived and (p_operation ~ '^(submit_|goya_equipment_submit|save_inventory_count|inventory_(submit|save)|goya_inventory_(shared_)?(save|submit)|staff_live_attendance_(check|set)|admin_inventory_save)' or (p_operation='goya_roster_save' and coalesce((p_args->>'p_publish')::boolean,false))) then raise exception 'This branch is archived. History is available; restore the branch before new operations';end if;
 select * into reg from goya_private.branch_rpc_registry r where name=p_operation and not exists(select 1 from jsonb_object_keys(p_args) k where not exists(select 1 from jsonb_array_elements(r.args) a where a->>'name'=k)) order by jsonb_array_length(args) limit 1;
 if not found then raise exception 'Unsupported branch operation';end if;
 for arg in select value from jsonb_array_elements(reg.args) loop
 if p_args ? (arg->>'name') then
 if arg->>'type' in('json','jsonb') then expr:=format('($1->%L)::%s',arg->>'name',arg->>'type');
 elsif right(arg->>'type',2)='[]' then expr:=format('case when jsonb_typeof($1->%L)=''array'' then array(select jsonb_array_elements_text($1->%L))::%s end',arg->>'name',arg->>'name',arg->>'type');
 else expr:=format('($1->>%L)::%s',arg->>'name',arg->>'type');end if;
 pieces:=array_append(pieces,format('%I := %s',arg->>'name',expr));end if;end loop;
 perform set_config('goya.branch_id',p_branch::text,true);
 if reg.returns_set then execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from public.%I(%s) x',p_operation,array_to_string(pieces,',')) into result using p_args;
 else execute format('select to_jsonb(public.%I(%s))',p_operation,array_to_string(pieces,',')) into result using p_args;end if;
 return result;end$$;
-- Grant only the authenticated gateway/catalog entry points; catalog tables remain private.
revoke all on function public.goya_branch_list(text,text),public.goya_branch_save(text,jsonb,integer),public.goya_branch_call(uuid,text,jsonb) from public;
grant execute on function public.goya_branch_list(text,text),public.goya_branch_save(text,jsonb,integer),public.goya_branch_call(uuid,text,jsonb) to anon,authenticated;
create view goya_private.branch_attendance_staff with(security_invoker=true) as select s.* from public.attendance_staff s where (s.portal_staff_id is null and goya_private.current_branch()='00000000-0000-0000-0000-000000000001') or exists(select 1 from goya_private.branch_members b where b.staff_id=s.portal_staff_id and b.branch_id=goya_private.current_branch()) or exists(select 1 from public.attendance_records r where r.attendance_staff_id=s.id) or exists(select 1 from public.attendance_device_records r where r.attendance_staff_id=s.id) or exists(select 1 from public.attendance_staff_submissions r where r.attendance_staff_id=s.id);grant select on goya_private.branch_attendance_staff to goya_operations;
CREATE OR REPLACE FUNCTION goya_private.require_employee_session(p_token text, p_admin boolean DEFAULT false)
 RETURNS app_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.app_sessions;
begin
  select * into s from public.app_sessions
  where token = p_token and expires_at > now() and is_admin = p_admin;
  if s.token is null then raise exception 'Session expired or unauthorized'; end if;
  return s;
end;
$function$
;
alter function goya_private.require_employee_session(text,boolean) owner to goya_operations;revoke all on function goya_private.require_employee_session(text,boolean) from public;grant execute on function goya_private.require_employee_session(text,boolean) to goya_operations;

CREATE OR REPLACE FUNCTION public.goya_hr_admin_profiles(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform goya_private.require_employee_session(p_token,true);
  return coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'active',s.active,'profile',to_jsonb(p),
    'history',(select jsonb_agg(jsonb_build_object('event',a.event,'created_at',a.created_at,'details',a.details)
      order by a.id desc) from goya_private.staff_hr_audit a where a.staff_id=s.id and a.event in ('Resignation','Rejoined')))
    order by s.active desc,s.name) from public.staff s
    left join goya_private.staff_hr_profiles p on p.staff_id=s.id),'[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_save_profile(p_token text, p_staff uuid, p_profile jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare previous goya_private.staff_hr_profiles; cessation date := nullif(p_profile->>'last_day','')::date;
begin
  perform goya_private.require_employee_session(p_token,true);
  perform 1 from public.staff where id=p_staff for update;
  if not found then raise exception 'Staff member was not found'; end if;
  select * into previous from goya_private.staff_hr_profiles where staff_id=p_staff;
  if cessation > (now() at time zone 'Asia/Dubai')::date then
    raise exception 'Record resignation on or after the last working day';
  end if;
  if previous.last_day is not null and cessation is null then
    raise exception 'Use the rejoin action to remove resigned status';
  end if;
  insert into goya_private.staff_hr_profiles(staff_id,joining_date,employee_code,position,branch,manager_notes,last_day)
  values(p_staff,nullif(p_profile->>'joining_date','')::date,left(coalesce(p_profile->>'employee_code',''),80),
    left(coalesce(p_profile->>'position',''),120),left(coalesce(p_profile->>'branch',''),120),
    left(coalesce(p_profile->>'manager_notes',''),4000),cessation)
  on conflict(staff_id) do update set joining_date=excluded.joining_date,employee_code=excluded.employee_code,
    position=excluded.position,branch=excluded.branch,manager_notes=excluded.manager_notes,last_day=excluded.last_day,updated_at=now();
  if cessation is not null then
    update public.staff set active=false where id=p_staff and active;
    update public.app_sessions set expires_at=now() where staff_id=p_staff and not is_admin and expires_at>now();
  end if;
  insert into goya_private.staff_hr_audit(staff_id,event,details)
  values(p_staff,case when previous.last_day is distinct from cessation and cessation is not null then 'Resignation' else 'Profile saved' end,
    jsonb_build_object('prior_joining_date',previous.joining_date,'prior_last_day',previous.last_day,'last_day',cessation));
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_rejoin(p_token text, p_staff uuid, p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare cessation date;
begin
  perform goya_private.require_employee_session(p_token,true);
  perform 1 from public.staff where id=p_staff for update;
  select last_day into cessation from goya_private.staff_hr_profiles where staff_id=p_staff;
  if cessation is null or p_date is null or p_date<=cessation or p_date>(now() at time zone 'Asia/Dubai')::date then
    raise exception 'Enter a rejoin date after the last working day and on or before today';
  end if;
  update goya_private.staff_hr_profiles set last_day=null,updated_at=now() where staff_id=p_staff;
  update public.staff set active=true where id=p_staff;
  insert into goya_private.staff_hr_audit(staff_id,event,details)
    values(p_staff,'Rejoined',jsonb_build_object('last_day',cessation,'rejoined_on',p_date));
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_staff_identity(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := (goya_private.require_employee_session(p_token,false)).staff_id;
begin
  return (select jsonb_build_object('id',id,'name',name) from public.staff where id=employee and active);
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_archive_import(p_token text, p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare inserted integer;
begin
  perform goya_private.require_employee_session(p_token,true);
  if jsonb_typeof(p_rows) is distinct from 'array' or octet_length(p_rows::text)>800000 then
    raise exception 'Invalid archive data';
  end if;
  insert into goya_private.roster_excel_archive(source_week,source_row,source_name,staff_id,shifts,pending_off,private_remarks)
  select source_week,source_row,source_name,staff_id,shifts,coalesce(pending_off,''),coalesce(private_remarks,'')
    from jsonb_to_recordset(p_rows) as r(source_week date,source_row integer,source_name text,
      staff_id uuid,shifts jsonb,pending_off text,private_remarks text)
  on conflict(branch_id,source_week,source_row) do update set staff_id=excluded.staff_id
  where roster_excel_archive.staff_id is null and excluded.staff_id is not null
    and roster_excel_archive.source_name=excluded.source_name and roster_excel_archive.shifts=excluded.shifts;
  get diagnostics inserted = row_count;
  return inserted;
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_archive_read(p_token text, p_admin boolean, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare sess public.app_sessions := goya_private.require_employee_session(p_token,p_admin);
begin
  if not p_admin and not exists(select 1 from public.staff where id=sess.staff_id and active) then
    raise exception 'Unauthorized';
  end if;
  return coalesce((select jsonb_agg(case when p_admin then to_jsonb(a) else
    jsonb_build_object('source_week',a.source_week,'shifts',a.shifts,'pending_off',a.pending_off) end
    order by a.source_week desc,a.source_row)
    from goya_private.roster_excel_archive a
    where (p_admin or a.staff_id=sess.staff_id) and a.source_week+6>=p_month and a.source_week<p_month+interval '1 month'),'[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_admin_email_settings(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform goya_private.require_employee_session(p_token,true);
  return goya_private.staff_leave_email_recipients();
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_save_email_settings(p_token text, p_owner text, p_hr text, p_expected integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  owner_address text := nullif(btrim(p_owner),'');
  hr_address text := nullif(btrim(p_hr),'');
  address text;
begin
  perform goya_private.require_employee_session(p_token,true);
  foreach address in array array[owner_address,hr_address] loop
    if address is not null and (length(address)>254 or address !~ '^[^[:space:]@<>,;]+@[^[:space:]@<>,;.]+([.][^[:space:]@<>,;.]+)+$') then
      raise exception 'Enter a valid email address for Owner and HR.';
    end if;
  end loop;
  if p_expected=0 then
    insert into goya_private.staff_leave_email_settings(owner_email,hr_email) values(owner_address,hr_address)
      on conflict(id) do nothing;
  else
    update goya_private.staff_leave_email_settings
      set owner_email=owner_address,hr_email=hr_address,revision=revision+1
      where id and revision=p_expected;
  end if;
  if not found then raise exception 'Email settings changed. Reload the settings before saving again.'; end if;
  return goya_private.staff_leave_email_recipients();
end $function$;

CREATE OR REPLACE FUNCTION public.goya_staff_remember(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare sess public.app_sessions; s public.staff; expiry timestamptz;
begin
 sess:=goya_private.require_employee_session(p_token,false);
 select * into s from public.staff where id=sess.staff_id and active for share;
 if not found then raise exception using message='DEVICE_LOGIN_REQUIRED',errcode='28000';end if;
 update public.app_sessions set expires_at=now()+interval '30 days' where token=p_token and not is_admin and expires_at>now() returning expires_at into expiry;
 if not found then raise exception using message='DEVICE_LOGIN_REQUIRED',errcode='28000';end if;
 insert into goya_private.staff_remembered_sessions(session_token,staff_id)values(p_token,s.id)on conflict(session_token)do nothing;
 return jsonb_build_object('expires_at',expiry);
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_week_leave(p_token text, p_week date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform goya_private.require_employee_session(p_token,true);
  return coalesce((select jsonb_agg(jsonb_build_object('id',id,'staff_id',staff_id,'kind',case when kind in ('Pending Off','Advance Off') then 'Weekly Off' when kind='Emergency Leave' then 'Other Leave' else kind end,
    'from',approved_from,'to',approved_to,'paid_request',kind in ('Pending Off','Advance Off')))
    from goya_private.staff_leave_requests where kind<>'Resignation' and state='Approved' and approved_from<=p_week+6 and approved_to>=p_week),'[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_admin_annual_sources(p_token text, p_staff uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform goya_private.require_employee_session(p_token,true);
  return (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'leave_from',r.approved_from,
    'leave_to',r.approved_to,'note',r.review_note) order by r.approved_from desc),'[]')
    from goya_private.staff_leave_requests r
    where r.staff_id=p_staff and r.kind='Annual Leave' and r.state='Approved'
      and r.approved_to < (now() at time zone 'Asia/Dubai')::date
      and not exists (select 1 from goya_private.staff_annual_history h where h.source_id=r.id));
end $function$;

CREATE OR REPLACE FUNCTION goya_private.document_staff(p_token text, p_staff uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid;
begin
  if p_staff is not null then
    perform goya_private.require_employee_session(p_token,true);
    return p_staff;
  end if;
  employee := (goya_private.require_employee_session(p_token,false)).staff_id;
  if not exists (select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized'; end if;
  return employee;
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_admin_profile(p_token text, p_staff uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform goya_private.require_employee_session(p_token,true);
  return (select to_jsonb(p) from goya_private.staff_hr_profiles p where p.staff_id=p_staff);
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_save_staff(p_token text, p_row jsonb, p_profile jsonb, p_expected timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := nullif(p_row->>'id','')::uuid;
  previous goya_private.staff_hr_profiles;
  cessation date := nullif(p_profile->>'last_day','')::date;
  saved jsonb;
begin
  perform goya_private.require_employee_session(p_token,true);
  if employee is not null then
    perform 1 from public.staff where id=employee for update;
    if not found then raise exception 'Staff member was not found'; end if;
    select * into previous from goya_private.staff_hr_profiles where staff_id=employee;
    if previous.updated_at is distinct from p_expected then
      raise exception 'The employment profile changed. Open it again before saving.';
    end if;
  end if;
  if cessation is not null then
    p_row := p_row || jsonb_build_object('active',false);
  end if;
  saved := public.admin_save_staff(p_token,p_row);
  if employee is null and cessation is null and coalesce(nullif(p_profile->>'joining_date',''),
    nullif(p_profile->>'position',''),nullif(p_profile->>'manager_notes','')) is null then
    insert into goya_private.staff_hr_profiles(staff_id) values((saved->>'id')::uuid);
    return;
  end if;
  perform public.goya_hr_save_profile(p_token,(saved->>'id')::uuid,
    p_profile || jsonb_build_object('employee_code',coalesce(previous.employee_code,''),'branch','GOYA'));
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_withdraw_request(p_token text, p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := (goya_private.require_employee_session(p_token,false)).staff_id;
begin
  perform 1 from public.staff where id=employee and active for update;
  if not found then raise exception 'Unauthorized'; end if;
  update goya_private.staff_leave_requests set state='Withdrawn',updated_at=clock_timestamp()
    where id=p_id and staff_id=employee and state='Pending';
  if not found then raise exception 'Only your pending requests can be withdrawn'; end if;
  insert into goya_private.staff_hr_audit(staff_id,event,details)
    values(employee,'Leave withdrawn',jsonb_build_object('request',p_id));
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_admin_requests(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform goya_private.require_employee_session(p_token,true);
  return coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('name',s.name) order by r.created_at desc)
    from goya_private.staff_leave_requests r join public.staff s on s.id=r.staff_id
    where p_month is null or (coalesce(approved_to,requested_to)>=p_month
      and coalesce(approved_from,requested_from)<p_month+interval '1 month')),'[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_my_journey(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid := (goya_private.require_employee_session(p_token,false)).staff_id;
begin
  if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized'; end if;
  return jsonb_build_object('profile',(select jsonb_build_object('joining_date',joining_date,'employee_code',employee_code,
    'position',position,'branch',branch,'mobile',mobile,'email',email,'address',address,'nationality',nationality,'date_of_birth',date_of_birth,'employment_type',employment_type,'probation_end',probation_end,'emergency_name',emergency_name,'emergency_relationship',emergency_relationship,'emergency_phone',emergency_phone) from goya_private.staff_hr_profiles where staff_id=employee),
    'archived_pending_off',(select jsonb_build_object('value',pending_off,'week',source_week)
      from goya_private.roster_excel_archive where staff_id=employee and pending_off<>'' order by source_week desc,source_row desc limit 1),
    'archived_annual_days',coalesce((select jsonb_agg(distinct item->>'date')
      from goya_private.roster_excel_archive a cross join lateral jsonb_array_elements(a.shifts) item
      where a.staff_id=employee and lower(btrim(item->>'value'))='annual leave'),'[]'::jsonb),
    'requests',coalesce((select jsonb_agg(to_jsonb(r)-'drive_file_id'-'staff_id' order by requested_from desc,created_at desc)
      from goya_private.staff_leave_requests r where r.staff_id=employee),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_review(p_token text, p_id uuid, p_expected timestamp with time zone, p_state text, p_from date, p_to date, p_payroll text, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare previous goya_private.staff_leave_requests;
begin
  perform goya_private.require_employee_session(p_token,true);
  select * into previous from goya_private.staff_leave_requests where id=p_id;
  if p_state is null or p_state not in ('Approved','Declined') or length(coalesce(p_note,''))>2000
    or (p_state='Approved' and (p_from is null or p_to is null or p_to<p_from or p_payroll is null or p_payroll not in ('Paid','Unpaid')))
    or (p_state='Declined' and p_payroll is distinct from 'Absent' and p_payroll is not null)
    or (p_payroll='Absent' and previous.kind<>'Sick Leave') then raise exception 'Invalid leave decision'; end if;
  perform 1 from public.staff where id=previous.staff_id for update;
  if p_state='Approved' and exists(select 1 from goya_private.staff_leave_requests other
    where other.staff_id=previous.staff_id and other.id<>p_id and other.state='Approved'
      and other.approved_from<=p_to and other.approved_to>=p_from) then
    raise exception 'There is already approved leave for part of this period';
  end if;
  update goya_private.staff_leave_requests set state=p_state, approved_from=case when p_state='Approved' then p_from end,
    approved_to=case when p_state='Approved' then p_to end,payroll=p_payroll,review_note=coalesce(p_note,''),updated_at=clock_timestamp()
    where id=p_id and updated_at=p_expected;
  if not found then raise exception 'Request changed. Reload before saving.'; end if;
  insert into goya_private.staff_hr_audit(staff_id,event,details) values(previous.staff_id,'Leave reviewed',
    jsonb_build_object('request',p_id,'prior_state',previous.state,'prior_from',previous.approved_from,'prior_to',previous.approved_to,
      'prior_payroll',previous.payroll,'prior_note',previous.review_note));
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_save_annual_history(p_token text, p_staff uuid, p_id uuid, p_expected timestamp with time zone, p_source uuid, p_year date, p_from date, p_to date, p_note text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare joined date;
  today date := (now() at time zone 'Asia/Dubai')::date;
  result uuid;
begin
  perform goya_private.require_employee_session(p_token,true);
  perform 1 from public.staff where id=p_staff for update;
  if not found then raise exception 'Staff record unavailable.'; end if;
  select joining_date into joined from goya_private.staff_hr_profiles where staff_id=p_staff;
  if joined is null then raise exception 'Add a joining date in Staff Management first.'; end if;
  if p_year is null or p_year < joined or p_year > today or
     p_year <> (joined + make_interval(years=>extract(year from p_year)::int-extract(year from joined)::int))::date
  then raise exception 'Choose a valid service year.'; end if;
  if (p_from is null) <> (p_to is null) or p_to < p_from or p_from < joined or p_to >= today
     or (p_from is null and (joined + make_interval(years=>extract(year from p_year)::int-extract(year from joined)::int+1))::date > today)
  then raise exception 'Enter both past leave dates, or leave dates blank for an earlier service year.'; end if;
  if p_source is not null and not exists (select 1 from goya_private.staff_leave_requests r
    where r.id=p_source and r.staff_id=p_staff and r.kind='Annual Leave' and r.state='Approved' and r.approved_to < today)
  then raise exception 'This annual leave record is unavailable.'; end if;
  if p_expected is null then
    insert into goya_private.staff_annual_history(id,staff_id,source_id,service_year,leave_from,leave_to,note)
      values(p_id,p_staff,p_source,p_year,p_from,p_to,coalesce(p_note,''))
      on conflict do nothing returning id into result;
    if result is null then
      select id into result from goya_private.staff_annual_history h where h.id=p_id and h.staff_id=p_staff
      and (h.source_id,h.service_year,h.leave_from,h.leave_to,h.note)
        is not distinct from (p_source,p_year,p_from,p_to,coalesce(p_note,''));
    end if;
  else
    update goya_private.staff_annual_history h set service_year=p_year,leave_from=p_from,leave_to=p_to,
      note=coalesce(p_note,''),updated_at=clock_timestamp() where h.id=p_id and h.staff_id=p_staff
      and h.updated_at=p_expected returning id into result;
  end if;
  if result is null then raise exception 'The record changed. Reopen the staff card and try again.'; end if;
  return result;
end $function$;

CREATE OR REPLACE FUNCTION public.goya_people_email_draft(p_token text, p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid:=(goya_private.require_employee_session(p_token,false)).staff_id; request goya_private.staff_leave_requests; recipients jsonb;
begin
 select * into request from goya_private.staff_leave_requests where id=p_request and staff_id=employee and kind in ('Annual Leave','Resignation') and state not in ('Withdrawn','Declined');
 if not found then raise exception 'Request is not available for email'; end if;
 if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized'; end if;
 recipients:=public.goya_hr_worker_email_settings();
 return jsonb_build_object('owner',recipients->>'owner_email','hr',recipients->>'hr_email','manager',recipients->>'manager_email',
 'staff',(select jsonb_build_object('name',s.name,'code',p.employee_code,'position',p.position,'mobile',p.mobile) from public.staff s left join goya_private.staff_hr_profiles p on p.staff_id=s.id where s.id=employee),
 'request',to_jsonb(request)-'drive_file_id'-'review_note'-'staff_id');
end $function$;

CREATE OR REPLACE FUNCTION public.goya_people_save_staff(p_token text, p_row jsonb, p_profile jsonb, p_expected timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid:=nullif(p_row->>'id','')::uuid; previous goya_private.staff_hr_profiles; saved jsonb;
begin
 perform goya_private.require_employee_session(p_token,true);
 if nullif(btrim(p_row->>'name'),'') is null then raise exception 'Full name is required'; end if;
 if employee is null and (nullif(p_profile->>'joining_date','') is null or nullif(btrim(p_profile->>'mobile'),'') is null
 or nullif(btrim(p_profile->>'position'),'') is null or jsonb_array_length(coalesce(p_row->'sections','[]'))=0) then
 raise exception 'Full name, joining date, mobile, position, section and PIN are required'; end if;
 if nullif(p_profile->>'date_of_birth','')::date>(now() at time zone 'Asia/Dubai')::date then raise exception 'Check date of birth'; end if;
 if nullif(p_profile->>'probation_end','')::date<nullif(p_profile->>'joining_date','')::date then raise exception 'Probation must end on or after joining'; end if;
 if employee is not null then
  perform 1 from public.staff where id=employee for update;
  if not found then raise exception 'Staff member not found'; end if;
  select * into previous from goya_private.staff_hr_profiles where staff_id=employee;
  if previous.updated_at is distinct from p_expected then raise exception 'Profile changed. Reopen it before saving.'; end if;
  if previous.last_day is not null and coalesce((p_row->>'active')::boolean,false) then raise exception 'Use Rejoin staff to reactivate'; end if;
 end if;
 if nullif(p_profile->>'last_day','') is distinct from previous.last_day::text then raise exception 'Use the resignation action to change last working day'; end if;
 saved:=public.admin_save_staff(p_token,p_row); employee:=(saved->>'id')::uuid;
 perform public.goya_hr_save_profile(p_token,employee,p_profile||jsonb_build_object('employee_code',coalesce(previous.employee_code,''),'branch','GOYA'));
 update goya_private.staff_hr_profiles set roster_group=coalesce(p_profile->>'roster_group',roster_group),mobile=left(coalesce(p_profile->>'mobile',mobile),60),email=left(coalesce(p_profile->>'email',email),254),address=left(coalesce(p_profile->>'address',address),1000),
 nationality=left(coalesce(p_profile->>'nationality',nationality),100),date_of_birth=nullif(p_profile->>'date_of_birth','')::date,
 employment_type=left(coalesce(p_profile->>'employment_type',employment_type),80),probation_end=nullif(p_profile->>'probation_end','')::date,
 emergency_name=left(coalesce(p_profile->>'emergency_name',emergency_name),120),emergency_relationship=left(coalesce(p_profile->>'emergency_relationship',emergency_relationship),80),
 emergency_phone=left(coalesce(p_profile->>'emergency_phone',emergency_phone),60) where staff_id=employee;
 return jsonb_build_object('id',employee,'profile',(select to_jsonb(p) from goya_private.staff_hr_profiles p where p.staff_id=employee));
end $function$;

CREATE OR REPLACE FUNCTION public.goya_hr_export_source(p_token text, p_staff uuid, p_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare hr text;files jsonb;begin
 perform goya_private.require_employee_session(p_token,true);
 select hr_email into hr from goya_private.staff_leave_email_settings where id;
 if hr is null or btrim(hr)='' then raise exception 'Set the HR email in Settings before exporting';end if;
 if p_ids is null or cardinality(p_ids) not between 1 and 30 or cardinality(p_ids)<>(select count(distinct x) from unnest(p_ids)x) then raise exception 'Select current documents';end if;
 select jsonb_agg(jsonb_build_object('id',d.id,'category',d.category,'title',d.custom_title,'name',d.file_name,'type',d.mime_type,'size',d.byte_size,'sha',d.sha256,'driveId',d.drive_file_id)) into files
 from goya_private.staff_document_versions d where d.staff_id=p_staff and d.id=any(p_ids) and d.uploaded_at is not null and d.category<>'profile-photo'
 and not exists(select 1 from goya_private.staff_document_versions newer where newer.staff_id=d.staff_id and newer.category=d.category and newer.uploaded_at is not null and (newer.uploaded_at,newer.id)>(d.uploaded_at,d.id));
 if coalesce(jsonb_array_length(files),0)<>cardinality(p_ids) then raise exception 'Documents changed. Reopen HR export and check the selection';end if;
 return jsonb_build_object('hr',btrim(hr),'files',files);
end $function$;

CREATE OR REPLACE FUNCTION public.goya_staff_inbox(p_token text, p_before bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid:=(goya_private.require_employee_session(p_token,false)).staff_id;settings jsonb;begin
 if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized';end if;
 perform goya_private.staff_notice_refresh(employee);
 select jsonb_build_object('value',preferences,'revision',revision) into settings from goya_private.staff_appearance where staff_id=employee;
 return jsonb_build_object('staff_id',employee,'preferences',coalesce(settings,'{"value":{"mode":"auto","accent":"default","text_size":"normal"},"revision":0}'),
 'unread',(select count(*) from goya_private.staff_notifications where staff_id=employee and read_at is null),
 'max_id',(select max(id) from goya_private.staff_notifications where staff_id=employee),
 'items',coalesce((select jsonb_agg(to_jsonb(q) order by q.id desc) from (select id,event_key,kind,title,body,target,created_at,read_at from goya_private.staff_notifications where staff_id=employee and (p_before is null or id<p_before) order by id desc limit 100)q),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.goya_staff_notice_read(p_token text, p_ids bigint[], p_read boolean, p_through bigint DEFAULT NULL::bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid:=(goya_private.require_employee_session(p_token,false)).staff_id;begin
 if not exists(select 1 from public.staff where id=employee and active) or p_read is null or coalesce(cardinality(p_ids),0)>200 or (p_through is not null and not p_read) then raise exception 'Invalid notification update';end if;
 update goya_private.staff_notifications set read_at=case when p_read then coalesce(read_at,clock_timestamp()) else null end
 where staff_id=employee and (id=any(p_ids) or (p_through is not null and id<=p_through));
end $function$;

CREATE OR REPLACE FUNCTION public.goya_staff_appearance_save(p_token text, p_preferences jsonb, p_expected integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare employee uuid:=(goya_private.require_employee_session(p_token,false)).staff_id;result jsonb;scene text;saved jsonb;sound_notification jsonb;sound_attendance jsonb;volume text;begin
 if not exists(select 1 from public.staff where id=employee and active) then raise exception 'Unauthorized';end if;
 if jsonb_typeof(p_preferences) is distinct from 'object' or p_preferences->>'mode' is null or p_preferences->>'mode' not in ('auto','light','dark') or p_preferences->>'accent' is null or p_preferences->>'accent' not in ('default','green','blue','purple','brown','teal') or p_preferences->>'text_size' is null or p_preferences->>'text_size' not in ('normal','large') or p_expected is null then raise exception 'Choose a supported theme preset';end if;
 scene:=coalesce(p_preferences->>'background',(select preferences->>'background' from goya_private.staff_appearance where staff_id=employee),'default');
 if scene not in ('default','ocean','forest','lavender','sand') then raise exception 'Choose a supported background preset';end if;
 select preferences into saved from goya_private.staff_appearance where staff_id=employee;
 sound_notification:=coalesce(p_preferences->'notification_sound',saved->'notification_sound','true'::jsonb);
 sound_attendance:=coalesce(p_preferences->'attendance_sound',saved->'attendance_sound','true'::jsonb);
 volume:=coalesce(p_preferences->>'sound_volume',saved->>'sound_volume','35');
 if jsonb_typeof(sound_notification)<>'boolean' or jsonb_typeof(sound_attendance)<>'boolean' or volume !~ '^(100|[0-9]{1,2})$' then raise exception 'Choose valid sound switches and volume (0–100)';end if;
 p_preferences:=jsonb_build_object('mode',p_preferences->>'mode','accent',p_preferences->>'accent','text_size',p_preferences->>'text_size','background',scene,'notification_sound',sound_notification,'attendance_sound',sound_attendance,'sound_volume',volume::integer);
 if p_expected=0 then insert into goya_private.staff_appearance(staff_id,preferences) values(employee,p_preferences) on conflict do nothing returning jsonb_build_object('value',preferences,'revision',revision) into result;
 else update goya_private.staff_appearance set preferences=p_preferences,revision=revision+1,updated_at=clock_timestamp() where staff_id=employee and revision=p_expected returning jsonb_build_object('value',preferences,'revision',revision) into result;end if;
 if result is null then raise exception 'Appearance changed on another device. Reopen Appearance and try again.';end if;return result;
end $function$;
CREATE OR REPLACE FUNCTION goya_private.release_branch_roster_off(p_token text, p_staff uuid, p_from date, p_to date, p_actor text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n integer;b jsonb;r record;begin
 select count(*) into n from goya_private.roster_off_charges where staff_id=p_staff and charged and off_date between p_from and p_to;
 if n=0 then return;end if;b:=goya_private.off_snapshot(p_staff);
 perform public.goya_management_save_balance(p_token,p_staff,(b->>'balance')::integer+n,(b->>'revision')::integer,'Paid Off transferred to approved request',p_actor);
 for r in update goya_private.roster_off_charges set charged=false,updated_at=clock_timestamp() where staff_id=p_staff and charged and off_date between p_from and p_to returning off_date loop
 insert into goya_private.off_balance_events(staff_id,delta,balance_after,effective_on,source,source_id,notice,actor)
 values(p_staff,1,(b->>'balance')::integer+n,r.off_date,'request-transfer',r.off_date::text,'Roster Paid Off returned before applying approved leave',p_actor);
 end loop;
end $function$
;
alter function goya_private.release_branch_roster_off(text,uuid,date,date,text) owner to goya_operations;revoke all on function goya_private.release_branch_roster_off(text,uuid,date,date,text) from public;grant execute on function goya_private.release_branch_roster_off(text,uuid,date,date,text) to goya_operations;
create or replace function goya_private.release_roster_off(p_token text,p_staff uuid,p_from date,p_to date,p_actor text) returns void language plpgsql security definer set search_path='' as $$declare b uuid;original uuid:=goya_private.current_branch();begin for b in select id from goya_private.branches loop perform set_config('goya.branch_id',b::text,true);perform goya_private.release_branch_roster_off(p_token,p_staff,p_from,p_to,p_actor);end loop;perform set_config('goya.branch_id',original::text,true);end$$;
create unique index roster_one_paid_off_per_day on goya_private.roster_off_charges(staff_id,off_date) where charged;
create function goya_private.validate_branch_roster(p_branch uuid,p_week date,p_schedule jsonb) returns void language plpgsql security definer set search_path='' as $$declare conflict_name text;begin
 with incoming as(select member.key employee,p_week+day.ordinality::int-1 as d,segment.value seg from jsonb_each(p_schedule->'staff') member cross join lateral jsonb_array_elements(member.value) with ordinality day(value,ordinality) cross join lateral jsonb_array_elements(day.value->'segments') segment where day.value->>'kind'='Shift'),
 existing as(select member.key employee,p.week_start+day.ordinality::int-1 as d,segment.value seg,b.name from goya_private.roster_publications p join goya_private.roster_weeks w on (w.branch_id,w.week_start,w.published_revision)=(p.branch_id,p.week_start,p.revision) join goya_private.branches b on b.id=p.branch_id cross join lateral jsonb_each(p.schedule->'staff') member cross join lateral jsonb_array_elements(member.value) with ordinality day(value,ordinality) cross join lateral jsonb_array_elements(day.value->'segments') segment where p.branch_id<>p_branch and p.week_start between p_week-7 and p_week+7 and day.value->>'kind'='Shift')
 select e.name into conflict_name from incoming i join existing e on e.employee=i.employee where tsrange(i.d+(i.seg->>'start')::time,i.d+(i.seg->>'end')::time+case when i.seg->>'end'<i.seg->>'start' then interval '1 day' else interval '0' end,'[)') && tsrange(e.d+(e.seg->>'start')::time,e.d+(e.seg->>'end')::time+case when e.seg->>'end'<e.seg->>'start' then interval '1 day' else interval '0' end,'[)') limit 1;
 if conflict_name is not null then raise exception 'A staff shift overlaps the published roster at %. Adjust the duty time before publishing.',conflict_name;end if;end$$;
revoke all on function goya_private.validate_branch_roster(uuid,date,jsonb) from public;grant execute on function goya_private.validate_branch_roster(uuid,date,jsonb) to goya_operations;

CREATE OR REPLACE FUNCTION public.goya_roster_save(p_token text, p_week date, p_expected integer, p_schedule jsonb, p_publish boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare next_revision integer; member record; day jsonb; segment jsonb; previous_end integer; start_min integer; end_min integer;
  snapshot jsonb; leave_day record; approval_actor text;
begin
  perform public.require_session(p_token,true);
  approval_actor:=p_schedule->>'approval_actor';p_schedule:=p_schedule-'approval_actor';
  if p_publish then
   perform 1 from goya_private.branch_staff where id::text in(select key from jsonb_each(p_schedule->'staff'))
    or id in(select staff_id from goya_private.roster_off_charges where charged and off_date between p_week and p_week+6) order by id for update;
  end if;
  if p_week is null or p_schedule is null or p_expected is null or p_publish is null
    or extract(isodow from p_week)<>1 or jsonb_typeof(p_schedule->'staff') is distinct from 'object'
    or jsonb_typeof(p_schedule->'notes') is distinct from 'string'
    or length(p_schedule->>'notes')>2000 or octet_length(p_schedule::text)>262144 then
    raise exception 'Invalid roster';
  end if;
  for member in select * from jsonb_each(p_schedule->'staff') loop
    if not exists(select 1 from goya_private.branch_staff s where s.id::text=member.key and (not p_publish or s.active))
      or jsonb_typeof(member.value) is distinct from 'array' then raise exception 'Invalid roster staff'; end if;
    if jsonb_array_length(member.value)<>7 then raise exception 'Enter all seven days'; end if;
    for day in select value from jsonb_array_elements(member.value) loop
      if day='null'::jsonb then continue; end if;
      if jsonb_typeof(day) is distinct from 'object'
        or coalesce(day->>'kind','') not in ('Shift','Weekly Off','Annual Leave','Sick Leave','Other Leave')
        or jsonb_typeof(day->'segments') is distinct from 'array' then raise exception 'Invalid roster day'; end if;
      if day ? 'off_source' and (day->>'kind'<>'Weekly Off' or coalesce(day->>'off_source','') not in ('balance','advance')) then raise exception 'Invalid Paid Off source';end if;
      if day ? 'label' and (day->>'kind'<>'Shift' or jsonb_typeof(day->'label') is distinct from 'string'
        or length(btrim(day->>'label')) not between 1 and 60 or day->>'label' ~ '[[:cntrl:]]') then
        raise exception 'Enter a custom shift name of 1–60 characters';
      end if;
      if length(coalesce(day->>'note',''))>500 then raise exception 'Shift note is too long'; end if;
      if day->>'kind'='Shift' then
        if jsonb_array_length(day->'segments') not between 1 and 2 then raise exception 'A shift needs one or two time blocks'; end if;
        previous_end := -1;
        for segment in select value from jsonb_array_elements(day->'segments') loop
          if coalesce(segment->>'start','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
            or coalesce(segment->>'end','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
            or coalesce(segment->>'break','') !~ '^[0-9]{1,3}$' then raise exception 'Invalid shift time'; end if;
          start_min := extract(epoch from (segment->>'start')::time)::integer/60;
          end_min := extract(epoch from (segment->>'end')::time)::integer/60;
          if end_min<start_min then end_min := end_min+1440; end if;
          if start_min<previous_end or end_min<=start_min or (segment->>'break')::integer>=end_min-start_min then
            raise exception 'Shift blocks overlap or break exceeds the shift';
          end if;
          previous_end := end_min;
        end loop;
      elsif jsonb_array_length(day->'segments')<>0 then raise exception 'Off or leave days cannot contain a shift'; end if;
    end loop;
  end loop;
  snapshot := p_schedule;
  if p_publish then
    for leave_day in
      select r.staff_id::text as staff_id,case when r.kind in ('Pending Off','Advance Off') then 'Weekly Off' when r.kind='Emergency Leave' then 'Other Leave' else r.kind end as kind,r.kind as request_kind,d as day_index
      from goya_private.staff_leave_requests r join goya_private.branch_staff s on s.id=r.staff_id and s.active
      cross join generate_series(0,6) as dates(d)
      where r.kind<>'Resignation' and r.state='Approved' and p_week+d between r.approved_from and r.approved_to
      order by r.staff_id,d
    loop
      if not ((snapshot->'staff') ? leave_day.staff_id) then
        snapshot := jsonb_set(snapshot,array['staff',leave_day.staff_id],'[null,null,null,null,null,null,null]');
      end if;
      snapshot := jsonb_set(snapshot,array['staff',leave_day.staff_id,leave_day.day_index::text],
        jsonb_build_object('kind',leave_day.kind,'segments','[]'::jsonb,'note','')||case when leave_day.request_kind in ('Pending Off','Advance Off') then jsonb_build_object('off_source','request') else '{}'::jsonb end);
    end loop;
  end if;
  if p_publish then
    for member in select * from jsonb_each(snapshot->'staff') loop
      for start_min in 0..6 loop
        if not goya_private.employed_on(member.key::uuid,p_week+start_min) then
          snapshot:=jsonb_set(snapshot,array['staff',member.key,start_min::text],'null'::jsonb);
        end if;
      end loop;
    end loop;
  end if;
  if p_publish then perform goya_private.validate_branch_roster(goya_private.current_branch(),p_week,snapshot);end if;
  if p_publish and not exists(select 1 from jsonb_each(snapshot->'staff') m
    cross join lateral jsonb_array_elements(m.value) as days(value) where days.value<>'null'::jsonb) then
    raise exception 'Add at least one shift or day status before publishing';
  end if;
  if p_expected=0 then
    insert into goya_private.roster_weeks(week_start,draft) values(p_week,p_schedule)
      on conflict do nothing returning revision into next_revision;
  else
    update goya_private.roster_weeks set draft=p_schedule,revision=revision+1 where week_start=p_week and revision=p_expected
      returning revision into next_revision;
  end if;
  if next_revision is null then raise exception 'This roster changed. Reload before saving.'; end if;
  if p_publish then
    perform goya_private.reconcile_roster_off(p_token,p_week,snapshot,next_revision,approval_actor);
    insert into goya_private.roster_publications(week_start,revision,schedule) values(p_week,next_revision,snapshot);
    update goya_private.roster_weeks set published_revision=next_revision where week_start=p_week;
  end if;
  return next_revision;
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_bootstrap(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.require_session(p_token,true);
  perform public.attendance_sync_portal_staff(p_token);
  return jsonb_build_object(
    'staff',(select coalesce(jsonb_agg(to_jsonb(x) order by lower(x.name)),'[]'::jsonb) from goya_private.branch_attendance_staff x where x.active=true),
    'settings',(select coalesce(value,'{}'::jsonb) from public.attendance_settings where key='rules')
  );
end; $function$;

CREATE OR REPLACE FUNCTION public.attendance_sync_portal_staff(p_token text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int;
begin
  perform public.require_session(p_token,true);
  insert into public.attendance_staff(portal_staff_id,name,employment_type,active)
  select s.id,s.name,'Full Time',s.active from public.staff s
  where not exists(select 1 from goya_private.branch_attendance_staff a where a.portal_staff_id=s.id)
  on conflict do nothing;
  get diagnostics n = row_count;
  update public.attendance_staff a set name=s.name,active=s.active,updated_at=now()
  from public.staff s where a.portal_staff_id=s.id;
  return n;
end; $function$;

CREATE OR REPLACE FUNCTION public.attendance_import_records(p_token text, p_rows jsonb, p_file_name text, p_upload_type text, p_date_from date, p_date_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it jsonb; s_id uuid; r_id uuid; n int:=0; skipped int:=0; code text; nm text;
begin
 perform public.require_session(p_token,true);
 for it in select * from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
   nm:=trim(it->>'name'); code:=nullif(trim(it->>'employee_code'),'');
   if nm='' or nullif(it->>'operational_date','') is null then continue; end if;
   select id into s_id from goya_private.branch_attendance_staff where (code is not null and employee_code=code) or lower(name)=lower(nm) order by (employee_code=code) desc nulls last limit 1;
   if s_id is null then insert into public.attendance_staff(name,employee_code,employment_type) values(nm,code,'Full Time') returning id into s_id; end if;
   insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,device_file)
   values(s_id,(it->>'operational_date')::date,nullif(it->>'punch_in','')::timestamp,nullif(it->>'punch_out','')::timestamp,coalesce((it->>'break_taken')::boolean,true),nullif(it->>'note',''),'device',p_file_name)
   on conflict(branch_id,attendance_staff_id,operational_date) do update set
      punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,
      note=coalesce(nullif(excluded.note,''),public.attendance_records.note),device_file=excluded.device_file,updated_at=now()
   where public.attendance_records.source <> 'manual'
   returning id into r_id;
   if r_id is null then skipped:=skipped+1; else n:=n+1; perform public.attendance_recalc(r_id); end if;
 end loop;
 insert into public.attendance_uploads(file_name,upload_type,date_from,date_to,rows_imported) values(p_file_name,coalesce(p_upload_type,'Daily'),p_date_from,p_date_to,n);
 return jsonb_build_object('imported',n,'manual_preserved',skipped);
end; $function$;

CREATE OR REPLACE FUNCTION public.attendance_records_range(p_token text, p_start date, p_end date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 perform public.require_session(p_token,true);
 perform public.attendance_sync_portal_staff(p_token);
 return jsonb_build_object(
   'records',(select coalesce(jsonb_agg(to_jsonb(q) order by q.operational_date desc,lower(q.staff_name)),'[]'::jsonb) from (
     select r.*,s.name staff_name,s.employee_code,s.employment_type,s.designation,s.default_start_time,s.expected_presence_minutes staff_expected_presence_minutes,s.default_break_minutes staff_break_minutes
     from public.attendance_records r join goya_private.branch_attendance_staff s on s.id=r.attendance_staff_id
     where r.operational_date between p_start and p_end
   ) q),
   'staff',(select coalesce(jsonb_agg(to_jsonb(s) order by lower(s.name)),'[]'::jsonb) from goya_private.branch_attendance_staff s where s.active=true)
 );
end; $function$;

CREATE OR REPLACE FUNCTION public.staff_attendance_submit(p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; v_id uuid;
begin
 sess:=public.require_session(p_token,false);
 select id into a_id from goya_private.branch_attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then
   insert into public.attendance_staff(portal_staff_id,name,employment_type,active)
   select id,name,'Full Time',active from public.staff where id=sess.staff_id returning id into a_id;
 end if;
 -- Replace only an existing Pending request for the same day; Approved history is preserved.
 delete from public.attendance_staff_submissions where attendance_staff_id=a_id and operational_date=p_operational_date and status='Pending';
 insert into public.attendance_staff_submissions(attendance_staff_id,portal_staff_id,operational_date,punch_in,punch_out,break_taken,day_off,note,status)
 values(a_id,sess.staff_id,p_operational_date,case when p_day_off then null else p_punch_in end,case when p_day_off then null else p_punch_out end,coalesce(p_break_taken,true),coalesce(p_day_off,false),p_note,'Pending') returning id into v_id;
 return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.staff_attendance_month(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; sd date; ed date;
begin
 sess:=public.require_session(p_token,false);
 select id into a_id from goya_private.branch_attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then return jsonb_build_object('records','[]'::jsonb,'submissions','[]'::jsonb); end if;
 sd:=date_trunc('month',p_month)::date;ed:=(sd+interval '1 month')::date;
 return jsonb_build_object(
  'records',coalesce((select jsonb_agg(to_jsonb(r) order by r.operational_date) from public.attendance_records r where r.attendance_staff_id=a_id and r.operational_date>=sd and r.operational_date<ed),'[]'::jsonb),
  'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.operational_date,s.submitted_at desc) from public.attendance_staff_submissions s where s.attendance_staff_id=a_id and s.operational_date>=sd and s.operational_date<ed),'[]'::jsonb)
 );
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_admin_submissions(p_token text, p_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 perform public.require_session(p_token,true);
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.operational_date desc,q.submitted_at desc) from (
   select s.*,a.name staff_name,a.employment_type from public.attendance_staff_submissions s join goya_private.branch_attendance_staff a on a.id=s.attendance_staff_id
   where p_status is null or p_status='' or s.status=p_status
 )q),'[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_review_submission(p_token text, p_id uuid, p_status text, p_admin_note text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.attendance_staff_submissions; a public.attendance_staff; r_id uuid;
begin
 perform public.require_session(p_token,true);
 if p_status not in ('Approved','Rejected') then raise exception 'Invalid review status'; end if;
 select * into s from public.attendance_staff_submissions where id=p_id;
 if s.id is null then raise exception 'Submission not found'; end if;
 if p_status='Approved' then
   select * into a from goya_private.branch_attendance_staff where id=s.attendance_staff_id;
   if s.day_off then
     delete from public.attendance_records where attendance_staff_id=s.attendance_staff_id and operational_date=s.operational_date;
   else
     insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,scheduled_start,expected_presence_minutes,break_minutes)
     values(s.attendance_staff_id,s.operational_date,s.punch_in,s.punch_out,s.break_taken,s.note,'manual',a.default_start_time,a.expected_presence_minutes,a.default_break_minutes)
     on conflict(branch_id,attendance_staff_id,operational_date) do update set punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,note=excluded.note,source='manual',scheduled_start=excluded.scheduled_start,expected_presence_minutes=excluded.expected_presence_minutes,break_minutes=excluded.break_minutes,updated_at=now()
     returning id into r_id;
     perform public.attendance_recalc(r_id);
   end if;
 end if;
 update public.attendance_staff_submissions set status=p_status,admin_note=p_admin_note,reviewed_at=now() where id=p_id;
 return true;
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_save_manual(p_token text, p_staff_id uuid, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_note text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid; s public.attendance_staff;
begin
 perform public.require_session(p_token,true); select * into s from goya_private.branch_attendance_staff where id=p_staff_id;
 insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,scheduled_start,expected_presence_minutes,break_minutes,day_off,split_shift,shift2_in,shift2_out,entry_origin)
 values(p_staff_id,p_operational_date,p_punch_in,p_punch_out,coalesce(p_break_taken,true),p_note,'manual',s.default_start_time,s.expected_presence_minutes,s.default_break_minutes,false,false,null,null,'admin_manual')
 on conflict(branch_id,attendance_staff_id,operational_date) do update set punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,note=excluded.note,source='manual',scheduled_start=excluded.scheduled_start,expected_presence_minutes=excluded.expected_presence_minutes,break_minutes=excluded.break_minutes,day_off=false,split_shift=false,shift2_in=null,shift2_out=null,entry_origin='admin_manual',updated_at=now() returning id into v_id;
 perform public.attendance_recalc(v_id); return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.staff_attendance_submit_v2(p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; v_id uuid;
begin
 sess:=public.require_session(p_token,false);
 select id into a_id from goya_private.branch_attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then insert into public.attendance_staff(portal_staff_id,name,employment_type,active) select id,name,'Full Time',active from public.staff where id=sess.staff_id returning id into a_id; end if;
 delete from public.attendance_staff_submissions where attendance_staff_id=a_id and operational_date=p_operational_date and status='Pending';
 insert into public.attendance_staff_submissions(attendance_staff_id,portal_staff_id,operational_date,punch_in,punch_out,break_taken,day_off,note,status,split_shift,shift2_in,shift2_out)
 values(a_id,sess.staff_id,p_operational_date,case when p_day_off then null else p_punch_in end,case when p_day_off then null else p_punch_out end,coalesce(p_break_taken,true),coalesce(p_day_off,false),p_note,'Pending',case when p_day_off then false else coalesce(p_split_shift,false) end,case when p_day_off then null else p_shift2_in end,case when p_day_off then null else p_shift2_out end) returning id into v_id;
 return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_admin_submissions_v2(p_token text, p_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 perform public.require_session(p_token,true);
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.operational_date desc,q.submitted_at desc) from (
   select s.*,a.name staff_name,a.employment_type,
     r.punch_in device_punch_in,r.punch_out device_punch_out,r.split_shift device_split_shift,r.shift2_in device_shift2_in,r.shift2_out device_shift2_out
   from public.attendance_staff_submissions s join goya_private.branch_attendance_staff a on a.id=s.attendance_staff_id
   left join public.attendance_records r on r.attendance_staff_id=s.attendance_staff_id and r.operational_date=s.operational_date and coalesce(r.entry_origin,'device')='device'
   where p_status is null or p_status='' or s.status=p_status
 )q),'[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_review_submission_v2(p_token text, p_id uuid, p_status text, p_admin_note text, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone, p_note text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.attendance_staff_submissions; a public.attendance_staff; r_id uuid;
begin
 perform public.require_session(p_token,true);
 if p_status not in ('Approved','Rejected') then raise exception 'Invalid review status'; end if;
 select * into s from public.attendance_staff_submissions where id=p_id; if s.id is null then raise exception 'Submission not found'; end if;
 update public.attendance_staff_submissions set punch_in=p_punch_in,punch_out=p_punch_out,break_taken=coalesce(p_break_taken,true),day_off=coalesce(p_day_off,false),split_shift=coalesce(p_split_shift,false),shift2_in=p_shift2_in,shift2_out=p_shift2_out,note=p_note,status=p_status,admin_note=p_admin_note,reviewed_at=now() where id=p_id;
 if p_status='Approved' then
   select * into a from goya_private.branch_attendance_staff where id=s.attendance_staff_id;
   insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,scheduled_start,expected_presence_minutes,break_minutes,day_off,split_shift,shift2_in,shift2_out,entry_origin)
   values(s.attendance_staff_id,s.operational_date,case when p_day_off then null else p_punch_in end,case when p_day_off then null else p_punch_out end,coalesce(p_break_taken,true),p_note,'manual',a.default_start_time,a.expected_presence_minutes,a.default_break_minutes,coalesce(p_day_off,false),case when p_day_off then false else coalesce(p_split_shift,false) end,case when p_day_off then null else p_shift2_in end,case when p_day_off then null else p_shift2_out end,'staff_approved')
   on conflict(branch_id,attendance_staff_id,operational_date) do update set punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,note=excluded.note,source='manual',scheduled_start=excluded.scheduled_start,expected_presence_minutes=excluded.expected_presence_minutes,break_minutes=excluded.break_minutes,day_off=excluded.day_off,split_shift=excluded.split_shift,shift2_in=excluded.shift2_in,shift2_out=excluded.shift2_out,entry_origin='staff_approved',updated_at=now() returning id into r_id;
   perform public.attendance_recalc(r_id);
 end if;
 return true;
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_import_records_v2(p_token text, p_rows jsonb, p_file_name text, p_upload_type text, p_date_from date, p_date_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it jsonb; s_id uuid; r_id uuid; n int:=0; skipped int:=0; code text; nm text;
begin
 perform public.require_session(p_token,true);
 for it in select * from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
   nm:=trim(it->>'name'); code:=nullif(trim(it->>'employee_code'),''); if nm='' or nullif(it->>'operational_date','') is null then continue; end if;
   select id into s_id from goya_private.branch_attendance_staff where (code is not null and employee_code=code) or lower(name)=lower(nm) order by (employee_code=code) desc nulls last limit 1;
   if s_id is null then insert into public.attendance_staff(name,employee_code,employment_type) values(nm,code,'Full Time') returning id into s_id; end if;
   insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,device_file,day_off,split_shift,shift2_in,shift2_out,entry_origin)
   values(s_id,(it->>'operational_date')::date,nullif(it->>'punch_in','')::timestamp,nullif(it->>'punch_out','')::timestamp,coalesce((it->>'break_taken')::boolean,true),nullif(it->>'note',''),'device',p_file_name,false,coalesce((it->>'split_shift')::boolean,false),nullif(it->>'shift2_in','')::timestamp,nullif(it->>'shift2_out','')::timestamp,'device')
   on conflict(branch_id,attendance_staff_id,operational_date) do update set punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,note=coalesce(nullif(excluded.note,''),public.attendance_records.note),device_file=excluded.device_file,day_off=false,split_shift=excluded.split_shift,shift2_in=excluded.shift2_in,shift2_out=excluded.shift2_out,entry_origin='device',source='device',updated_at=now()
   where coalesce(public.attendance_records.entry_origin,'device')='device'
   returning id into r_id;
   if r_id is null then skipped:=skipped+1; else n:=n+1; perform public.attendance_recalc(r_id); end if;
 end loop;
 insert into public.attendance_uploads(file_name,upload_type,date_from,date_to,rows_imported) values(p_file_name,coalesce(p_upload_type,'Daily'),p_date_from,p_date_to,n);
 return jsonb_build_object('imported',n,'manual_preserved',skipped);
end $function$;

CREATE OR REPLACE FUNCTION public.staff_attendance_submit_v10(p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; v_id uuid;
begin
 sess:=public.require_session(p_token,false);
 select id into a_id from goya_private.branch_attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then
   insert into public.attendance_staff(portal_staff_id,name,employment_type,active)
   select id,name,'Full Time',active from public.staff where id=sess.staff_id returning id into a_id;
 end if;
 -- Re-submit replaces only the current not-finalized submission for that staff/date.
 delete from public.attendance_staff_submissions
 where attendance_staff_id=a_id and operational_date=p_operational_date and status in ('Pending','Submitted');
 insert into public.attendance_staff_submissions(attendance_staff_id,portal_staff_id,operational_date,punch_in,punch_out,break_taken,day_off,note,status,split_shift,shift2_in,shift2_out)
 values(a_id,sess.staff_id,p_operational_date,case when p_day_off then null else p_punch_in end,case when p_day_off then null else p_punch_out end,
   coalesce(p_break_taken,true),coalesce(p_day_off,false),p_note,'Submitted',
   case when p_day_off then false else coalesce(p_split_shift,false) end,
   case when p_day_off then null else p_shift2_in end,case when p_day_off then null else p_shift2_out end)
 returning id into v_id;
 return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.staff_attendance_month_v10(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; sd date; ed date;
begin
 sess:=public.require_session(p_token,false);
 select id into a_id from goya_private.branch_attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then return jsonb_build_object('records','[]'::jsonb,'submissions','[]'::jsonb); end if;
 sd:=date_trunc('month',p_month)::date; ed:=(sd+interval '1 month')::date;
 return jsonb_build_object(
   'records',coalesce((select jsonb_agg(to_jsonb(r) order by r.operational_date) from public.attendance_records r where r.attendance_staff_id=a_id and r.operational_date>=sd and r.operational_date<ed),'[]'::jsonb),
   'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.operational_date,s.submitted_at desc) from public.attendance_staff_submissions s where s.attendance_staff_id=a_id and s.operational_date>=sd and s.operational_date<ed),'[]'::jsonb)
 );
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_import_records_v10(p_token text, p_rows jsonb, p_file_name text, p_upload_type text, p_date_from date, p_date_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it jsonb; s_id uuid; r_id uuid; n int:=0; final_updated int:=0; code text; nm text;
begin
 perform public.require_session(p_token,true);
 for it in select * from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
   nm:=trim(it->>'name'); code:=nullif(trim(it->>'employee_code'),'');
   if nm='' or nullif(it->>'operational_date','') is null then continue; end if;
   select id into s_id from goya_private.branch_attendance_staff
   where (code is not null and employee_code=code) or lower(name)=lower(nm)
   order by (employee_code=code) desc nulls last limit 1;
   if s_id is null then insert into public.attendance_staff(name,employee_code,employment_type) values(nm,code,'Full Time') returning id into s_id; end if;

   insert into public.attendance_device_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,split_shift,shift2_in,shift2_out,note,device_file)
   values(s_id,(it->>'operational_date')::date,nullif(it->>'punch_in','')::timestamp,nullif(it->>'punch_out','')::timestamp,
     coalesce((it->>'break_taken')::boolean,true),coalesce((it->>'split_shift')::boolean,false),nullif(it->>'shift2_in','')::timestamp,nullif(it->>'shift2_out','')::timestamp,nullif(it->>'note',''),p_file_name)
   on conflict(branch_id,attendance_staff_id,operational_date) do update set
     punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,split_shift=excluded.split_shift,
     shift2_in=excluded.shift2_in,shift2_out=excluded.shift2_out,note=excluded.note,device_file=excluded.device_file,updated_at=now();
   n:=n+1;

   insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,device_file,day_off,split_shift,shift2_in,shift2_out,entry_origin)
   values(s_id,(it->>'operational_date')::date,nullif(it->>'punch_in','')::timestamp,nullif(it->>'punch_out','')::timestamp,
     coalesce((it->>'break_taken')::boolean,true),nullif(it->>'note',''),'device',p_file_name,false,coalesce((it->>'split_shift')::boolean,false),
     nullif(it->>'shift2_in','')::timestamp,nullif(it->>'shift2_out','')::timestamp,'device')
   on conflict(branch_id,attendance_staff_id,operational_date) do update set
     punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,note=coalesce(nullif(excluded.note,''),public.attendance_records.note),
     device_file=excluded.device_file,day_off=false,split_shift=excluded.split_shift,shift2_in=excluded.shift2_in,shift2_out=excluded.shift2_out,
     entry_origin='device',source='device',updated_at=now()
   where coalesce(public.attendance_records.entry_origin,'device')='device'
   returning id into r_id;
   if r_id is not null then final_updated:=final_updated+1; perform public.attendance_recalc(r_id); end if;
 end loop;
 insert into public.attendance_uploads(file_name,upload_type,date_from,date_to,rows_imported)
 values(p_file_name,coalesce(p_upload_type,'Daily'),p_date_from,p_date_to,n);
 return jsonb_build_object('imported',n,'final_updated',final_updated,'admin_final_preserved',n-final_updated);
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_staff_device_compare_v10(p_token text, p_status text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 perform public.require_session(p_token,true);
 return coalesce((select jsonb_agg(to_jsonb(q) order by q.operational_date desc,q.submitted_at desc) from (
   select s.*,a.name staff_name,a.employment_type,
     d.punch_in device_punch_in,d.punch_out device_punch_out,d.break_taken device_break_taken,d.split_shift device_split_shift,d.shift2_in device_shift2_in,d.shift2_out device_shift2_out,
     f.punch_in final_punch_in,f.punch_out final_punch_out,f.break_taken final_break_taken,f.split_shift final_split_shift,f.shift2_in final_shift2_in,f.shift2_out final_shift2_out,
     f.net_work_minutes final_net_work_minutes,f.additional_minutes final_additional_minutes,f.entry_origin final_origin
   from public.attendance_staff_submissions s
   join goya_private.branch_attendance_staff a on a.id=s.attendance_staff_id
   left join public.attendance_device_records d on d.attendance_staff_id=s.attendance_staff_id and d.operational_date=s.operational_date
   left join public.attendance_records f on f.attendance_staff_id=s.attendance_staff_id and f.operational_date=s.operational_date
   where p_status is null or p_status='' or s.status=p_status
 )q),'[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_save_final_submission_v10(p_token text, p_id uuid, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone, p_note text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.attendance_staff_submissions; a public.attendance_staff; r_id uuid;
begin
 perform public.require_session(p_token,true);
 select * into s from public.attendance_staff_submissions where id=p_id;
 if s.id is null then raise exception 'Submission not found'; end if;
 select * into a from goya_private.branch_attendance_staff where id=s.attendance_staff_id;
 update public.attendance_staff_submissions set punch_in=p_punch_in,punch_out=p_punch_out,break_taken=coalesce(p_break_taken,true),day_off=coalesce(p_day_off,false),
   split_shift=coalesce(p_split_shift,false),shift2_in=p_shift2_in,shift2_out=p_shift2_out,note=p_note,status='Finalized',reviewed_at=now() where id=p_id;
 insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,scheduled_start,expected_presence_minutes,break_minutes,day_off,split_shift,shift2_in,shift2_out,entry_origin)
 values(s.attendance_staff_id,s.operational_date,case when p_day_off then null else p_punch_in end,case when p_day_off then null else p_punch_out end,coalesce(p_break_taken,true),p_note,'manual',
   a.default_start_time,a.expected_presence_minutes,a.default_break_minutes,coalesce(p_day_off,false),case when p_day_off then false else coalesce(p_split_shift,false) end,
   case when p_day_off then null else p_shift2_in end,case when p_day_off then null else p_shift2_out end,'admin_final')
 on conflict(branch_id,attendance_staff_id,operational_date) do update set
   punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,note=excluded.note,source='manual',scheduled_start=excluded.scheduled_start,
   expected_presence_minutes=excluded.expected_presence_minutes,break_minutes=excluded.break_minutes,day_off=excluded.day_off,split_shift=excluded.split_shift,
   shift2_in=excluded.shift2_in,shift2_out=excluded.shift2_out,entry_origin='admin_final',updated_at=now()
 returning id into r_id;
 perform public.attendance_recalc(r_id);
 return true;
end $function$;

CREATE OR REPLACE FUNCTION public.staff_attendance_month_v11(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; sd date; ed date; a public.attendance_staff; rules jsonb;
begin
 sess:=public.require_session(p_token,false);
 select * into a from goya_private.branch_attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a.id is null then return jsonb_build_object('records','[]'::jsonb,'submissions','[]'::jsonb,'staff','{}'::jsonb); end if;
 a_id:=a.id; sd:=date_trunc('month',p_month)::date; ed:=(sd+interval '1 month')::date;
 select coalesce(value,'{}'::jsonb) into rules from public.attendance_settings where key='rules';
 return jsonb_build_object(
   'staff',to_jsonb(a) || jsonb_build_object('late_grace_minutes',coalesce((rules->>'late_grace_minutes')::int,15)),
   'records',coalesce((select jsonb_agg(to_jsonb(r) order by r.operational_date) from public.attendance_records r where r.attendance_staff_id=a_id and r.operational_date>=sd and r.operational_date<ed),'[]'::jsonb),
   'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.operational_date,s.submitted_at desc) from public.attendance_staff_submissions s where s.attendance_staff_id=a_id and s.operational_date>=sd and s.operational_date<ed),'[]'::jsonb)
 );
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_import_records_v11(p_token text, p_rows jsonb, p_file_name text, p_upload_type text, p_date_from date, p_date_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare it jsonb; s_id uuid; r_id uuid; n int:=0; final_updated int:=0; code text; nm text;
begin
 perform public.require_session(p_token,true);
 for it in select * from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
   nm:=trim(it->>'name'); code:=nullif(trim(it->>'employee_code'),'');
   if nm='' or lower(nm)='goya lounge' or nullif(it->>'operational_date','') is null then continue; end if;
   s_id:=null;
   select id into s_id from goya_private.branch_attendance_staff where lower(trim(name))=lower(trim(nm)) order by active desc,updated_at desc limit 1;
   if s_id is null then insert into public.attendance_staff(name,employee_code,employment_type) values(nm,code,'Full Time') returning id into s_id; end if;

   insert into public.attendance_device_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,split_shift,shift2_in,shift2_out,note,device_file)
   values(s_id,(it->>'operational_date')::date,nullif(it->>'punch_in','')::timestamp,nullif(it->>'punch_out','')::timestamp,
     coalesce((it->>'break_taken')::boolean,true),coalesce((it->>'split_shift')::boolean,false),nullif(it->>'shift2_in','')::timestamp,nullif(it->>'shift2_out','')::timestamp,nullif(it->>'note',''),p_file_name)
   on conflict(branch_id,attendance_staff_id,operational_date) do update set
     punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,split_shift=excluded.split_shift,
     shift2_in=excluded.shift2_in,shift2_out=excluded.shift2_out,note=excluded.note,device_file=excluded.device_file,updated_at=now();
   n:=n+1;

   insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,device_file,day_off,split_shift,shift2_in,shift2_out,entry_origin)
   values(s_id,(it->>'operational_date')::date,nullif(it->>'punch_in','')::timestamp,nullif(it->>'punch_out','')::timestamp,
     coalesce((it->>'break_taken')::boolean,true),nullif(it->>'note',''),'device',p_file_name,false,coalesce((it->>'split_shift')::boolean,false),
     nullif(it->>'shift2_in','')::timestamp,nullif(it->>'shift2_out','')::timestamp,'device')
   on conflict(branch_id,attendance_staff_id,operational_date) do update set
     punch_in=excluded.punch_in,punch_out=excluded.punch_out,break_taken=excluded.break_taken,note=coalesce(nullif(excluded.note,''),public.attendance_records.note),
     device_file=excluded.device_file,day_off=false,split_shift=excluded.split_shift,shift2_in=excluded.shift2_in,shift2_out=excluded.shift2_out,
     entry_origin='device',source='device',updated_at=now()
   where coalesce(public.attendance_records.entry_origin,'device')='device'
   returning id into r_id;
   if r_id is not null then final_updated:=final_updated+1; perform public.attendance_recalc(r_id); end if;
 end loop;
 insert into public.attendance_uploads(file_name,upload_type,date_from,date_to,rows_imported)
 values(p_file_name,coalesce(p_upload_type,'Daily'),p_date_from,p_date_to,n);
 return jsonb_build_object('imported',n,'final_updated',final_updated,'admin_final_preserved',n-final_updated);
end $function$;

CREATE OR REPLACE FUNCTION public.staff_attendance_submit_v12(p_token text, p_operational_date date, p_punch_in timestamp without time zone, p_punch_out timestamp without time zone, p_break_taken boolean, p_day_off boolean, p_note text, p_split_shift boolean, p_shift2_in timestamp without time zone, p_shift2_out timestamp without time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; v_id uuid; cur_month date;
begin
 sess:=public.require_session(p_token,false);
 cur_month:=date_trunc('month',(now() at time zone 'Asia/Dubai')::date)::date;
 if date_trunc('month',p_operational_date)::date<>cur_month then
   raise exception 'Previous month attendance is locked for staff editing.';
 end if;
 select id into a_id from goya_private.branch_attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a_id is null then
   insert into public.attendance_staff(portal_staff_id,name,employment_type,active)
   select id,name,'Full Time',active from public.staff where id=sess.staff_id returning id into a_id;
 end if;
 delete from public.attendance_staff_submissions
 where attendance_staff_id=a_id and operational_date=p_operational_date and status in ('Pending','Submitted');
 insert into public.attendance_staff_submissions(attendance_staff_id,portal_staff_id,operational_date,punch_in,punch_out,break_taken,day_off,note,status,split_shift,shift2_in,shift2_out)
 values(a_id,sess.staff_id,p_operational_date,case when p_day_off then null else p_punch_in end,case when p_day_off then null else p_punch_out end,
   coalesce(p_break_taken,true),coalesce(p_day_off,false),p_note,'Submitted',case when p_day_off then false else coalesce(p_split_shift,false) end,
   case when p_day_off then null else p_shift2_in end,case when p_day_off then null else p_shift2_out end)
 returning id into v_id;
 return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_recalc(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r public.attendance_records;
  s public.attendance_staff;
  rules jsonb;
  shifts jsonb;
  sh text;
  grace int:=15;
  punch_min int;
  sh_min int;
  best_min int:=null;
  best_dist int:=null;
  dist int;
  calculated_late int:=0;
  st timestamp;
  effective_in timestamp;
  out1 timestamp;
  out2 timestamp;
  presence1 int:=0;
  presence2 int:=0;
  total_presence int:=0;
  netv int:=0;
  exp_net int:=0;
  cutoff_min int:=120;
begin
  select * into r from public.attendance_records where id=p_id;
  if r.id is null then return; end if;
  select * into s from goya_private.branch_attendance_staff where id=r.attendance_staff_id;
  select coalesce(value,'{}'::jsonb) into rules from public.attendance_settings where key='rules';

  grace:=coalesce((rules->>'late_grace_minutes')::int,15);
  cutoff_min:=coalesce(
    split_part(coalesce(rules->>'operational_cutoff','02:00'),':',1)::int*60 +
    split_part(coalesce(rules->>'operational_cutoff','02:00'),':',2)::int,
    120
  );
  r.expected_presence_minutes:=coalesce(r.expected_presence_minutes,s.expected_presence_minutes,(rules->>'default_presence_minutes')::int,540);
  r.break_minutes:=coalesce(r.break_minutes,s.default_break_minutes,(rules->>'default_break_minutes')::int,60);
  shifts:=coalesce(rules->'shift_start_times',jsonb_build_array('08:00','09:00','10:00','11:00','12:00','13:00','14:00','15:00','16:00','17:00'));

  if r.punch_in is not null then
    punch_min:=extract(hour from r.punch_in)::int*60 + extract(minute from r.punch_in)::int;
    for sh in select jsonb_array_elements_text(shifts) loop
      begin
        sh_min:=split_part(sh,':',1)::int*60 + split_part(sh,':',2)::int;
        dist:=abs(punch_min-sh_min);
        if best_dist is null or dist<best_dist or (dist=best_dist and sh_min>best_min) then
          best_dist:=dist;
          best_min:=sh_min;
        end if;
      exception when others then null;
      end;
    end loop;

    if best_min is not null then
      st:=r.operational_date::timestamp + make_interval(mins=>best_min);
      r.scheduled_start:=st::time;
      if punch_min-best_min>grace then calculated_late:=punch_min-best_min; end if;
    end if;
  end if;

  effective_in:=r.punch_in;
  if effective_in is not null and st is not null and effective_in<st then effective_in:=st; end if;

  out1:=r.punch_out;
  if effective_in is not null and out1 is not null and out1<=effective_in then
    -- Safe legacy/manual overnight correction only when OUT clock is inside the next-day cutoff window.
    if (extract(hour from out1)::int*60 + extract(minute from out1)::int)<=cutoff_min then
      out1:=out1+interval '1 day';
    end if;
  end if;
  if effective_in is not null and out1 is not null then
    presence1:=greatest(0,floor(extract(epoch from (out1-effective_in))/60)::int);
  end if;

  if coalesce(r.split_shift,false) and r.shift2_in is not null and r.shift2_out is not null then
    out2:=r.shift2_out;
    if out2<=r.shift2_in and (extract(hour from out2)::int*60 + extract(minute from out2)::int)<=cutoff_min then
      out2:=out2+interval '1 day';
    end if;
    presence2:=greatest(0,floor(extract(epoch from (out2-r.shift2_in))/60)::int);
  end if;

  total_presence:=presence1+presence2;
  netv:=greatest(0,total_presence-case when r.break_taken then r.break_minutes else 0 end);
  exp_net:=greatest(0,r.expected_presence_minutes-r.break_minutes);

  update public.attendance_records set
    scheduled_start=r.scheduled_start,
    expected_presence_minutes=r.expected_presence_minutes,
    break_minutes=r.break_minutes,
    late_minutes=calculated_late,
    presence_minutes=total_presence,
    net_work_minutes=netv,
    additional_minutes=greatest(0,netv-exp_net),
    updated_at=now()
  where id=p_id;
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_legacy_admin_history(p_token text, p_start date, p_end date, p_staff_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.require_session(p_token,true);
  if p_start is null or p_end is null or p_end < p_start then
    raise exception 'Invalid date range';
  end if;

  return jsonb_build_object(
    'rows', coalesce((
      with candidates as (
        select a.id attendance_staff_id, a.portal_staff_id staff_id, s.name staff_name, r.operational_date
          from goya_private.branch_attendance_staff a
          join public.staff s on s.id=a.portal_staff_id
          join public.attendance_records r on r.attendance_staff_id=a.id
         where r.operational_date between p_start and p_end
           and (p_staff_id is null or a.portal_staff_id=p_staff_id)
        union
        select a.id, a.portal_staff_id, s.name, x.operational_date
          from goya_private.branch_attendance_staff a
          join public.staff s on s.id=a.portal_staff_id
          join public.attendance_staff_submissions x on x.attendance_staff_id=a.id
         where x.operational_date between p_start and p_end
           and (p_staff_id is null or a.portal_staff_id=p_staff_id)
      )
      select jsonb_agg(jsonb_build_object(
        'staff_id',c.staff_id,
        'staff_name',c.staff_name,'staff_active',(select st.active from public.staff st where st.id=c.staff_id),'employment_note',goya_private.employment_note(c.staff_id,c.operational_date),
        'operational_date',c.operational_date,
        'record',(select to_jsonb(r) from public.attendance_records r
                  where r.attendance_staff_id=c.attendance_staff_id and r.operational_date=c.operational_date
                  limit 1),
        'submission',(select to_jsonb(x) from public.attendance_staff_submissions x
                      where x.attendance_staff_id=c.attendance_staff_id and x.operational_date=c.operational_date
                      order by x.submitted_at desc nulls last limit 1)
      ) order by c.operational_date desc,c.staff_name)
      from candidates c where goya_private.employed_on(c.staff_id,c.operational_date)
    ),'[]'::jsonb)
  );
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_live_admin_set_break(p_token text, p_staff_id uuid, p_date date, p_break_taken boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  beforev jsonb; afterv jsonb; a_id uuid; r_id uuid;
begin
  perform public.require_session(p_token,true);
  if p_staff_id is null or p_date is null then raise exception 'Staff and date are required'; end if;

  if exists(select 1 from public.attendance_live_days where staff_id=p_staff_id and operational_date=p_date)
     or exists(select 1 from public.attendance_live_sessions where staff_id=p_staff_id and operational_date=p_date and coalesce(is_deleted,false)=false) then
    select to_jsonb(d) into beforev from public.attendance_live_days d where d.staff_id=p_staff_id and d.operational_date=p_date;
    insert into public.attendance_live_days(staff_id,operational_date,break_taken,classification,is_deleted)
    values(p_staff_id,p_date,coalesce(p_break_taken,true),'Duty',false)
    on conflict(branch_id,staff_id,operational_date) do update set break_taken=excluded.break_taken,updated_at=now(),is_deleted=false,deleted_at=null,deleted_reason=null
    returning to_jsonb(attendance_live_days.*) into afterv;
    perform public.attendance_live_recalculate_day_internal(p_staff_id,p_date);
    select to_jsonb(d) into afterv from public.attendance_live_days d where d.staff_id=p_staff_id and d.operational_date=p_date;
  else
    select id into a_id from goya_private.branch_attendance_staff where portal_staff_id=p_staff_id order by active desc,updated_at desc limit 1;
    if a_id is null then raise exception 'Attendance staff mapping not found'; end if;
    select id,to_jsonb(r) into r_id,beforev from public.attendance_records r where r.attendance_staff_id=a_id and r.operational_date=p_date limit 1;
    if r_id is null then raise exception 'Previous attendance record not found'; end if;
    update public.attendance_records set break_taken=coalesce(p_break_taken,true),updated_at=now() where id=r_id;
    perform public.attendance_recalc(r_id);
    select to_jsonb(r) into afterv from public.attendance_records r where r.id=r_id;
  end if;

  insert into public.attendance_live_audit(staff_id,operational_date,actor_type,action,before_data,after_data)
  values(p_staff_id,p_date,'admin','EDIT_BREAK',beforev,afterv);
  return jsonb_build_object('ok',true,'staff_id',p_staff_id,'operational_date',p_date,'break_taken',coalesce(p_break_taken,true));
end $function$;

CREATE OR REPLACE FUNCTION public.attendance_live_admin_update_previous_record(p_token text, p_staff_id uuid, p_date date, p_punch_in timestamp with time zone, p_punch_out timestamp with time zone, p_break_taken boolean, p_split_shift boolean, p_shift2_in timestamp with time zone, p_shift2_out timestamp with time zone, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  a_id uuid; r_id uuid; beforev jsonb; afterv jsonb;
  pin timestamp; pout timestamp; s2in timestamp; s2out timestamp;
begin
  perform public.require_session(p_token,true);
  select id into a_id from goya_private.branch_attendance_staff where portal_staff_id=p_staff_id order by active desc,updated_at desc limit 1;
  if a_id is null then raise exception 'Attendance staff mapping not found'; end if;
  if p_punch_in is null then raise exception 'Check In is required'; end if;
  pin:=p_punch_in at time zone 'Asia/Dubai';
  pout:=case when p_punch_out is null then null else p_punch_out at time zone 'Asia/Dubai' end;
  s2in:=case when p_shift2_in is null then null else p_shift2_in at time zone 'Asia/Dubai' end;
  s2out:=case when p_shift2_out is null then null else p_shift2_out at time zone 'Asia/Dubai' end;
  if pout is not null and pout<=pin then raise exception 'Check Out must be after Check In'; end if;
  if coalesce(p_split_shift,false) and (s2in is null or s2out is null or s2out<=s2in) then raise exception 'Valid Session 2 In/Out is required'; end if;

  select id,to_jsonb(r) into r_id,beforev from public.attendance_records r where r.attendance_staff_id=a_id and r.operational_date=p_date limit 1;
  if r_id is null then
    insert into public.attendance_records(attendance_staff_id,operational_date,punch_in,punch_out,break_taken,note,source,day_off,split_shift,shift2_in,shift2_out,entry_origin)
    values(a_id,p_date,pin,pout,coalesce(p_break_taken,true),nullif(trim(coalesce(p_note,'')),''),'manual',false,coalesce(p_split_shift,false),s2in,s2out,'admin_manual') returning id into r_id;
  else
    update public.attendance_records set punch_in=pin,punch_out=pout,break_taken=coalesce(p_break_taken,true),note=coalesce(nullif(trim(coalesce(p_note,'')),''),note),source='manual',day_off=false,split_shift=coalesce(p_split_shift,false),shift2_in=case when coalesce(p_split_shift,false) then s2in else null end,shift2_out=case when coalesce(p_split_shift,false) then s2out else null end,entry_origin='admin_manual',updated_at=now() where id=r_id;
  end if;
  perform public.attendance_recalc(r_id);
  select to_jsonb(r) into afterv from public.attendance_records r where r.id=r_id;
  insert into public.attendance_live_audit(staff_id,operational_date,actor_type,action,before_data,after_data)
  values(p_staff_id,p_date,'admin','EDIT_PREVIOUS_RECORD',beforev,afterv);
  return jsonb_build_object('ok',true,'record',afterv);
end $function$;

CREATE OR REPLACE FUNCTION public.staff_attendance_month_v12(p_token text, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sess public.app_sessions; a_id uuid; sd date; ed date; a public.attendance_staff; rules jsonb;
begin
 sess:=public.require_session(p_token,false);
 select * into a from goya_private.branch_attendance_staff where portal_staff_id=sess.staff_id limit 1;
 if a.id is null then return jsonb_build_object('records','[]'::jsonb,'submissions','[]'::jsonb,'staff','{}'::jsonb); end if;
 a_id:=a.id; sd:=date_trunc('month',p_month)::date; ed:=(sd+interval '1 month')::date;
 select coalesce(value,'{}'::jsonb) into rules from public.attendance_settings where key='rules';
 return jsonb_build_object(
   'staff',to_jsonb(a) || jsonb_build_object(
      'late_grace_minutes',coalesce((rules->>'late_grace_minutes')::int,15),
      'shift_start_times',coalesce(rules->'shift_start_times',jsonb_build_array(coalesce(rules->>'operational_start','08:00')))
   ),
   'records',coalesce((select jsonb_agg(to_jsonb(r) order by r.operational_date) from public.attendance_records r where goya_private.employed_on(sess.staff_id,r.operational_date) and r.attendance_staff_id=a_id and r.operational_date>=sd and r.operational_date<ed),'[]'::jsonb),
   'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.operational_date,s.submitted_at desc) from public.attendance_staff_submissions s where goya_private.employed_on(sess.staff_id,s.operational_date) and s.attendance_staff_id=a_id and s.operational_date>=sd and s.operational_date<ed),'[]'::jsonb)
 );
end $function$;
create function goya_private.assign_operation_staff() returns trigger language plpgsql security definer set search_path='' as $$begin insert into goya_private.branch_members(branch_id,staff_id) values(goya_private.current_branch(),new.id) on conflict do nothing;return new;end$$;
create trigger assign_operation_staff after insert on public.staff for each row execute function goya_private.assign_operation_staff();
CREATE OR REPLACE FUNCTION goya_private.staff_notice_emit(employee uuid, event_key text, kind text, title text, body text, target jsonb, at_time timestamp with time zone DEFAULT clock_timestamp())
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 insert into goya_private.staff_notifications(staff_id,event_key,kind,title,body,target,created_at)
 select employee,case when kind in ('roster','attendance','reminder') then goya_private.current_branch()::text||':' else '' end||event_key,kind,left(title,250),left(case when kind in ('roster','attendance','reminder') then coalesce((select name from goya_private.branches where id=goya_private.current_branch()),'GOYA')||E'\n' else '' end||body,4000),target||case when kind in ('roster','attendance','reminder') then jsonb_build_object('branch_id',goya_private.current_branch()) else '{}'::jsonb end,at_time
 where exists(select 1 from public.staff where id=employee)
 and not exists(select 1 from goya_private.staff_notifications n where n.staff_id=$1 and n.event_key=case when $3 in ('roster','attendance','reminder') then goya_private.current_branch()::text||':' else '' end||$2)
 on conflict(staff_id,event_key) do nothing;
$function$
;
CREATE OR REPLACE FUNCTION goya_private.staff_notice_emit(employee uuid, event_key text, kind text, title text, body text, target jsonb, at_time timestamp with time zone DEFAULT clock_timestamp())
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 insert into goya_private.staff_notifications(staff_id,event_key,kind,title,body,target,created_at)
 select employee,case when kind in ('roster','attendance','reminder') and goya_private.current_branch()<>'00000000-0000-0000-0000-000000000001' then goya_private.current_branch()::text||':' else '' end||event_key,kind,left(title,250),left(case when kind in ('roster','attendance','reminder') then coalesce((select name from goya_private.branches where id=goya_private.current_branch()),'GOYA')||E'\n' else '' end||body,4000),target||case when kind in ('roster','attendance','reminder') then jsonb_build_object('branch_id',goya_private.current_branch()) else '{}'::jsonb end,at_time
 where exists(select 1 from public.staff where id=employee)
 and not exists(select 1 from goya_private.staff_notifications n where n.staff_id=$1 and n.event_key=case when $3 in ('roster','attendance','reminder') and goya_private.current_branch()<>'00000000-0000-0000-0000-000000000001' then goya_private.current_branch()::text||':' else '' end||$2)
 on conflict(staff_id,event_key) do nothing;
$function$
;
create or replace function goya_private.staff_notice_reminders() returns void language plpgsql security definer set search_path='' as $$declare employee uuid;b uuid;begin for b in select id from goya_private.branches loop perform set_config('goya.branch_id',b::text,true);for employee in select id from goya_private.branch_staff where active order by id loop perform goya_private.staff_notice_refresh(employee);end loop;end loop;end$$;
insert into goya_private.branch_rpc_registry values('goya_push_check','p_id uuid, p_date date','[{"name":"p_id","type":"uuid"},{"name":"p_date","type":"date"}]'::jsonb,false) on conflict do nothing;
insert into goya_private.branch_rpc_registry values('goya_push_claim','','[]'::jsonb,false) on conflict do nothing;
insert into goya_private.branch_rpc_registry values('goya_push_result','p_id uuid, p_date date, p_ok boolean, p_expired boolean','[{"name":"p_id","type":"uuid"},{"name":"p_date","type":"date"},{"name":"p_ok","type":"boolean"},{"name":"p_expired","type":"boolean"}]'::jsonb,false) on conflict do nothing;
insert into goya_private.branch_rpc_registry values('goya_notice_push_claim','','[]'::jsonb,false) on conflict do nothing;
insert into goya_private.branch_rpc_registry values('goya_notice_push_check','p_notice uuid, p_subscription uuid','[{"name":"p_notice","type":"uuid"},{"name":"p_subscription","type":"uuid"}]'::jsonb,false) on conflict do nothing;
insert into goya_private.branch_rpc_registry values('goya_notice_push_result','p_notice uuid, p_subscription uuid, p_ok boolean, p_expired boolean','[{"name":"p_notice","type":"uuid"},{"name":"p_subscription","type":"uuid"},{"name":"p_ok","type":"boolean"},{"name":"p_expired","type":"boolean"}]'::jsonb,false) on conflict do nothing;
insert into goya_private.branch_rpc_registry values('goya_roster_push_claim','','[]'::jsonb,false) on conflict do nothing;
insert into goya_private.branch_rpc_registry values('goya_roster_push_check','p_week date, p_revision integer, p_subscription uuid','[{"name":"p_week","type":"date"},{"name":"p_revision","type":"integer"},{"name":"p_subscription","type":"uuid"}]'::jsonb,false) on conflict do nothing;
insert into goya_private.branch_rpc_registry values('goya_roster_push_result','p_week date, p_revision integer, p_subscription uuid, p_sent boolean, p_expired boolean','[{"name":"p_week","type":"date"},{"name":"p_revision","type":"integer"},{"name":"p_subscription","type":"uuid"},{"name":"p_sent","type":"boolean"},{"name":"p_expired","type":"boolean"}]'::jsonb,false) on conflict do nothing;
insert into goya_private.branch_rpc_registry values('goya_admin_push_claim','','[]'::jsonb,false) on conflict do nothing;
insert into goya_private.branch_rpc_registry values('goya_admin_push_check','p_notification bigint, p_device uuid','[{"name":"p_notification","type":"bigint"},{"name":"p_device","type":"uuid"}]'::jsonb,false) on conflict do nothing;
insert into goya_private.branch_rpc_registry values('goya_admin_push_result','p_notification bigint, p_device uuid, p_ok boolean, p_expired boolean','[{"name":"p_notification","type":"bigint"},{"name":"p_device","type":"uuid"},{"name":"p_ok","type":"boolean"},{"name":"p_expired","type":"boolean"}]'::jsonb,false) on conflict do nothing;
create function public.goya_branch_worker_call(p_branch uuid,p_operation text,p_args jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare reg record;arg jsonb;pieces text[]:='{}';result jsonb;begin
 if p_operation !~ '^goya_(push|notice_push|roster_push|admin_push)_(claim|check|result)$' or not exists(select 1 from goya_private.branches where id=p_branch) then raise exception 'Unsupported worker request';end if;
 select * into strict reg from goya_private.branch_rpc_registry where name=p_operation;
 for arg in select value from jsonb_array_elements(reg.args) loop if p_args ? (arg->>'name') then pieces:=array_append(pieces,format('%I := ($1->>%L)::%s',arg->>'name',arg->>'name',arg->>'type'));end if;end loop;
 perform set_config('goya.branch_id',p_branch::text,true);execute format('select to_jsonb(public.%I(%s))',p_operation,array_to_string(pieces,',')) into result using p_args;return result;end$$;
create function public.goya_branches_worker_claim(p_operation text) returns jsonb language plpgsql security definer set search_path='' as $$declare b record;items jsonb;result jsonb:='[]';begin
 if p_operation not in('goya_push_claim','goya_notice_push_claim','goya_roster_push_claim','goya_admin_push_claim') then raise exception 'Unsupported worker request';end if;
 for b in select id,name from goya_private.branches loop items:=public.goya_branch_worker_call(b.id,p_operation);select result||coalesce(jsonb_agg(value||jsonb_build_object('branch_id',b.id,'branch_name',b.name)),'[]') into result from jsonb_array_elements(coalesce(items,'[]'));end loop;return result;end$$;
revoke all on function public.goya_branch_worker_call(uuid,text,jsonb),public.goya_branches_worker_claim(text) from public,anon,authenticated;
grant execute on function public.goya_branch_worker_call(uuid,text,jsonb),public.goya_branches_worker_claim(text) to service_role;
alter function goya_private.run_duty_reminders() owner to postgres;
alter function goya_private.run_roster_notifications() owner to postgres;
alter function goya_private.run_admin_notifications() owner to postgres;
do $$declare b uuid;begin insert into goya_private.branches(name,kind) values('Goya-Event','event') returning id into b;
insert into goya_private.branch_members(branch_id,staff_id) select b,id from public.staff where active;
insert into public.attendance_settings(key,value,branch_id) select key,case when key='live_rules' then value||jsonb_build_object('locations','[]'::jsonb,'approved_public_ips','[]'::jsonb) else value end,b from public.attendance_settings where branch_id='00000000-0000-0000-0000-000000000001' and key<>'management_share';
insert into public.settings(key,value,branch_id) select key,value,b from public.settings where branch_id='00000000-0000-0000-0000-000000000001';end$$;
revoke create on schema public,goya_private from goya_operations;
notify pgrst,'reload schema';
commit;
