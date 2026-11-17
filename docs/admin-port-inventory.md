# Custom admin port inventory

The [2026-11-17 parity review](admin-parity-review-2026-11-17.md) records confirmed
gaps found during iteration, including generic RailsAdmin conveniences that the
initial port did not retain. This contract remains the target, not a statement
that every item has been completed.

This is the replacement contract established by inspecting the RailsAdmin configuration, custom actions, templates, authorization, reports, and tests before implementation. The first port keeps the existing data model and automation rules. Public portal redesign and changes to those rules are later work.

## Staff and administrator boundaries

All admin pages require the existing Google-authenticated staff session. An ordinary staff account can read and update jobs, use job conversations and files, read lookup records, and update patron names and email addresses. Administrators manage configuration, staff roles, patrons, and other operational records. The server must enforce these boundaries independently of navigation visibility.

| Capability | Staff | Administrator |
| --- | --- | --- |
| Overview, statistics, workflow guide | Yes | Yes |
| Read and update existing jobs | Yes | Yes |
| Conversations, staff notes, mentions, job file management | Yes | Yes |
| Create or delete jobs, bulk deletion | No | Yes |
| Read patrons; edit name and email | Yes | Yes |
| Create, delete, or merge patrons | No | Yes |
| Read model catalog and configuration lookup records | Yes | Yes |
| Modify model catalog or configuration | No | Yes |
| Staff role management, conversations/messages administration, activity log | No | Yes |
| Dedicated Mark picked up action | No | Yes |

The old ability rules did not grant ordinary staff the custom `picked_up` action, despite its prominent dashboard placement. Staff can still record a pickup date while updating a job, which archives it through the existing callback. The custom interface makes the dedicated action's administrator restriction explicit. A later permissions revision can change this deliberately.

The existing patron-update permission is preserved through explicit update authorization. Ordinary staff can edit patron name and email. Patron credentials and role attributes are not accepted through that form.

## Screen and action parity

| Existing surface | Replacement contract |
| --- | --- |
| Dashboard | Status counts and filtered queue links; ready-for-pickup list; unread patron replies; current user's mentions; request-form links. |
| Job index | Active/inactive/ongoing queues; search, filters, sorting, pagination, export; permitted row and bulk actions. |
| Job show/edit | Patron, category, status, pickup, notes; print or scan fields; computed costs displayed; immutable STI type and original request classification. |
| Job conversation | Read tracking; staff replies and internal notes; image attachments; forced internal treatment of mentions; staff and patron notifications. |
| Job files | Multiple STL/3MF uploads, per-job attachment deletion, downloads and STL preview; attach scan result files without changing job classification. |
| Picked up | POST with confirmation and server-side ready-status check; set today's pickup date, attribute staff, archive, return to overview. |
| Patrons | Searchable patron records and job history; permitted edit/create/delete actions. |
| Patron merge | Administrator confirmation; choose surviving record; transaction moves jobs and patron-authored messages, preserves surviving email, removes duplicate. |
| Printable models | Name/code/category/order/default weight/notes, reusable model file and preview image; initial save-from-job and Print again actions use this existing catalog. |
| Filament colors | Name/code/active/hex color, normalized and validated by the existing model. |
| Pickup locations | Name/code/active/scanner/FDM/resin flags and printer associations. These flags still control public service availability. |
| Printers | Name, pickup location, print type, model, bed size, location, public-notification flag. |
| Print types, statuses, categories | Existing labels/codes/ordering and associations; status job counts. |
| Staff users | Existing OAuth-created users, read-only identity fields, editable administrator role. No direct user creation. |
| Conversations and messages | Administrator record inspection and permitted maintenance; creation occurs through a job conversation. |
| Activity log | Administrator inspection of audited records, actors, timestamps, actions, and changes. |
| Statistics | Existing report definitions, date presets and location filters; summary metrics, category breakdown, daily quantity/material charts and filament color chart. |
| Help | Current workflow, status reference, automation map, and existing staff-guide link. |

Association choices were alphabetical in RailsAdmin rather than ordered by the legacy position field. Active-only pickup and color choices, optional relationships, read-only calculated costs, and printer-driven print type all need to survive the port.

RailsAdmin supplied generic search/filter/sort/export/pagination and administrator bulk deletion. Those capabilities are part of the replacement contract, even though they were not custom action classes. Exports must use explicit authorized fields rather than exporting login tokens, OAuth identifiers, or other credentials through generic model introspection.

