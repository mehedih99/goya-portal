# Staff access and Event assignments

Admin → Staff → **Manage Access** is the central editor for each employee. Enable the relevant Branch / Event, choose allowed work and sections, then Save Access. New-staff registration uses the same controls. The Branch manager links to this page and displays membership without a separate permission form.

Permissions are independent per branch: Orders, Production, Wastage, Inventory Counts, Equipment / Breakage, Attendance and Schedule. Sections control available item catalogs and submissions. Existing branch memberships and effective permissions are retained when the migration runs. Staff profiles, documents and private notifications remain shared. Staff without Schedule access can still open My Journey.

Removing branch access keeps orders, attendance, publications, documents and other saved history. Attendance access cannot be removed during an open duty session; check the employee out first. Concurrent edits are checked before saving, and access changes have a private audit record.

In the GOYA weekly roster, choose **EVENT** and the destination Event branch. Only Event branches where that employee has Schedule access are offered. This saves an assignment with no working hours and no Paid Off debit. The Event manager plans and publishes actual shifts in that Event’s own roster. Branch membership determines whose name appears in each roster.

Legacy EVENT-labelled shifts display as EVENT; their original publications remain intact. CSV and PDF display the marker without hours. Excel accepts EVENT when that employee has exactly one eligible destination; for multiple Events, choose the destination in the portal editor.

Apply `database/event-marker-access.sql` once before publishing the matching frontend. It adds permission metadata, access revision/audit tables, permission-checked RPCs and Event validation. A transaction-level preservation check verifies pre-existing business rows and rolls back if their fingerprints differ. Operational RPC owners remain `goya_operations`, preserving branch RLS. The access editor’s two admin-only RPCs explicitly validate the existing management session before reading or changing membership.

Validation: isolated PostgreSQL tests cover permission independence, direct denial, section checks, Event-only registration, atomic registration failure, stale updates, independent Event duty hours, no off charge and retained historical exports after membership removal. Browser fixtures cover mobile controls, five portal branch selectors, Event editor and cart regression.
