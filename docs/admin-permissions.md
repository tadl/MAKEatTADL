# Staff interface permissions

The custom staff interface uses the existing `StaffUser#admin?` flag and
CanCanCan `Ability`. Each controller authorizes its actions on the server;
navigation visibility is only a convenience. A patron portal login does not
grant staff access.

This baseline was established by inspecting the RailsAdmin configuration,
custom actions, models, and installed authorization adapter on November 17,
2026. Effective CanCanCan permissions were also checked in the test environment.

## Permission matrix

| Operation | Staff | Administrator |
| --- | --- | --- |
| Overview, statistics, workflow guide | Allowed | Allowed |
| View and update existing jobs | Allowed | Allowed |
| Create, delete, bulk delete, or export jobs | Denied | Allowed |
| Read and send job conversations | Allowed | Allowed |
| Attach, download, and remove job model files | Allowed | Allowed |
| Mark a ready job picked up using the dedicated action | Denied | Allowed |
| View patrons and update name/email | Allowed | Allowed |
| Create, delete, bulk delete, or export patrons | Denied | Allowed |
| Merge patrons | Denied | Allowed |
| Read lookup and printable-model records | Allowed | Allowed |
| Modify lookup and printable-model records | Denied | Allowed |
| Directly manage staff, messages, conversations, or activity records | Denied | Administrator only, subject to each screen's allowed operations |
| Change a staff account's administrator flag | Denied | Allowed |
| Save own theme and density preferences | Allowed | Allowed |

Lookup records include statuses, categories, printers, print types, filament
colors, pickup locations, and printable models. The old interface hid these
navigation entries from ordinary staff even though their underlying read
permission was allowed. Staff permissions apply to all jobs and patrons; there
is no existing per-location or per-job ownership restriction for staff.

The original `Ability` aliased index, show, edit, and update to read. The custom
interface uses conventional read/update actions instead, preserving effective
permissions without implying that read access permits editing.

`PATCH /admin/preferences` is an authenticated self-service endpoint for theme
and density only. It always updates the signed-in staff account, ignores record
IDs and identity/role fields, and does not grant general StaffUser edit access.
The supported values are validated by the model and database constraints.

## Authentication and session boundaries

- `/admin/login` shows the Google sign-in prompt; sign-in starts with a POST to
  `/auth/google_oauth2`. Google callbacks continue through
  `/auth/:provider/callback`.
- Staff identity is read from `session[:staff_user_id]`. A successful sign-in
  rotates the session and defaults to the custom admin overview.
- Only local `/admin` return paths are accepted after login. External URLs,
  non-admin paths, backslashes, line breaks, and the login page are rejected.
- Every custom admin controller inherits from `Admin::BaseController`, which
  authenticates staff and checks `:access, :admin` before controller actions.
- Logout clears the staff session and retains the existing patron logout
  behavior. `Current.staff_user` and Audited attribution continue to use the
  signed-in staff account.
- Staff responses use `Cache-Control: no-store`, and the staff layout disables
  Turbo snapshots so a previous staff screen is not restored from a snapshot
  after signing out.

Google's configured domain and hosted-domain checks remain in `StaffUser`.
`GOOGLE_DOMAIN` must be configured to enforce an organization boundary: an empty
value leaves domain filtering disabled. The UI port does not change the
existing Google identity acceptance rules.

## Protected fields and exports

Patron forms accept name and email only. They do not display, export, or accept
authentication tokens or token timestamps, and they cannot reassign jobs by
submitting association IDs. This deliberately replaces the former generic
administrator token/association fields with contact editing. Job reassignment
for duplicate patrons remains available through the administrator merge action.

Patron CSV, JSON, and XML exports allow only ID, name, email, and creation time.
CSV cells beginning with formula characters are escaped. Ordinary staff cannot
invoke export endpoints directly.

The activity log is read-only, including for administrators. Credential fields
inside audit changes are redacted in both pages and exports. The former generic
audit creation/edit/deletion controls are intentionally omitted so the staff
interface cannot rewrite its own history. Existing records are preserved.

Job identity and ownership, calculated costs, and system tracking fields should
remain protected by each controller's explicit parameter allowlist. Hiding an
input alone does not protect a field.

## Existing behavior that needs care

The former dashboard rendered pickup controls to all staff, but the dedicated
`picked_up` action had no ordinary-staff grant and was denied by CanCanCan.
The custom interface preserves that effective permission and hides the action
from staff who cannot use it. Ordinary staff can still update a job's pickup
date through the existing edit workflow, which invokes the same archival
callback. Changing that policy is separate from porting the interface.

The `files` permission includes deleting model attachments, even though staff
cannot delete jobs. Attachment deletion must be scoped to the selected job.
Adding model files to a scan must preserve its `ScanJob` identity.

Conversation mentions force a staff-only note. Public replies notify the
patron; staff notes do not. Reading a conversation marks patron messages read
and clears only the current staff member's notifications for that conversation.

ActiveStorage currently uses ordinary signed blob URLs. Anyone holding such a
URL can retrieve that file; the UI port does not add per-request staff/patron
authorization to the underlying ActiveStorage delivery endpoints.

## Verification

`test/models/ability_test.rb` records the role matrix.
`test/integration/admin_permissions_test.rb` exercises anonymous access,
patron-versus-staff sessions, login return paths, logout, and direct requests to
administrative patron actions. `test/integration/admin_patrons_test.rb` covers
contact editing, protected attributes, search, pagination, creation, deletion,
merging, and safe export fields. Job, attachment, conversation, and configuration
workflow tests provide the remaining controller-level coverage.
