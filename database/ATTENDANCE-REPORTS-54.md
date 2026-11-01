# Attendance report tables (release 54)

Report-only frontend update. No database migration, data writes, attendance policy or calculation changes are required.

Normal PDF and Excel exports retain the selected report filters. Each staff report includes a summary table, separate leave classifications, dated day-off/review notes and the daily timetable. Excel also provides combined summary, daily details and review sheets.

OT Only selects staff with positive OT matching the current filters, then includes their complete loaded selected-period records so weekly off and leave remain visible. The OT overview is followed by each staff member's summary and timetable. Existing OT calculations and historical snapshots remain unchanged.

`attendance-xlsx.js` wraps the official `xlsx-js-style@1.2.0/dist/xlsx.bundle.js` in a private function and exposes only `window.GoyaReportXLSX`. It preserves the original `window.XLSX` used by imports and legacy exports. License: `vendor/attendance-xlsx-LICENSE.txt`. To reproduce, wrap that distribution in an IIFE with local `module,exports,define,require` declarations and publish its local `XLSX` as `window.GoyaReportXLSX`; do not replace the original global. Strip its sourceMappingURL comment.

Validation: `tests/attendance-report-layout.cjs` generates and reloads real PDF/XLSX files for all four exports, checking classifications, notes, totals, filters, duplicate names, OT policy boundaries, unchanged input rows and preservation of the original XLSX global. It requires jspdf@2.5.1, jspdf-autotable@3.8.4 and xlsx@0.18.5 under `GOYA_REPORT_DEPS`. Generated files in `GOYA_REPORT_QA` contain synthetic fixtures only. PDF/Excel layout was also rendered and visually checked. Existing OT UI and review consistency tests cover the unchanged controls and calculations.
