# GOYA attendance and HR release

Review the branch using sample data. Before production, test the two SQL
scripts in a separate database with the same staff and session schema as
the live portal. Apply `staff-hr.sql` before `weekly-roster.sql`.

Before the live release, verify a recoverable Supabase database backup and
record the currently deployed Git commit. Keep any separate storage backup
private. Check that representative existing records can be read before and
after release, including staff, punches, roster history, orders, inventory,
and saved reports. Compare fixed historical periods so new live activity
does not appear to be a migration difference. Run the portal upload,
email and opted-in device delivery tests in the separate environment
before deploying to staff.

Configure the new `staff-leave` function for the existing GOYA custom
sessions by deploying it with JWT verification disabled at the gateway.
The function checks the GOYA session with the database before accepting
any upload. The origin must match the portal's origin exactly.

Configure the following on the server:

- `GOYA_PORTAL_ORIGIN` and `GOYA_LEAVE_ADMIN_URL`
- `GOYA_LEAVE_DRIVE_ACCOUNT`, `GOYA_LEAVE_DRIVE_FOLDER_ID`, `GOYA_DRIVE_CLIENT_ID`,
  `GOYA_DRIVE_CLIENT_SECRET`, and `GOYA_DRIVE_REFRESH_TOKEN`
- `GOYA_LEAVE_RESEND_KEY` and `GOYA_LEAVE_FROM_EMAIL`

Set the account to `mehedi.src@gmail.com` and the folder ID to the owner's
private `database` folder. The upload function verifies the account and
folder name before creating folders by leave start year, month, and type.
Use a private Drive folder that the connected Google account can write
to and authorized reviewers can open. Using Google Drive's limited
`drive.file` scope requires giving the OAuth application access to the
specific destination folder. Leave attachments are written only to
Drive. SQL receives attachment IDs and upload fingerprints.

The manager's email is read from the existing Admin Panel settings.
Enter the owner and HR email addresses under Attendance Settings → Leave
notification emails. Only an Attendance Admin can read or edit the setting.
Verify with sample attachments and test recipients. Annual requests go to
the saved owner and HR addresses with the manager copied. Other requests go
to the manager. The portal saves requests before attempting email. A failed
mail request leaves the submission visible in Staff Requests.

The old roster archive retains both versions of repeated source weeks.
Review name matches before importing. Rows without a staff match are
admin-only. The archive keeps the original shift text, pending PH/PO
and remarks, with no automatic attendance or payroll backfill. Publish
rosters in the Weekly Roster screen to notify staff in their portal.

For device notifications, test `roster-push.sql` after `weekly-roster.sql`
and deploy the separate `roster-notifications` worker with gateway JWT
verification disabled. Schedule authenticated POSTs using the existing
push worker token in the `x-goya-worker` header, without changing the
duty-reminder job. Recipients are active, opted-in staff with entries
in the current published revision. Stop the separate scheduled job if
device delivery needs to be rolled back.

To roll back the site, redeploy the previous known-good commit and
disable the new `staff-leave` function. Leave the added SQL tables in
place to preserve HR records and roster history. If the rollback also
needs to restore legacy editing behavior, a database administrator can
disable the `prevent_resigned_staff_activation` trigger on
`public.staff` while retaining all recorded employment statuses.
Keep private Drive documents in their folder. Existing attendance
sessions and historical reports can still be accessed in the previous
site version.
