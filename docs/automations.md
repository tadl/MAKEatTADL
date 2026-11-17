# Automations

This is the current behavior retained during the custom staff interface port.
Changes to these rules can be reviewed separately with the makerspace specialist.

## Staff edits and incoming requests

| Trigger | Result | Patron notification |
| --- | --- | --- |
| Submit a public print or scan request | Creates a job and conversation; copies request notes into the conversation. Patron requests begin Pending; fidget, assistive, and staff print requests begin Approved. | Receipt email |
| Assign or change a printer | Copies the printer's print type. Moves eligible print jobs to In progress. Leaves cancelled, rejected, archived, ready, abandoned, and ongoing statuses unchanged. | Progress message and email only when the patron opted in and the printer is public |
| First estimated weight on an existing Patron print job | Calculates the estimate; sets Information requested; starts a new response window and clears its reminder timestamp. | Quote message and email |
| First actual weight on an existing print job | Calculates cost; sets Ready for pickup and completion date; records finishing staff/time. | Completion message and email |
| First resin volume on an existing resin print job | Calculates cost; sets Ready for pickup and completion date; records finishing staff/time. | Completion message and email |
| Enter or re-enter Information requested | Records the explicit start of the response window and clears its reminder timestamp. | None from the status change alone |
| Patron replies through the portal or inbound email | Changes Information requested to Response received. Other statuses remain unchanged. | None |
| Staff posts a public conversation reply | Adds a patron-visible message. | Message email |
| Staff posts a staff note | Adds a message visible only to staff. | None |
| Staff includes `@username` | Forces the message to be a staff note. Each matching staff account gets a notification and mention email. Repeated mentions in the same message notify once. | None |
| Open a staff conversation | Marks its patron messages read for staff; marks mention notifications read only for the signed-in staff member. | None |
| Change status to Cancelled or Rejected | Adds an explanatory patron-visible message. | Message email |
| Enter a pickup date | Archives the job. The Mark picked up action first checks the job is Ready for pickup. | None |

Printer assignment and material edits use the existing model callbacks. The staff
interface saves records normally so that status changes, pricing, audit history,
staff attribution, and notifications continue to run at the same boundaries.
Calculated cost and staff-attribution fields cannot be supplied through the job
edit form. Patron and job type are fixed on existing jobs; attaching scan-result
model files keeps a scan job a scan job.

Setting estimated weight again after it already has a value recalculates its
cost but does not send another initial quote. Likewise, subsequent actual-weight
or resin-volume edits do not send the first-completion notification again.
Changing status to Ready for pickup manually records finishing staff/time but
does not itself send the material-completion message.

Ongoing jobs suppress the first-weight quote, material-completion notifications,
and opted-in progress notification. This is not a global pause switch: pickup-date
archival, cancellation/rejection messages, and attribution still apply when their
own conditions are met. Scheduled tasks select other specific statuses and do
not process Ongoing jobs.

## Pricing

The retained pricing rules are FDM at $0.10 per gram with a $1 minimum, and resin
at $0.35 per milliliter with a $3 minimum. Assistive, Staff, and Fidget categories
have a zero cost. Pricing changes are outside this interface port.

## Scheduled maintenance

The tracked application configuration requests
`rake print_jobs:nightly_maintenance` daily at `0 12 * * *`. The scheduler's own
timezone and the live installed schedule must be checked on the deployment host;
this document describes repository configuration, not a verified production run.

The batch runs these tasks in order:

1. `print_jobs:info_requests_nudge_and_cancel`: considers print jobs in Information
   requested. Jobs without `information_requested_at` are skipped. At 7–13 days,
   a Patron-category job with a positive estimate gets a quote reminder if none
   has been sent in the preceding seven days. At 14 days or later, the job is
   cancelled, regardless of category or estimate. Cancellation rechecks status
   and response-window timestamp under a row lock to avoid acting on a stale
   response window.
2. `print_jobs:send_pickup_reminders`: considers any job Ready for pickup with a
   completion date. A reminder is due seven days after completion or the last
   reminder. No reminder is sent once the job reaches the 30-day abandonment
   threshold.
3. `print_jobs:abandon_overdue_pickups`: marks Ready for pickup jobs Abandoned at
   30 days after completion and sends the existing courtesy message and email.

Preview tasks are `print_jobs:info_requests_preview`,
`print_jobs:pickup_reminders_preview`, and `print_jobs:pickup_abandon_preview`.
They do not change jobs or send messages. Their output includes patron contact
information, so keep that output out of Git, issue trackers, and shared logs.

The tasks require the configured automation staff account. They set the current
staff/audit actor to that account and restore the prior context afterward.
Maintenance emails are delivered synchronously before a task process exits.
Reminder timestamps are written only after successful delivery. If one task
section fails, the batch still attempts later sections and exits with an overall
failure. There is no persistent per-job retry queue; a repeated run after a
partially completed section can repeat messages. Preview and review the relevant
job history before manually retrying a failure.

## Delivery, links, and inbound email

Ordinary web requests queue mail with `deliver_later`. Only a web process is
declared in the Procfile, and production does not select a persistent job adapter
in the tracked configuration. Those jobs use Rails' default in-process queue;
queued work is not durable across process restarts. Development uses inline
delivery and tests use the test adapter. This port does not change that setup.

Receipt, conversation, and progress emails regenerate the patron's login token.
Tokens last seven days and are consumed after successful login. The reply address
contains the conversation token, which must remain stable across interface
changes. Staff mention emails link to the custom staff conversation.

Inbound email requires a valid Mailgun signature and configured signing key,
rejects expired or future timestamps and replayed tokens, resolves the recipient's
conversation token, and requires the sender address to match the job's patron.
Its created patron message follows the same Information requested → Response
received callback as a portal reply.

## Source and verification

The rules live in `app/models/job.rb`, `app/models/print_job.rb`,
`app/models/message.rb`, `lib/tasks/print_jobs.rake`, the mailers, and
`app/controllers/inbound_controller.rb`. Conversation posting and read receipts
live in `app/controllers/admin/jobs_controller.rb`; the public controller retains
submission and magic-link handling. The port keeps these backend rules intact.

Regression tests cover model transitions, attribution, response windows,
scheduled delivery/failure behavior, signed inbound email, and the replacement
staff actions. Passing local tests does not establish live mail delivery,
provider login, or production scheduler execution.
