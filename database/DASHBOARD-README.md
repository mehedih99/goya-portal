# Staff Dashboard release

## Runtime

Staff login opens My Dashboard. Dashboard loading is asynchronous and does not block the existing navigation. A refresh failure leaves the rest of the portal accessible. No demo records are shipped.

- Attendance and monthly totals are scoped to the authenticated staff session. Live and legacy attendance are merged without duplicate dates.
- Team Order counts deliberately follow the existing shared `staff_history` visibility. Pending and Ordered cards include all dates and open matching History. Other status cards return to monthly history.
- Notice Board uses private `goya_private.notices` storage, with custom-session-authorized admin RPCs. Admin Panel → Notice Board publishes/unpublishes notices. Expiry is entered in UAE time. Content is rendered as text. No notices have been prepublished.
- Admin Attendance Settings → Force no break sets an 8-hour target for active staff. It does not rewrite historical attendance. A trigger enforces the policy on current/future day writes. This differs from merely hiding the break selection controls.

## Push reminders

Staff must opt in with Enable reminders on each device. iPhone requires a supported iOS version and a Home Screen web app. The worker checks accumulated session time every minute and sends during the 15-minute window before 8 hours without a break or 9 hours with a break. Pauses between sessions are excluded. Checked-out, inactive staff and expired operational days are excluded. Each subscription/day is claimed once, with bounded retries for failed attempts. A last-minute server recheck reduces the checkout/send race. Delivery cannot be guaranteed to the second; browser, network and OS restrictions apply. Push uses a 60-second TTL and a per-day notification tag. A reminder never checks anyone out.

Subscriptions are private. Logging out unsubscribes the browser; signing in as a different staff member on the same browser deactivates the prior account's endpoint until the new user explicitly opts in. Service worker notification clicks only open the Staff Portal.

`duty-reminders` is an Edge Function with its own random worker-token authentication. Only service_role RPCs can read private VAPID configuration or claim/result jobs. No service-role key, worker token or private VAPID key is stored in Git. Existing public PIN/session auth is retained; replacing the app's auth model is outside this release.

Production key material was generated once and provisioned into `goya_private.push_config`; preserve it when redeploying. Re-running the creation migration is not a key rotation process. Initial provisioning of another environment must generate its own P-256 VAPID keypair and random worker token outside the repo, then insert them using a trusted database connection.

Cron job `goya-duty-reminders` calls `goya_private.run_duty_reminders()` every minute. It avoids network calls when no subscription is active. To stop sending without deleting any data: `select cron.unschedule('goya-duty-reminders');` Re-enable with the schedule statement in `duty-reminder-cron.sql`.

## Validation

- Offline Chromium: login loading, duplicate submissions, error/retry, dashboard initial route, notice carousel/pause and text escaping, pending-history route, force-break display, push opt-in/out/denial, failed dashboard refresh, and overflow at 360/390/768/1440 widths.
- Admin notice editor: create/update/unpublish, UAE expiry conversion, duplicate submit guard, escaped text.
- Existing Attendance Admin and checkout-display regressions.
- Production database tests used transactions followed by ROLLBACK: staff/admin authorization, own-staff attendance, notice expiry, private-config permissions, 8h/9h due times, duplicate claim suppression, checkout cancellation, split gaps and force-break enforcement. No synthetic test records remain.
- Worker endpoint: invalid token rejected with 401; valid token returned 200 with zero jobs. A real device permission/subscription is still needed for a physical notification delivery test.

Advisors flag the existing custom PIN-session SECURITY DEFINER architecture; new browser RPCs explicitly call require_session before accessing private data, pin their search_path, revoke PUBLIC execution and use explicit anon/authenticated grants. Private tables intentionally have no direct client RLS policies. Worker RPCs are service-role-only. No existing table policies or authentication functions were altered.

Important notice mobile push (v43.1): apply `notice-mobile-push.sql` after
`notice-publication-date.sql`, then deploy `supabase/functions/duty-reminders`
with `deno.json` as its import map. The existing random worker-header check and
service-role-only worker RPCs remain required. No VAPID rotation is needed.
The existing cron handles both duty and notice queues. No old notice is enrolled.

