# Branches and Events

The existing GOYA operation remains the default branch. Goya-Event is seeded as a separate Event with active staff assigned. Delivery address and start/end dates are optional; ending a date never archives an operation automatically. Branch names and membership are managed from the shared header or Admin/Attendance Settings. Archive preserves records.

Staff profiles, documents, leave requests, off balances, appearance, master items and suppliers are shared. Orders, drafts, production/wastage, inventory, breakage, notices, admin notifications, attendance records/rules, P&L and roster publications are branch scoped. An order captures the branch's name/address at submission; later edits to branch settings cannot change that snapshot.

## Isolation contract

- The browser calls `goya_branch_call` with the selected branch, an allowlisted RPC name and its original arguments. The gateway checks the real session and staff membership, then sets a transaction-local branch context. Switching operation reloads the page after saving operational carts/roster drafts; pending saves block switching.
- `goya_operations` is a NOLOGIN, NOBYPASSRLS function owner. Operational RPCs must retain this owner. It has no table ownership or schema CREATE permission. RLS policies restrict operational tables to `goya_private.current_branch()`. Legacy calls default to GOYA.
- Never replace the scoped function owner with a table owner or BYPASSRLS role. Never add an operational table without its branch column, RLS policy, scoped natural key and parent consistency constraints. New RPCs require registry and frontend routing updates.
- Global employee identity/document APIs intentionally use the employee session helper; employment and personal documents are not duplicated for each location. Branch attendance and roster staff lists use membership views.
- Staff cannot submit a second open attendance session at another branch. Published shifts cannot overlap a published shift at another branch. Paid Off balance is shared and a day cannot be charged twice across branches.
- Background workers use separate service-role-only entry points. Each job's branch is carried through checks, result updates and notification links. Do not expose the worker gateway to anon/authenticated roles.

## Preservation and verification

The migration is transactional and adds branch identity to existing records as GOYA. It does not remove staff, orders, attendance, files, leave or roster history. Original row IDs and timestamps remain unchanged. The old API signatures remain available for GOYA clients.

Validation used a separate PGlite database with the production table structure, constraints, triggers and 272 existing function definitions, plus synthetic employees/sessions. Checks cover legacy and Event orders, pagination, drafts, delivery snapshots, cross-branch edits, roster overlap, independent settings/weeks, attendance check-in/out, shared document identity, archive, membership and worker authorization. Mobile browser checks cover all five portal pages and branch settings; worker tests mock delivery instead of sending notifications.

Before publishing, compare existing GOYA business records before/after migration, verify the exact changed files, deploy the worker updates, and wait for GitHub Pages deployment success. Configure Goya-Event GPS/network under Attendance Settings before accepting Event check-ins; the GOYA location/network allowlist is intentionally not reused for a new venue.
