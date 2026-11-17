# Custom staff workspace verification — November 17, 2026

The first implementation is on `codex/custom-admin`, starting from `5f6f589`.
The original RailsAdmin configuration, all custom actions and overridden views,
effective permissions, domain callbacks, reports, and scheduled tasks were
inspected before implementation. The baseline passed 93 tests and 470 assertions.

The RailsAdmin gem, engine, initializer, custom-action classes, views, theme,
and its vendored jQuery UI asset override are removed. Their relevant behavior
is implemented in the custom controllers and Tailwind staff layout. Historical
email/bookmark GET links redirect to their replacements. New mention emails use
the application's conversation route.

## Latest verification and review readiness

The latest local run after the pagination, appearance, CI, and catalog-selection
changes passed **256 Rails tests and 9,075 assertions** with `CI=1`, with no
failures, errors, or skips. Both Chrome suites passed: 27 desktop/mobile page checks, 19 viewport
confirmation controls, user-menu/appearance behavior, and chart navigation,
theme changes, and failure recovery. Production-mode assets and eager loading
also passed. The dependency audit and reviewed scanner result below were
rechecked without a change in findings.

GitHub Actions now runs the Rails suite, eager-load check, asset compilation,
and both browser regressions on Ubuntu with PostgreSQL. Its actual run results
are recorded in the repository's Actions tab. See [development and CI setup](admin-development.md#github-actions)
for the locked browser dependencies, fixture safeguards, and coverage limits.

The branch is ready for a coordinator walkthrough with synthetic data. Before
acceptance, restore or explicitly defer the [remaining parity gaps](admin-parity-review-2026-11-17.md).
Walk through pickup and library actions as both an ordinary staff member and an
administrator; those dedicated actions retain their administrator-only boundary.
Decide whether the existing global read-marking behavior is acceptable for this
release or whether the proposed shared Needs response queue is required.

Controlled live Google login/CAPTCHA, outbound email, and inbound-reply smoke
tests remain outstanding. The browser CAPTCHA checks simulate the SDK.
Production scheduling and a Dokku build/release have not been validated here.

The review also corrected a pre-existing public catalog-selection boundary:
Fidget and Assistive POSTs now resolve models through their matching collection,
and generic requests reject catalog IDs. Missing, invalid, cross-collection, and
staff-only selections return a validation error without creating requests or
copying files. Regressions retain valid public model files, pricing/status,
CAPTCHA checks, and eligible choices after form errors.

## Initial implementation checks

| Check | Result |
| --- | --- |
| Full Rails suite with `CI=1` | 174 tests, 1,503 assertions; zero failures, errors, or skips |
| Chart browser regression in Chrome | Passed delayed library load, Turbo navigation, filters, leaving, Back, reload, mobile navigation/layout, and readable chart-failure fallback |
| Staff layout browser regression in Chrome | Passed 19 actual rendered screens at desktop/mobile widths, Turbo model-library navigation, reprint link, and live STL preview zoom/reset controls |
| Production-mode asset compilation | Passed with the local test database, synthetic secret, and outbound mail disabled |
| Zeitwerk eager-load check | Passed |
| Bundle check | Passed |
| JavaScript syntax and Git whitespace checks | Passed |
| Bundler Audit | No vulnerabilities reported with advisory database `cad74bbe85c643bb9456450f357d6288c9ded2f8` |
| Brakeman 8.1.0 | Zero errors; one reviewed weak-confidence URL warning, described below |

All browser records and exported attachments are synthetic. The fixture renderer
checks for an empty local test database and rolls back its records. Screenshots
and static fixture exports are stored outside Git.

The tests cover anonymous/staff/administrator boundaries, direct mutation
requests, protected fields, session return paths, malformed parameters, staff
notes and mentions, file ownership and validation, unchanged scan identity,
pricing/status callbacks, pickup gating, patron merges, filtered exports, and
credential redaction. Model-library checks also verify per-copy source weights,
source-job history, retention after deleting the original job attachment, and
existing reprints retaining their file when a catalog file is replaced.

The populated mobile checks caught and fixed two overflow sources: visually
hidden headings escaping scrollable tables, and charts preserving their desktop
minimum width during a resize.

## Dependency and asset integration

