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
