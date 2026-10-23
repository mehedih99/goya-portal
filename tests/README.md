# Attendance Admin regression checks

Production changes are limited to `attendance.html`, `live-admin.js`, and the new admin-only stylesheet. Staff Portal scripts, shared styles, configuration, and database schema are unchanged.

Install Playwright in your development environment and its Chromium browser, then run:

```sh
node --check live-admin.js
node tests/attendance-admin.cjs
```

Optional environment variables:

- `CHROMIUM_EXECUTABLE_PATH`: use an existing Chromium binary.
- `CODEX_PRIMARY_RUNTIME_NODE_MODULES`: alternate location of Playwright.
- `TEST_EXPORT_MODULES`: node_modules directory with xlsx 0.18.5, jspdf 2.5.1 and jspdf-autotable 3.8.4. Enables real PDF/XLSX download checks.

The test blocks all network traffic and replaces Supabase with fixtures. It checks report-only UI, month/status filters, UAE time conversion in a non-UAE browser timezone, report export data, failed/in-flight report handling, batch preview, partial failures, duplicate submits, record changes after preview, and invalid session times. Desktop/mobile screenshots are temporary test output.

## Release validation

No production writes or database migrations were performed. The existing live and legacy history RPCs must both succeed; failures now stop report generation instead of silently omitting previous records. Admin writes reuse existing RPCs.

Batch operations commit each record separately, show failures individually, and never automatically retry. Each record is re-read before saving. This is not an atomic database transaction: server-side authorization and protection against simultaneous changes still depend on the existing Supabase functions. Verify the flow in a staging database (or a designated disposable test record) before merging into the live branch.

Device Attendance is removed from navigation only. Its old records, database functions, and dormant import markup remain preserved. No delete/archive action is exposed by the redesigned live report/control UI.
