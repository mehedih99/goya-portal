# Main Admin release 51

## User flows

- Admin PIN login offers **Remember this device** (default checked, optional). Only the session token is stored under `goya-admin-session-v1`; the PIN is never persisted. Saved sessions resume without PIN and renew after use, with a 30-day inactivity expiry. Full browser/site data clearing removes the saved token. Shared devices should leave Remember unchecked.
- Invalid/expired/revoked sessions return to PIN. Network failures keep the saved token with Retry / Use PIN controls. Logout clears the local token, unsubscribes this Admin registration and calls the existing server logout; server session deletion cascades its new private device records. PIN changes expire remembered Admin sessions and disable Admin push devices without deleting session/history rows. Existing ordinary Admin/Attendance sessions are unchanged by this new trigger. Cross-tab local token changes lock the old page.
- Main Admin bell → Desktop / phone notifications → **Enable notifications** on each personal device. Permission is requested only after clicking Enable. Enabling also remembers that login. Disable cancels pending deliveries on that device. The new manifest opens `admin.html`; Admin worker registration is scoped to `/admin-push/`, separate from the existing Staff registration. No APK is created. iPhone/iPad generally require Safari Add to Home Screen first; OS/browser/background settings can delay or suppress push. No physical phone delivery has been tested.
- Production & Wastage rows have **Edit Qty / History**. The modal shows existing quantities, accepts the corrected quantity and Storage/Ingredients unit type plus a required reason. It performs no unit conversion. A correction updates the same source row's quantity, unit and the relevant quantity column; its name/SKU, staff, created time, wastage reason and Pending/Done status stay intact. The old and new full row snapshots, correction reason and timestamp remain in private history. Future staff history/reports/exports read the corrected source; previous exported/imported Foodics files are not modified remotely. No real historical quantity was automatically corrected.

## Backend / safety

`admin_remember_push_and_audited_quantity_corrections` adds four private RLS tables, six session-authorized client APIs, three service-role-only delivery APIs and two private triggers. No business-row backfill, deletion or source schema change. Quantity edits require Admin, lock the row, compare expected quantity fields to reject stale updates, validate positive values up to 3 decimals, resolve units from the item catalog, and use a stable request UUID to make uncertain-response retries idempotent. The browser freezes an uncertain correction payload for Retry.

New submission pointers are queued once per currently enabled Admin device. No draft/status/quantity edit notification is created. Old submissions are not backfilled on opt-in. Unique delivery keys, claim leases, pre-send checks, tags and capped retries limit duplicates. Disable/rebind cancels pending deliveries; expired endpoints deactivate. Pending alerts older than one day are not sent, and deliveries cascade when their 90-day notification pointer expires. Source reports are not removed. Push is best effort: a lost result acknowledgement can cause a retry with the same replacement tag.

`admin-notifications` Edge Function v1 reuses the existing private VAPID/worker configuration; no secret was read, replaced or exposed. `verify_jwt=false` is intentional: POST requires the private worker header and claims/check/results use service-role-only RPCs. GET returns 405 and unauthenticated POST 401. Existing `duty-reminders` Edge Function, VAPID values, Staff subscriptions and Staff cron were not modified.

`schedule_admin_submission_push_worker` adds a once-per-minute cron that calls the new worker only with eligible pending deliveries. There is no new realtime subscription or idle Edge Function invocation. Delivery typically waits for the next cron run plus the push provider/device.

## Verification

- `tests/admin-device-db.cjs`: remembered session expiry/revocation, staff authorization denial, opt-in queue snapshots, claim lease, cancellation/rebind/410, private grants; both correction types/units, preserved row metadata, retry deduplication, stale conflict, input validation and audit.
- `tests/admin-device-ui.cjs`: actual Admin app + PGlite bridge; saved login/reload without another PIN, no PIN stored, unchecked remember, expired login, offline Retry, logout; correction/unit/history/lost-response retry/double-click protection, push permission deny/enable/disable, independent worker scope, mobile modal and 360/390/768/1440 light/dark layouts.
- `tests/admin-push-worker.cjs`: worker authentication and payloads, anonymous identity, cancellation and expired endpoint handling, service-worker Admin click routing. No real network push.
- Existing admin-login, remembered Staff login, portal-ui and Staff notice/duty worker checks passed.
- `tests/admin-device-live.sql`: real PostgreSQL with disposable synthetic tokens/items/operations inside BEGIN/ROLLBACK; passed with no retained fixtures, no real PIN/session read and no real device subscription or source row edited. Source fingerprints matched before/after: Production 261 rows `92f1faac421fc858a21894ad29617dd8`; Wastage 10 rows `63213b638a70fc35dfbf3c4a55d4aa60`; Inventory 375 rows `4c233de7d084cc93b041a366e93914c4`.
- Security advisors reviewed: four new deny-by-default private RLS INFO entries, six expected custom-token SECURITY DEFINER API entries; existing search-path warnings remain unchanged. No table grants were added for clients.

The first migration attempts expired in Supabase confirmation and did not apply. The successful version expires remembered sessions and cancels pending deliveries instead of deleting them. The subsequent live verification passed.

## Rollback

Revert only this frontend release. Retain the new audit, reports and private tables so saved history is not lost. Disable `goya-admin-notifications` cron and set Admin push devices inactive if rolling back push. Remove only the new Admin-specific triggers if rolling back integration; do not delete business rows or restore old source snapshots automatically. Already-authorized corrections remain in their source and audit.