## Existing automation map

These rules belong to the existing models, portal/inbound controllers, and Rake tasks. The UI port documents and invokes them; it does not replace them.

| Trigger | Existing owner | Effect |
| --- | --- | --- |
| Public request creation | `PortalController` | Patron print and scan requests begin Pending; fidget, assistive, and staff prints begin Approved; create patron/job/conversation and receipt notifications. |
| Estimated weight first populated on update | `PrintJob` | Recompute estimate; Patron category jobs with a conversation move to Information requested and send quote. |
| Information requested status entered | `Job` | Record explicit request timestamp and reset quote-reminder tracking. |
| Patron-authored message saved | `Message` | Information requested becomes Response received; portal and inbound-email paths share this behavior. |
| Assigned printer changes | `PrintJob` | Set print type; normally enter In progress. Ongoing and terminal/ready statuses are preserved. |
| Enter In progress | `Job`, `PrintJob` | Record first starting staff/timestamp. Opted-in jobs on public printers also receive a conversation message and start email. |
| Actual weight first populated | `PrintJob` | Compute actual cost; record completion/finishing staff/timestamp; mark Ready for pickup; send completion message and email. |
| Resin volume first populated on resin job | `PrintJob` | Same completion path using resin pricing. |
| Pickup date populated on update | `Job` | Archive job. |
| Cancelled or Rejected status entered | `Job` | Conversation status notice and patron email. |
| Staff conversation contains mentions | Admin conversation action | Force internal note, notify matching staff, do not email patron. |
| Quote aged 7–13 days | `print_jobs:info_requests_nudge_and_cancel` | Nudge eligible Patron-category print requests with a positive estimate, at least 7 days after last nudge. |
| Information request aged at least 14 days | Same task | Cancel still-waiting print jobs; verify status and request timestamp again under lock. Skip missing timestamps. |
| Ready job's pickup reminder due | `print_jobs:send_pickup_reminders` | First reminder after 7 days, then every 7 days after last sent reminder; require completion date; stop at abandonment eligibility. |
| Ready job completed at least 30 days ago | `print_jobs:abandon_overdue_pickups` | Mark Abandoned; send courtesy notice. |

`print_jobs:nightly_maintenance` invokes the three scheduled mutation tasks. It attempts every section and exits unsuccessfully if any section fails. Scheduled messages are delivered synchronously before task exit and audited as the automation staff account. Preview tasks exist for quote follow-ups, pickup reminders, and abandonment. This code inventory does not verify the production scheduler or delivery.

Ongoing suppresses the estimate/completion/print-start callbacks. It does not suppress all model callbacks: recording pickup still archives, and Cancelled/Rejected still notify.

## Reporting semantics retained

`PrintJobReport` remains the source for statistics. Submissions use print-origin requests created in the date range. Completions use completion dates and exclude Cancelled/Rejected; scans use preserved original request type. Blank/zero quantities count as one. Filament and resin totals retain the existing stored-total semantics. Design identity uses saved catalog id, normalized URL, file checksums, or job fallback.

The custom statistics controller prepares report data, validates ISO dates and range order, rejects unknown location filters, and limits a request to 3,660 days. Chart data is escaped into HTML attributes. The Stimulus chart controller waits for the pinned Chart.js library and destroys charts on disconnect and before Turbo caching. Every chart also has a readable data table.

## Compatibility and verification

- Keep existing admin conversation URLs usable for previously delivered mention emails; new mail uses the app's route helpers.
- Remove RailsAdmin engine/gem/configuration/actions/views and its vendored asset chain only after replacing cross-references, including shared portal message rendering and mailer links.
- Use a separate Tailwind staff layout. The existing Bootstrap public portal remains for its later UX overhaul.
- Preserve audit attribution and ordinary model saves so the current callbacks still run.
- Verify anonymous, ordinary-staff, and administrator HTTP access, including forged write requests and protected attributes.
- Retain model/service tests for job automation, reports, dashboard aggregation, patron merges, and inbound mail.
- Port filename/URL escaping, scan-result upload, catalog download/preview, and dashboard notification regressions.
- Exercise chart first-load delay, Turbo navigation, filters, leaving the page, history restoration, and reload in a browser.

The new makerspace specialist will guide subsequent UX iterations. The first model-library iteration supports saving one selected job file and starting a new print from a saved model. Richer repository features (multiple files, revisions, tags, and tested print profiles), the public interface overhaul, and changes to backend workflow rules remain follow-up work.
