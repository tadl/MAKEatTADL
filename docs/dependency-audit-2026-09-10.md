# Dependency audit — 2026-09-10

## Scope and baseline

Reviewed the application, Gemfile/lockfile, Ruby pin, importmap, CDN tags,
RailsAdmin's vendored JavaScript, tests, initializers, Procfile, and Dokku
`app.json`. The starting checkout was clean at `03ac3de`.
There is no tracked CI workflow, Dockerfile, package.json, or npm/Yarn lockfile.
Dokku uses buildpacks; its predeploy migration hook and nightly maintenance
schedule are unchanged. No production access, deployment, migrations, or
outbound patron messages were performed during this audit.

Ruby **3.4.10**, Rails **8.1.3.1**, Puma **7.2.1**, and Bundler **2.6.9** remain
unchanged. The Ruby pin and lockfile agree. Ruby 3.4 is in normal maintenance;
Rails 8.1 is supported. These are published releases, and the requested Ruby
and Rails versions were already installed. The existing Rails 7.1 configuration
defaults are intentionally retained.

Baseline checks passed: **70 tests, 260 assertions**, Zeitwerk eager loading,
production-mode asset compilation, Bundler Audit 0.9.3, and Brakeman 8.0.6
(zero warnings/errors). No pre-existing test or build failures were observed.
Existing RailsAdmin/ActiveSupport deprecation warnings remain. Production-mode
checks used the local test database, a dummy secret, and disabled Mailgun.

## Changes and security findings

| Dependency | Before | After | Reason |
| --- | --- | --- | --- |
| omniauth-google-oauth2 | 1.2.1 | 1.2.3 | Validate direct ID-token signatures and bind claims to the access-token owner |
| omniauth | 2.1.3 | 2.1.4 | Compatible maintenance patch; upstream tests Ruby 3.4 |
| bootstrap gem | 5.3.5 | 5.3.8 | CSS/accessibility and interaction fixes |
| Public Bootstrap CSS | 5.3.7 | 5.3.8 | Match gem version; update verified SHA-384 integrity hash |
| importmap-rails | 2.1.0 | 2.2.3 | Import-map resolution fixes |
| turbo-rails | 2.0.16 | 2.0.23 | Refresh bundled Turbo JavaScript/dependencies |
| Chart.js | 4.4.0 importmap; unversioned stats script | 4.5.1 in both | Reproducible loading, maintenance fixes, integrity hash on stats script |
| RailsAdmin jQuery UI Position | 1.12.1 | 1.12.1 + upstream security backport | CVE-2021-41184 |

The Google strategy security release was **not reported by Bundler Audit**.
Its upstream release notes describe forged or mismatched caller-supplied ID
tokens populating `extra.id_info`. User identity/email from Google's userinfo
endpoint were not affected by that flaw. The app uses claims from this auth
hash, so this update is relevant even though normal browser login uses an
authorization code. No login bypass in this application is claimed.
The Gemfile now requires at least 1.2.3 within the existing 1.x series.

RailsAdmin 3.3.0 is current, but its Sprockets bundle contains jQuery UI 1.12.1.
The positioning utility interprets an `of` string as HTML, allowing script
execution if the caller supplies untrusted input (CVE-2021-41184). No such
application input path was identified. The narrow vendored asset override
backports the official selector-only fix without changing other widgets.
The browser regression reproduces execution with the original upstream asset
and rejects it with the compiled patched asset, while preserving normal
positioning. See the adjacent vendor README for provenance and removal criteria.

OSV also reports jQuery UI datepicker/checkboxradio advisories
(CVE-2021-41182, CVE-2021-41183, CVE-2022-31160), but those components are not
included in RailsAdmin's shipped subset. They were not counted as application
fixes. RailsAdmin's separate Bootstrap 5.1.3, jQuery 3.6.0, and flatpickr 4.6.11
assets are unchanged; updating the bootstrap gem does not replace its vendored
Bootstrap. The direct CDN libraries and these embedded libraries were checked
separately from Bundler.

Pagy is now constrained to `~> 9.3` to preserve `Pagy::Backend`,
`Pagy::Frontend`, and `pagy/extras/bootstrap` usage during future resolution.
README runtime/setup instructions now match the actual stack.

## Verification

- Full suite with eager loading (`CI=1`): **75 tests, 276 assertions**, no
  failures/errors/skips. Covers patron magic links and ownership, staff access,
  uploads, mail rendering, signed inbound webhooks/replay rejection, job
  transitions, nightly delivery/failure behavior, and filtered reports.
- Five new OAuth tests exercise the real strategy and JWT verification using
  synthetic Google HTTP responses: authorization-code login, valid direct
  token, forged signature, mismatched subject, and unverified email.
- `bundle check`, Zeitwerk, production-mode boot and `/up` (HTTP 200), and
  production-mode asset compilation passed.
- Bundler Audit: no reported vulnerable gems, using ruby-advisory-db commit
  `93b32f641f84282183ce58ab1d7204bee50885bd` (updated September 8).
- Brakeman 8.0.6: zero warnings/errors. No repository lint configuration exists;
  an unrelated formatting rewrite was not introduced.
