# Admin release 49

Items and Suppliers are separate existing views in `admin.html`. IDs and all existing CRUD/import handlers remain intact; supplier links and source tables are untouched.

Staff: Equipment / Breakage sits directly below Wastage. Staff type an arbitrary equipment/item name, optional quantity, description, incident date and own section. No item catalog, stock deduction, photos or ingredient wastage is involved. Review precedes Submit. Staff see only their own reports, by incident month, 30 per page.

Admin: Equipment / Breakage sits below Production & Wastage. Monthly report cards show submitting staff and incident details. Admin can set Pending / Reviewed / Repaired / Replaced / Closed with a note. Status updates use a version conflict guard and retain a private audit history. No delete endpoint is provided. Reports survive month changes and staff deletion (staff name is snapshotted).

Main Admin bell only: new Orders, Production, Wastage, Complaint/Feedback, legacy Inventory final, shared Inventory final, Equipment submissions. No new mobile push, Staff bell, Attendance Admin, Goya Live, app/APK or attendance event notifications. Existing important-notice push is unchanged. Anonymous feedback stays anonymous in bell and detail responses.

Notification pointers are grouped/deduplicated by submission and stored transactionally by insert statement triggers. Existing submission RPC definitions are unchanged. Auto Draft writes and status changes do not notify. Trigger setup does not backfill old submissions. Shared final retries do not duplicate alerts; a new final generation after reopening has its own alert. Only notification pointers older than 90 days are removed on the next submission; all source reports remain. Detail is fetched from its source, 30 rows per page. Shared final detail uses its existing immutable snapshot. If the admin deletes an original source record through its existing controls, its notification can show that the source is unavailable.

Bell count refreshes at login and roughly every 90 seconds while the Admin page is visible. Opening the bell refreshes immediately. No Realtime subscriptions or additional cron/Edge Functions. Read state is shared across main Admin sessions. Mark-all-read uses the last loaded ID, preserving newer arrivals.

Security: three private RLS tables, no anon/authenticated table access. Seven RPCs explicitly granted to the client roles; every call validates the existing custom PIN session, with admin-only authorization for notifications and reviews. Equipment staff calls additionally validate active staff and assigned section. No service key added. The seven SECURITY DEFINER API advisor entries and three deny-by-default RLS info entries are intentional for this existing architecture; no new search-path warning. The private trigger function is not client executable.

Equipment retry uses a stable UUID request ID and server uniqueness guard. An uncertain response keeps the reviewed payload in the current page for retry. It is not an offline draft system: keep the page open until submission is confirmed. Date defaults and limits use Asia/Dubai. New network calls have a 20-second timeout, stale-session guards, retry messages and loading cleanup.

Validation:

- `node tests/admin-records-db.cjs` (PGlite dependency path via GOYA_PGLITE_PATH): all seven event types, grouped deduplication, idempotent equipment retry, staff isolation/admin denial, anonymous feedback, both pagination paths, review conflict guard, read-all race, notification-only retention.
- `CHROMIUM_EXECUTABLE_PATH=/tmp/chromium node tests/admin-records-ui.cjs`: actual app login and navigation with PGlite RPC bridge; lost-response and double-click retry, escaped text, split views, admin status reflected to staff, failed notification load/retry, light/dark widths 360/390/768/1440 and loader cleanup. Screenshots inspected; mobile welcome heading has room to wrap without letter-by-letter layout.
- Existing admin-login, staff-login, remembered-login, pagination and shared-inventory-ui checks passed.
- `tests/admin-records-live.sql`: real PostgreSQL submission APIs with disposable synthetic staff/session/catalog/count fixtures, inside BEGIN/ROLLBACK. All passed and no fixtures retained. No real PIN/session was read or used.
- Before/after counts and full-row fingerprints matched for 14 existing tables: master/internal items, suppliers, staff, orders/groups, production, wastage, inventory counts/sessions, feedback, live attendance days/sessions and legacy staff attendance submissions.

Deployment: apply additive `admin_submission_notifications_and_equipment_records` migration, then publish the selected frontend files. Rollback frontend by reverting the release commit; keep the additive tables so new equipment reports are not lost. If rolling back server integration, remove only the seven `goya_admin_*` insert triggers, retaining new tables and reports. Do not run DROP TABLE or roll back business data.

Physical phone testing was not performed; browser viewport checks passed. No claim of absolute bug-free behavior is made.
