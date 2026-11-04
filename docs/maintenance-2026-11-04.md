# Maintenance review — 2026-11-04

Reviewed the patron portal, staff dashboard, conversations, reporting, upload
rendering, dependency lockfile, and existing regression checks. The starting
checkout was clean on `main` at `2143374`. GitHub reported no open pull requests,
including dependency updates. No production access or deployment was performed.

## Runtime and dependencies

Ruby is now **3.4.12** and Rails is **8.1.4.1**, with matching Gemfile, lockfile,
and `.ruby-version`. Rails remains constrained to 8.1.x, and its existing 7.1
configuration defaults are retained. Bundler remains 2.6.9.

| Dependency | Before | After |
| --- | --- | --- |
| Rails components | 8.1.3.1 | 8.1.4.1 |
| RailsAdmin | 3.3.0 | 3.3.1 |
| Rack | 3.2.6 | 3.2.8 |
| Nokogiri | 1.19.4 | 1.19.7 |
| rails-html-sanitizer | 1.7.1 | 1.7.2 |
| Loofah | 2.25.2 | 2.25.3 |
| Crass | 1.0.7 | 1.0.8 |
| Bootsnap | 1.18.6 | 1.26.1 |
| pg | 1.5.9 | 1.7.0 |
| CanCanCan | 3.6.1 | 3.7.0 |
| dotenv / dotenv-rails | 3.1.8 | 3.2.0 |
| Jbuilder | 2.13.0 | 2.15.1 |
| mailgun-ruby | 1.3.7 | 1.4.6 |
| reCAPTCHA | 5.19.0 | 5.21.2 |

Rails 8.1.4.1 includes the November 4 security fixes. The refreshed advisory
database also identified Crass CVE-2026-116695; 1.0.8 fixes its CSS tokenizer
sanitizer bypass. Major API migrations such as Pagy and OpenSSL are deferred.

On this Mac, installing the existing OpenSSL gem against Homebrew OpenSSL 4
failed. This local build setting selects the compatible OpenSSL 3 installation:

```sh
BUNDLE_BUILD__OPENSSL=--with-openssl-dir="$(brew --prefix openssl@3)" bundle install
```

This is a local native-build option, not a new production setting. The bundled
gem successfully loaded OpenSSL 3.5.9 during verification.

## Performance and correctness

- The patron dashboard preloads statuses and printers and looks up pickup
  names once per page. Pagination now breaks timestamp ties by job ID.
- Both conversation views preload authors and image attachments. Thumbnail
  processing happens on the image request instead of blocking the HTML response.
- `StaffDashboard` groups status, unread-message, and personal-mention counts
  and preloads the referenced jobs and patrons. Its controller replaces the
  unused default RailsAdmin dashboard queries for every visible model.
- Design reporting fetches only job identifiers, model IDs, URLs, and checksums
  in one query, without instantiating Active Record objects. Design precedence,
  URL normalization, attachment ordering, and per-job fallback are preserved.

Measured with synthetic data and cleared query caches, using the updated bundle
for both original and revised application code:

| Patron page, 10 rows | Original SELECTs | Revised SELECTs |
| --- | --- | --- |
| Dashboard, distinct statuses/printers/locations | 35 | 7 |
| Conversation, distinct authors and no images | 29 | 12 |

The revised counts remain 7 and 12 when growing from one to ten rows. Staff
dashboard data loading remains nine SELECTs when growing from one to ten ready
jobs, unread conversations, mentions, and additional statuses. These are query
measurements, not production latency benchmarks.

## Input and output safety

The original unanchored URL expression accepted
`javascript:alert(1)//https://example.org/model`. Model validation now parses the
entire value and requires HTTP/HTTPS plus a host. Existing invalid values render
as escaped text in both portals instead of executable links.

Model-file HTML now uses an escaped shared ERB partial for job and catalog
previews. This also preserves filenames containing literal HTML entities.
Active Storage already sanitizes markup characters in filenames; this change
does not claim a demonstrated filename-based script exploit.

## Verification and limits

- Baseline: 80 tests, 371 assertions. Final suite with `CI=1`: 93 tests,
  470 assertions, no failures, errors, or skips.
- Original application code fails the six regression checks covering growing
  portal query counts, URL validation, executable legacy links in both portals,
  and literal filename rendering. Revised code passes.
- `bundle check`, Zeitwerk eager loading, production-mode asset compilation,
  and production-mode `/up` (HTTP 200) pass. Production-mode checks use the local
  test database, a dummy secret, and disabled outbound email.
- Bundler Audit: no reported vulnerable gems, advisory database commit
  `516ea4757d5eec778c49af8371c23309c4b70f42` (November 4).
- Brakeman 8.1.0: no warnings or errors.
- Both Chrome/Playwright regressions pass: compiled jQuery UI positioning/XSS
  guard and stats chart loading during Turbo navigation, filtering, Back, and
  reload. The vendored jQuery UI security override remains necessary.
- `git diff --check` passes. No repository lint configuration exists.

Live Google login, Mailgun delivery, reCAPTCHA, Linux builds, and production
data were not exercised. Existing RailsAdmin deprecation warnings remain.
The SassC and Three.js migrations described in the September audit remain
separate work. No database migration or new runtime configuration is required.

## Primary references

- [Ruby 3.4.12 release](https://www.ruby-lang.org/en/news/2026/10/23/ruby-3-4-12-released/)
- [Rails 8.1.4.1 security release](https://rubyonrails.org/2026/11/4/Rails-8.0.5.2-and-8.1.4.1-have-been-released)
- [Crass security advisory](https://github.com/rgrove/crass/security/advisories/GHSA-pq4g-8rxf-4g29)