- Chrome 153 browser checks passed against Rails-rendered synthetic pages and
  compiled assets: three stats charts, desktop/mobile layouts, upload control,
  public home/form, and Turbo loading; no uncaught JavaScript errors. Google
  reCAPTCHA's real-domain validation is not exercised by this local preview.
- The committed Playwright regression checks the **compiled** RailsAdmin asset,
  ensuring the Sprockets override is actually loaded and blocks the XSS payload.
- CDN integrity hashes were calculated from the exact versioned response bytes
  and accepted by Chrome. `git diff --check` passed.

Run the Rails checks with the pinned Ruby:

```sh
RAILS_ENV=test DATABASE_URL=postgresql:///make_at_tadl_test CI=1 RBENV_VERSION=3.4.10 rbenv exec bundle exec rails test
RAILS_ENV=test DATABASE_URL=postgresql:///make_at_tadl_test RBENV_VERSION=3.4.10 rbenv exec bundle exec rails zeitwerk:check
RAILS_ENV=production DATABASE_URL=postgresql:///make_at_tadl_test SECRET_KEY_BASE_DUMMY=1 MAILGUN_API_KEY= MAILGUN_DOMAIN= RBENV_VERSION=3.4.10 rbenv exec bundle exec rails assets:precompile
RBENV_VERSION=3.4.10 rbenv exec bundler-audit check --update
RBENV_VERSION=3.4.10 rbenv exec brakeman --no-pager
```

Bundler Audit and Brakeman are developer tools installed separately from the
application bundle. The optional browser regression requires Playwright and
Google Chrome; it adds no production dependency. After asset compilation, run
`node test/browser/jquery_ui_position_test.cjs` with Playwright on Node's module
path. This audit used the desktop's bundled Playwright through `NODE_PATH`;
set that variable to your shared Node module directory if Playwright is not
installed locally.

## Deferred work and verification limits

- **SassC/LibSass is end-of-life.** It compiles trusted application/admin SCSS
  during builds, not uploaded patron models. Migrating to Dart Sass requires
  checking RailsAdmin's Sprockets integration and differing Sass semantics;
  treat it as a separate build migration with visual comparisons.
- **Three.js r134 is old.** Its global `STLLoader`/`OrbitControls` APIs are used
  by the model viewer. Current versions require ES modules and other viewer
  changes; defer that migration. OSV reported no advisory for 0.134.0, which is
  not a guarantee of safety. A real WebGL/STL interaction test remains needed.
- Major updates to Pagy, Puma, image_processing, JSON, Marcel, OpenSSL, and
  omniauth-rails_csrf_protection were not attempted just to reach the newest
  release. Existing APIs/runtime constraints remain in place. Rack 3.2.6
  already includes the reviewed Rack security fixes; 3.2.7 restores old Ruby
  compatibility and adds no identified benefit on Ruby 3.4.
- Other maintenance-only updates remain available (for example pg, bootsnap,
  Mailgun, Sprockets, dotenv, recaptcha, and transitive mail/native gems).
  `bundle outdated --parseable` inventories these; outdated is not synonymous
  with vulnerable. No additional matching gem advisories were found.
- Google OAuth responses were simulated, not an actual account login. Live
  Mailgun delivery, reCAPTCHA, provider availability, production data, Linux
  native builds, system PostgreSQL/OpenSSL/libvips/ImageMagick packages, and
  production scheduler execution were not verified. There is no tracked CI
  pipeline, and no remote pipeline was invoked.

## Deployment

Deploy through the existing Dokku process when ready. No new configuration,
database migration, or data repair is required by these changes. The ordinary
asset precompile must run so the patched admin JavaScript is served. The
existing predeploy hook remains unchanged. After deployment, smoke-test Google
staff login, Stats charts, a scan-file upload, and patron submission/login.

## Primary references

- [Ruby 3.4.10 release](https://www.ruby-lang.org/en/news/2026/06/30/ruby-3-4-10-released/) and [Ruby maintenance branches](https://www.ruby-lang.org/en/downloads/branches/).
- [Rails 8.1.3.1 security release](https://rubyonrails.org/2026/7/29/Rails-Versions-7-2-3-2-8-0-5-1-and-8-1-3-1-have-been-released) and [maintenance policy](https://guides.rubyonrails.org/maintenance_policy.html).
- [Google OAuth strategy 1.2.3 security notes](https://github.com/zquestz/omniauth-google-oauth2/releases/tag/v1.2.3).
- [jQuery UI positioning advisory](https://github.com/jquery/jquery-ui/security/advisories/GHSA-gpqq-952q-5327) and [fixed upstream component](https://github.com/jquery/jquery-ui/blob/1.13.0/ui/position.js).
- [Bootstrap 5.3.8](https://github.com/twbs/bootstrap/releases/tag/v5.3.8), [Turbo Rails 2.0.23](https://github.com/hotwired/turbo-rails/releases/tag/v2.0.23), [Importmap Rails 2.2.3](https://github.com/rails/importmap-rails/releases/tag/v2.2.3), and [Chart.js 4.5.1](https://github.com/chartjs/Chart.js/releases/tag/v4.5.1).
- [Rack changelog](https://github.com/rack/rack/blob/v3.2.7/CHANGELOG.md), [LibSass end-of-life](https://sass-lang.com/blog/libsass-is-end-of-life/), and [Three.js migration guide](https://github.com/mrdoob/three.js/wiki/Migration-Guide).
