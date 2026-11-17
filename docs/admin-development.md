# Developing the staff workspace

The custom staff interface replaces RailsAdmin at `/admin`. It uses ordinary
Rails controllers and ERB views, CanCanCan authorization, Tailwind CSS 4, and
Stimulus/Turbo. The existing public portal keeps its Bootstrap layout for the
later front-end UX overhaul.

## Branch and iteration

Development is on `codex/custom-admin`. Keep changes on that branch while the
makerspace specialist and staff review the workflows. Merge to `main` only when
the branch is accepted. A source push or merge does not deploy the app.

The first pass ports the existing operational capabilities and permissions:
jobs, files and previews, conversations and mentions, pickup, patrons and merges,
configuration, activity history, reports, and workflow documentation. See
[the inventory](admin-port-inventory.md) and [permissions](admin-permissions.md).

Subsequent rounds can change the information architecture and workflow based on
staff feedback. Public form/dashboard design, revised backend rules, automation
controls, and broader automation redesign are deferred until the port is stable.
The current rules remain in the existing models, controllers, and Rake tasks.

Use direct page headings, clear labels, restrained styling, and minimal eyebrow
text. Preserve keyboard navigation, visible focus, labels, narrow layouts, and
the readable data behind charts.

Paginated staff lists share numbered controls above and below their results,
including patron job history. Lists with 25 or fewer results omit pagination
entirely. The default page size is 25, with 50 and 100 also available. Larger
lists that fit the selected size retain the size selector without page buttons.
Changing the size starts at page one and keeps the current filters and sorting.
The preference stays in the URL so filtered links can be shared.
Bulk actions appear only while items on the current page are selected. Select
all applies to the visible rows/cards, and its mixed state reflects partial
selection. Server-side authorization remains independent of those controls.

## User menu and appearance

The header user menu shows the Google profile image and name, with initials as
a fallback. All staff can log out and choose appearance settings; administrators
also get an Overview shortcut. Theme and density use labeled icon segments with
native radio-group keyboard behavior and save automatically.

`StaffUser.theme` defaults to `system`, which follows the device preference;
explicit `light` and `dark` choices override it. `StaffUser.ui_density` defaults
to `normal`, with `condensed` reducing row, card, form, and layout spacing while
keeping full-size controls. Both choices persist with the staff account across
sign-ins and browsers. Google profile refreshes retain the saved choices.

The staff layout renders the attributes before styles load, and CSS resolves
System mode without an initialization flash. Charts update their text/grid
colors after appearance or system-theme changes. The shared dialog uses staff
theme variables while retaining its existing public-portal styling. Palette
changes are immediate, with no color fades or dimming of the preference segments
while saving; the save-status line reserves its space to keep controls steady.

## Local setup and styles

Use the repository's `.ruby-version` and locked bundle. With a local PostgreSQL
development database configured:

```sh
bundle install
bin/dev
```

`bin/dev` starts Rails and the Tailwind watcher through `Procfile.dev`, installs
Foreman for the current Ruby if needed, and stops both processes with Ctrl-C.
The default port is 3000; use `bin/dev -p 3001` to select another port. Foreman is a local
development tool and is intentionally kept outside the application's bundle.

To build styles once without starting the development processes:

```sh
bin/rails tailwindcss:build
```

Staff styling lives in `app/assets/tailwind/application.css`; generated files
under `app/assets/builds` are ignored. Tailwind scans the admin views, staff
layout, admin helpers, and Stimulus controllers. Keep complete utility class
names in scanned sources. The gem includes the Tailwind CLI, so these builds
do not require Node or a JavaScript package installation.