Tailwind uses the `tailwindcss-rails` gem and bundled CLI, with no npm build.
Its generated CSS is separate from the public Bootstrap/SCSS assets. SassC still
compiles SCSS, but its legacy CSS compressor is disabled because it cannot parse
Tailwind's modern media queries; Tailwind minifies its own output.
See the [official integration](https://github.com/rails/tailwindcss-rails).

The refreshed advisory database also led to these narrow dependency updates:

| Gem | Previous | Locked |
| --- | --- | --- |
| Puma | 7.2.1 | 7.2.3 |
| OmniAuth | 2.1.4 | 2.4.1 |
| MessagePack | 1.8.4 | 1.8.7 |

Puma's recent fixes include shutdown and connection-handling issues.
[Puma advisory](https://github.com/puma/puma/security/advisories/GHSA-jm4r-w4xx-qxw7)
OmniAuth's existing production `full_host` remains derived from configured
application host/protocol rather than request headers, and is compatible with
the updated host-handling implementation.
[OmniAuth source](https://github.com/omniauth/omniauth/blob/v2.4.1/lib/omniauth/strategy/hosts.rb)
The MessagePack advisory concerns its JRuby decoder; the lockfile was refreshed
alongside these updates.
[MessagePack advisory](https://github.com/msgpack/msgpack-ruby/security/advisories/GHSA-73v3-wf97-vpgj)

## Reviewed scanner warning

Brakeman reports a weak-confidence `LinkToHref` warning for the job's model URL
in `app/views/admin/jobs/show.html.erb`. That link is rendered only when
`Job#http_model_url?` accepts the full value through `URI.parse`, requires an
HTTP/HTTPS URI, and requires a host. Other values render as escaped plain text.
The executable legacy-URL integration regression passes. This is a reviewed
false positive; it has not been hidden through a scanner ignore rule. Brakeman
therefore exits with its warning status, rather than a clean-zero-warning status.

## Boundaries and remaining validation

The initial port required no schema migration. A subsequent additive migration
stores staff theme/density preferences, with defaults and database constraints;
it has been applied only to local development/test databases. The existing
Dokku predeploy command runs `db:migrate` during a separately authorized release.
No production access, deployment, live email, or live Google login was performed.
Actual Dokku builds and the production scheduler remain unverified. Existing
Rails boot/test deprecation warnings remain.

The public UX redesign and changes to backend workflow/pricing/automation rules
remain later iterations with the makerspace specialist. The first library uses
the existing single-file catalog schema; richer revisions, multi-file designs,
tags, and printer/material profiles remain design work.

Existing effective role boundaries are preserved. Administrator-only library
writes/reprints and the dedicated pickup action follow those boundaries. The
activity log is deliberately read-only, and authentication tokens are omitted
from forms/exports. Signed ActiveStorage download URLs retain their existing
bearer-link behavior. See the [permission matrix](admin-permissions.md),
[port inventory](admin-port-inventory.md), and [automation map](automations.md).

The branch is intended for review and iteration before merging to `main`.

## Feedback iteration

The subsequent iteration adds the guarded `demo:seed` task, the TADL palette
and shared header/body background images, automatic mesh thumbnails, and three
clear library collections. At that checkpoint, the suite passed **216 tests and
8,414 assertions**, with no failures, errors, or skips. Those Chrome checks covered
19 desktop/mobile screens, actual generated thumbnails, uploaded-photo priority,
missing-file states, collection choices, save-from-job discovery, and STL controls.
The chart navigation/failure regression also passes. Production-mode asset
compilation, eager loading, and the dependency audit pass; the same reviewed
weak-confidence model-URL scanner warning remains.

The default demo dataset has 300 jobs across all 11 statuses and five demo pickup
locations, including 240 print jobs and 60 scan jobs. Local population and an
idempotent second run were observed; the second run created zero jobs. An
explicit supplied-STL run populated local library model files without adding
the supplied binary to Git. See [demo data](demo-data.md) for guards, preservation
behavior, optional templates, and the explicit library-file replacement flag.

Generated thumbnails read actual ASCII/binary STL or core 3MF geometry on the
server. Parsing has source/decompression, archive-entry, mesh, component, numeric,
and recursion limits. Archives are never extracted to disk. Output contains only
validated numeric geometry and fixed styles; authenticated image responses use
no-store, nosniff, and sandbox headers. Orthographic backface culling prevents
hidden faces from painting over thin models. Unsupported or malformed inputs
receive a fixed safe placeholder. Materials, textures, beam lattices, and
mixed-unit assemblies are outside the thumbnail renderer's scope.

Staff library is the default for newly saved job models. Assistive/Fidget are
explicit public choices; legacy duplicate job-category rows are preserved and
do not produce duplicate collection options. Printing notes copy technical
settings and per-copy material use, without patron identities or request text.

The local development server was restarted after dependency/configuration
changes and its `/up` endpoint returned HTTP 200. Development asset resolution
now uses the current asset environment, so a previous QA precompile cannot mask
Tailwind watcher updates. No production database, deployment, merge, or live
production scheduler was involved in this iteration.
