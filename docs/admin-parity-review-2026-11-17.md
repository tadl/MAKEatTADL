# Admin conversion parity review

Compared the custom admin branch with `origin/main` at
`5f6f5892fddc722893f3925aa50acf387c3b4def`, including its RailsAdmin configuration,
custom actions/templates, and RailsAdmin 3.3.1's generic list/export behavior.
This is a list of confirmed interface gaps, not a claim of complete parity.

## Corrected in this iteration

- Confirmation prompts use one branded viewport dialog, with Cancel/Escape,
  focus containment/restoration, and cancellation during navigation. This covers
  pickup, individual/bulk deletion, and patron merges. The public CAPTCHA error
  uses the same component in notice mode.
- Pickup confirmation again includes patron, pickup location, completion date,
  and price. The stored final price takes precedence; an estimate is explicitly
  labeled when the final price is absent. Missing prices remain distinct from
  `$0.00`. Both Overview and job-page buttons use the same helper.
- Successful pickup returns to Overview, preserving consecutive handoffs from
  the ready-for-pickup list.

The previous pickup details and redirect are visible in
`origin/main:app/views/rails_admin/main/dashboard.html.erb:114-178` and
`origin/main:lib/rails_admin/config/actions/picked_up.rb:63`.

## Remaining gaps

These require restoration or an explicit product decision before calling the
conversion complete. They are not implemented by this review.

| Area | Confirmed difference | Source evidence |
| --- | --- | --- |
| Job exports | Selected-row exports and field/association/CSV-option selection are absent. The fixed safe export also omits useful operational fields such as URL, filament color, duration, request origin, and starting/finishing staff/timestamps. | Old RailsAdmin export action/template; current `app/controllers/admin/jobs_controller.rb`, `export`. |
| Other export menus | Patron, model, and settings lists visibly offer CSV only, though their JSON/XML endpoints remain available. Job list still offers all three formats. | Current list templates and export controller actions. |
| Filters and old bookmarks | Exact patron/job-ID filters and generic operators are missing. Legacy job links translate query/scope/status, silently losing other old filters. | Old Job list configuration/generic index; current `JobsController#filtered_jobs` and `LegacyController`. |
| List controls | Select all, scope counts, numbered page links, and the old limited Show all control are missing. Individual selection and previous/next pagination remain. | Old `app/views/rails_admin/main/index.html.erb`; current list and pagination templates. |
| Patron navigation | Job rows and request details show patron names without the old direct patron-record links. Patron records and job history still exist. | Old association rendering; current `admin/jobs/index` and `admin/jobs/show`. |
| Audit history | The patron-specific history link/view, exact audited-record filter, and actor/target record links are missing. Global read-only activity inspection remains. | Old RailsAdmin config lines 345-360 and 515-522; current patron show and generic audit resource. |
| Merge context | Losing/winning patron job counts are absent from the merge screen. The transactional merge itself remains. | Old `merge_patron.html.erb:16,30`; current `admin/patrons/merge`. |
| Conversation images | Clicking a thumbnail downloads the file rather than opening the full-size image in another tab. Uploading and thumbnail display remain. | Old `_message.html.erb:21-23`; current `admin/jobs/conversation`. |
| Existing message attachments | Administrators cannot edit/remove existing message image attachments through generic message maintenance. Conversation attachment upload/viewing remains. | Old Message configuration and RailsAdmin ActiveStorage field controls; current message resource fields/form/show. |
| Smaller conveniences | Edit-page URL Open button and inline association create/edit controls are absent. The model URL remains clickable on job details; related records have their own screens. | Old `_url_with_open`/association controls; current job form/resource screens. |

## Retained behavior and deliberate restrictions

`Job`, `PrintJob`, `Message`, `PrintJobReport`, and `StaffDashboard` have no source
changes from the baseline. Pricing calculations, quote/completion callbacks,
pickup archiving, patron-response status transitions, and report calculations
therefore remain in their existing owners. Conversations retain privacy,
mentions and the old read-marking semantics. The proposed shared Needs response
queue has not been implemented.

Credential/token fields remain excluded from edit forms and exports; activity
records remain read-only. Those restrictions are intentional and should not be
removed to reproduce generic RailsAdmin behavior. The existing staff versus
administrator action boundaries are documented in `admin-permissions.md`.

## Verification

Pickup regression coverage checks positive, zero, estimated, and missing prices
on both entry points, the retained patron/location/completion context, and the
successful redirect to Overview. Browser coverage exercises all fourteen
confirmation controls and real HTTP form submission against synthetic fixtures.
CAPTCHA browser tests simulate the SDK; they do not contact Google's verification
service. Server-side CAPTCHA verification remains unchanged.