The staff palette follows the TADLPhone TADL theme and
[TADL's website theme](https://www.tadl.org/themes/custom/website_theme/css/style?ton0n3):
primary blue `#49688e`, strong/navy `#0b2f57`, and teal accent `#07846c`.
The header and body use the shared `tadl-header-bg.jpg` and
`tadl-content-bg.jpg` assets. Controls and text sit on solid readable panels.
Development resolves current assets from the asset environment so a previous
QA precompile cannot hide Tailwind watcher updates.

To populate a local development database with representative jobs, files,
conversations, and locations, see [synthetic demo data](demo-data.md).

The public stylesheet and Bootstrap are separate from the staff layout. Avoid
loading both CSS frameworks into the same page. Normal Rails asset
precompilation also builds Tailwind.

For a normal interactive preview, open `/admin` on the local Rails server and
use the configured Google staff login. This branch does not add an authentication
bypass or a local admin password.

## Synthetic layout preview

The browser fixtures render actual staff templates using synthetic test records
and roll those records back. They use Rails' test mail delivery and queue
adapters. Use a dedicated local test database; never point them at production.

After preparing that test database, build assets:

```sh
RAILS_ENV=test DATABASE_URL=postgresql:///make_at_tadl_test RBENV_VERSION=3.4.12 rbenv exec bundle exec rails assets:precompile
```

To export static overview/statistics pages for layout review:

```sh
preview_dir="$(mktemp -d "${TMPDIR:-/tmp}/make-admin-preview.XXXXXX")"
RAILS_ENV=test DATABASE_URL=postgresql:///make_at_tadl_test RBENV_VERSION=3.4.12 STATS_BROWSER_PAGES="$preview_dir" rbenv exec bundle exec ruby test/browser/render_stats_pages.rb
ln -s "$PWD/public/assets" "$preview_dir/assets"
python3 -m http.server 3100 --bind 127.0.0.1 --directory "$preview_dir"
```

Open `http://127.0.0.1:3100/dashboard.html`, `stats.html`, or `filtered.html`.
These exports are for visual inspection: form submissions and application
links require the Rails app. Stop the static server after review. Files contain
synthetic records only; do not substitute real patron data for screenshots.

The browser regression below supplies its own temporary HTTP routes and tests
real Turbo navigation between the exported pages.

For broader visual QA, `test/browser/render_admin_pages.rb` exports overview,
jobs, job details/edit/conversation/files, patrons, library entries/forms,
settings, activity history, statistics, and help. Set `ADMIN_BROWSER_PAGES` to a
temporary output directory and run it in the same local test environment. It
refuses preexisting operational records, creates only synthetic fixtures, and
rolls those records back. Its `pages.json` maps application URL paths to exported
HTML and synthetic attachment filenames for a browser harness to serve.

## Verification

Run meaningful authorization and workflow integration tests, plus the existing
model and service tests, using the local test database:

```sh
RAILS_ENV=test DATABASE_URL=postgresql:///make_at_tadl_test RBENV_VERSION=3.4.12 rbenv exec bundle exec rails test
```

With Playwright available to Node and Google Chrome installed:

```sh
node test/browser/stats_navigation_test.cjs
node test/browser/admin_layout_test.cjs
```

That check covers delayed Chart.js loading, filters, navigation away, history
restoration, reload, narrow layout, and chart-library failure fallback. Browser
verification needs access to the pinned library CDN, unless the environment
provides a cache or fixture. The app itself uses importmap rather than an npm
build.

The layout check renders staff screens and pagination snapshots in a transaction
using an empty local test database. It checks desktop/mobile layouts, numbered
navigation and page sizes, selection-aware actions, confirmations, CAPTCHA
handling, library navigation, the reprint link, and live STL preview controls.
Set `ADMIN_SCREENSHOTS` to a directory outside the repository to save synthetic
desktop/mobile screenshots.

For exports of all those pages, run `test/browser/render_admin_pages.rb` with
`ADMIN_BROWSER_PAGES` set to a temporary directory. Its `pages.json` maps app
URLs, including pagination query strings, to the exported HTML and synthetic
attachments. No application login bypass is installed; these are static layout
fixtures with test mail/queue adapters, and all generated database records roll back.

Keep permission checks at the HTTP/controller boundary and test anonymous,
ordinary staff, and administrator requests. Hidden controls alone do not secure
a route. Retain checks for immutable job type, unchanged scan origin, safe URLs,
escaped file names, private staff notes, and audit attribution.

## Model library scope

The first library uses the existing `PrintableModel` record: name, code,
category, position, default single-copy weight, notes, one model file, and one
preview image. Administrators can manage entries and save a selected job file
into the library; staff can browse permitted entries. Linked print history
provides context for previous work. A print started from a saved model is a new
job, preserving the earlier job's history and using the existing workflow.

This preserves a useful starting point without a schema migration. A design
containing several related files, explicit file revisions, searchable tags,
printer/material profiles, and richer reprint defaults need a later design
with the specialist. Keep the library record and each individual print request
as separate concepts when adding those features.

Library collections are **Staff library**, **Assistive**, and **Fidget**. New
entries and files saved from jobs default to Staff library. Assistive and Fidget
are explicit public choices because those entries also appear on the public
request forms. Existing catalog entries backed by Patron or another nonpublic
job category display and filter as Staff library; their stored category remains
unchanged until a collection is explicitly selected. Duplicate job categories
are not merged or deleted by this interface.

Saving a job file pre-fills curated printing settings, source-run material totals,
per-copy usage, and a rounded default weight per copy. It does not copy patron
identity, contact information, request notes, conversation messages, or the job's
URL into printing notes. Staff can review and edit those notes before saving.
Cards and model details use an uploaded preview first, then a generated preview
of the attached model. Entries without an actual model file say **No model file**
and cannot start a reprint.

## Before accepting the branch

- Walk through real staff tasks with synthetic data at desktop and narrow widths.
- Check all former admin surfaces against the inventory, including less frequent
  configuration, export, deletion, and merge tasks.
- Confirm staff and administrator boundaries, message privacy, and notification
  behavior with the tests and local previews.
- Review the automation map against the actual callbacks/tasks before changing
  any rules. Production scheduling and delivery require separate live validation.
- Record remaining UX decisions and verification limits. Merge and deployment
  remain separate steps.
