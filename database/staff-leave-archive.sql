begin;

alter table goya_private.staff_leave_requests
  drop constraint staff_leave_requests_check1,
  drop constraint staff_leave_requests_kind_check,
  drop constraint staff_leave_requests_state_check,
  add constraint staff_leave_requests_check1 check (
    state <> 'Approved' or (
      approved_from is not null and approved_to is not null and approved_to between approved_from and approved_from + 365
      and ((payroll is not null and payroll in ('Paid','Unpaid'))
        or (payroll is null and kind='Annual Leave' and email_state='Imported'))
    )),
  add constraint staff_leave_requests_kind_check check (
    (kind in ('Annual Leave','Sick Leave','Other Leave') and state <> 'Recorded')
    or (kind in ('Emergency Leave','Cancelled Off','Attendance Note') and state='Recorded' and email_state='Imported')
  ),
  add constraint staff_leave_requests_state_check check (
    state in ('Pending','Approved','Declined','Withdrawn','Recorded')
  );

commit;
