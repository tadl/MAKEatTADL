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

## Observed checks

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

No schema migrations, production access, deployment, live email, or live Google
login were performed. Linux/Dokku builds and the actual production scheduler
remain unverified. Existing Rails boot/test deprecation warnings remain.

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