Admin must explicitly check Send mobile notification with Important and Published.
Scheduled notices wait for publication. Editing does not resend an existing notice;
unpublishing or removing Important cancels its remaining queue. Create a new notice
for a new broadcast. Recipients are snapshotted once at publication, and both the
staff account and subscription must still be active and matched before dispatch.
Retries are bounded to three attempts; provider expiry deactivates the endpoint.
One notice/device delivery record plus a stable notification tag limits duplicates.
Push service acceptance is not proof that the phone displayed or the staff read it.
Delivery requires opt-in and is subject to OS/network settings. No real device push
was sent during validation. Mock worker tests and SQL transaction/rollback checks
cover auth, scheduling, cancellation and deduplication.

Portal history and notice lifecycle (v44): apply
`paged-history-and-notice-delete.sql`. Existing `admin_orders` and `staff_history`
APIs remain intact for compatibility. New browser list requests use authenticated
30-row server pages, stable `(created_at, id)` ordering, counts, and clamped page
numbers. Staff history requests only the active kind; monthly and all-date open
orders retain existing team visibility. Date filters use UAE calendar boundaries.
Admin dashboard uses a counts + eight recent orders summary; no order history is
loaded during login. CSV and Supplier WhatsApp load all applied-filter matches
only on explicit request. Selection and row edits operate on the visible page.

Notice Delete is a retained-record deletion (`deleted_at`, `active=false`), hidden
from admin lists and staff dashboards, with pending push cancellation. A stale
editor cannot restore a deleted notice. No existing notices are removed by the
migration. The dashboard carousel frame is fixed per breakpoint, rotates every
three seconds when playing, scrolls internally, and pauses on touch/hover/focus.

Validation: `tests/pagination.cjs`, `tests/notice-frame-delete.cjs`, existing login,
dashboard, theme and notice tests. SQL transaction/rollback checks verify bounded
pages, totals, last-page clamping, authorization, retained deletion, and push
cancellation without deleting real user data.

Staff remembered login and attendance presentation (v45): apply
`staff-remembered-login.sql`. Remember this device is checked by default, can be
unchecked for shared devices, and stores only the existing random session token
under `goya-staff-session-v1`. No PIN or cached staff identity is stored. A private,
RLS-protected opt-in marker extends only staff sessions to 30 days. Resume checks
both session validity and current staff activity, returns current permissions,
and renews expiry. A ten-minute visible-page heartbeat also renews active usage.
Admin sessions are unchanged. Logout deletes the session and its remembered marker;
Admin changes to active or pin_code revoke that staff member's remembered sessions.
The existing app_sessions cleanup handles expiry. No existing staff session is
extended or revoked merely by deploying this migration.

Auth/bootstrap requests have bounded waits and use their own loading state, so a timed-out background request cannot leave the global loading indicator stuck. Network/bootstrap failures retain the saved token for Retry instead of treating
an outage as invalid credentials. Invalid, expired or revoked sessions return to
PIN. Use PIN instead cancels a pending restore, clears the saved credential and
attempts logout of the old session. Cross-tab storage changes reset the old identity.
Read responses carry session-generation guards so an old restore/draft/status reply
cannot overwrite a newer staff session. Explicit sign out clears local persistence
before network cleanup; server revocation is best effort when offline and cannot
complete until connectivity is available. Browser site-data deletion, private-mode
closure or storage eviction removes remembered login. Clearing only HTTP cache does
not remove localStorage. Installed web apps remain subject to these browser rules.

Attendance cards initially hide details, use a plain accessible summary button
without a chevron, toggle on any card click, and keep expanded dates during refresh.
Desktop table and PDF export stay complete. The timer ring consumes existing totals:
remaining duty shrinks the teal arc; after duty, a warm overlay grows in one-hour
visual cycles over the completed ring. This visual cycle does not change paid OT,
break, split gaps or any attendance formula. `calcRow` is unchanged. Reduced-motion
settings disable transitions. Goya Live files and database attendance APIs are unchanged.

Validation: `tests/remembered-login.cjs`, `tests/attendance-design.cjs`, existing
login/dashboard/pagination/theme suites, plus transaction/rollback checks for expiry,
PIN/activity revocation, current permissions, staff-only access and logout cascade.
No real staff PIN or physical phone login was used in these tests.
