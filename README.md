# MAKEatTADL

**A full-featured 3D Print Job Management Platform for Public Libraries**

[![Ruby](https://img.shields.io/badge/Ruby-3.4.12-red)](https://www.ruby-lang.org)
[![Rails](https://img.shields.io/badge/Rails-8.1.4.1-red)](https://rubyonrails.org/)

---

MAKEatTADL is a web application developed by [Traverse Area District Library (TADL)](https://www.tadl.org) for managing 3D print requests from patrons and staff. The platform streamlines communication, estimation, and fulfillment of 3D printing jobs, designed for real-world use in public libraries.

---

## Table of Contents

- [Features](#features)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
  - [Configuration](#configuration)
  - [Development](#development)
- [Usage](#usage)
  - [Submitting a Print Job](#submitting-a-print-job)
  - [Staff Workflow](#staff-workflow)
  - [Admin Panel](#admin-panel)
- [Architecture](#architecture)
- [Deployment](#deployment)
- [Contributing](#contributing)
- [License](#license)
- [Credits](#credits)

---

## Features

- 🖨️ **Patron Print Requests** – Forms for library patrons to submit print and scan requests, including STL and 3MF model uploads.
- 🗨️ **Conversation Thread** – Messaging system for patron/staff communication per job.
- 🏷️ **Status Tracking** – Granular status management: *pending*, *information requested*, *response received*, *approved*, *in progress*, *ready for pickup*, *cancelled*... Statuses are a model, you can add more as needed.
- 💰 **Cost Estimation** – Staff can provide filament/cost/time estimates and request patron approval.
- 🏢 **Staff Workspace** – Custom Rails and Tailwind interface for jobs, patron conversations, reporting, configuration, and staff permissions.
- 📁 **Model Library** – Searchable reusable models with preview images, files, printing notes, and linked job history.
- 📨 **Email Notifications** – Automated notifications for key status changes and messages.
- 🔒 **Google OAuth** – Secure staff login via Google Workspace SSO.
- 🗄️ **File Storage** – All print files handled by ActiveStorage, configurable for local or S3.
- ✨ **Accessible UI** – Simple, mobile-friendly design for patrons and staff.

---

## Getting Started

### Prerequisites

- **Ruby**: 3.4.12 (use [rbenv](https://github.com/rbenv/rbenv) or [asdf](https://asdf-vm.com/))
- **Rails**: 8.1.4.1
- **PostgreSQL**: Use a [currently supported release](https://www.postgresql.org/support/versioning/).
- **Assets**: Importmap/Sprockets JavaScript and the bundled Tailwind CLI; no npm/Yarn install is required for the app.
- **ImageMagick**: For image processing (used by ActiveStorage)
- **libvips**: (optional, for faster image handling)

#### Recommended Dev Tools

- [Docker](https://www.docker.com/)
- [dotenv](https://github.com/bkeepers/dotenv) (for `.env` support)

---

### Installation

Clone the repo:

```sh
git clone https://github.com/tadl/MAKEatTADL.git
cd MAKEatTADL
```

Install the locked Ruby dependencies and build the staff stylesheet:

```sh
bundle install
bin/rails tailwindcss:build
```

Set up the database:

```sh
bin/rails db:setup
```

`db:setup` seeds only required reference data. After logging in to `/admin`,
create operational records for your installation:

- Add at least one active pickup location, with the scanner/FDM/resin flags that
  match the services available there.
- Add any printers that should be assignable to jobs.
- Add or deactivate filament colors beyond the seeded black and white defaults.

---

### Configuration

**Environment Variables**

Copy `.env.example` to `.env` and configure the services used by your installation.
Use your own values; never commit `.env` or credentials. Staff authentication
requires the Google client settings and an allowed Workspace domain:

```env
GOOGLE_CLIENT_ID=your-google-oauth-client-id
GOOGLE_CLIENT_SECRET=your-google-oauth-client-secret
GOOGLE_DOMAIN=example.org
MAILGUN_DOMAIN=your.mailgun.domain
MAILGUN_API_KEY=your-mailgun-api-key
RAILS_MASTER_KEY=your-master-key
SECRET_KEY_BASE=your-secret-key
```

**Google OAuth Setup**

- Go to Google Cloud Console.
- Create OAuth2 Credentials.
- Set authorized redirect URI to:  
  `https://<your-domain>/auth/google_oauth2/callback`
- Fill in `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, and `GOOGLE_DOMAIN` in your `.env`.
- Staff accounts are created through verified Google login. Administrator roles
  are managed separately; there is no local password-based admin login.

**Mail Configuration**

- Outbound email is used for notifications.
- Fill in Mailgun API credentials in `.env`.

**ActiveStorage**

- Default: local storage (`storage/` dir)
- An S3 configuration can be added in `config/storage.yml` and selected in the
  appropriate Rails environment. The repository currently configures disk services.

---

### Development

Start Rails and the Tailwind watcher together:

```sh
bin/dev
```

The launcher installs Foreman for the current Ruby if needed. Both processes
stop with Ctrl-C. The default port is 3000; use `bin/dev -p 3001` to change it.

Visit [the public site](http://localhost:3000) or
[the staff workspace](http://localhost:3000/admin). See
[admin development](docs/admin-development.md) for branch iteration, synthetic
previews, and the scope of the first port.

---

## Usage

### Submitting a Print Job (Patron Workflow)

1. Patron fills out the print job request form, uploads 3D model.
2. Staff are notified and review the submission.
3. Staff can communicate with patron via job message thread for clarification or updates.
4. Staff estimate cost/time/materials and request approval.
5. Patron approves/rejects; job moves to next stage.
6. Staff assign job to printer, set status, and track progress.
7. When job is done, staff mark as *ready*; patron is notified for pickup.

### Staff Workflow

Public scan requests are available whenever at least one active Pickup Location
has **Scanner** enabled. To pause scanning, clear **Scanner** on every active
location in the admin interface. Public scanning links and promotional wording
disappear, and bookmarked scan forms or stale submissions are blocked. Enable
**Scanner** on an active location to restore requests without a deployment.
Existing scan jobs, conversations, and files remain available while scanning is
paused. An inactive location does not enable the service.

- Log in via Google SSO.
- View, filter, and manage all jobs.
- Use the custom workspace for job details, files, patron records, and administration.
- Communicate with patrons via messages.
- Track metrics and status of all jobs.
- Download and prepare print files.

### Admin Panel

- Available at `/admin`.
- Requires staff login.
- Staff can update existing jobs, exchange messages, manage job files, update
  patron contact details, and read the model library and statistics.
- Administrators also create/delete records, manage configuration and staff
  roles, merge patrons, and inspect the activity log.
- See [permissions](docs/admin-permissions.md) for the enforced access matrix and
  [the port inventory](docs/admin-port-inventory.md) for workflow/automation coverage.

---

## Architecture

- **Rails 8.1** app, retaining the established Rails 7.1 configuration defaults.
- **ActiveStorage** for all file uploads (optionally S3).
- **OmniAuth** for Google OAuth2 staff authentication.
- **Custom Rails controllers and ERB views** for the staff workspace.
- **Tailwind CSS 4** for staff styling, with the existing Bootstrap public portal.
- **CanCanCan** for server-side authorization and **Stimulus/Turbo** for interactions.
- **PostgreSQL** database.

Directory layout:
```
app/
  controllers/
  models/
  views/
  jobs/
  mailers/
  services/
  ...
config/
db/
test/
docs/
```

---

## Deployment

- Supports standard Heroku/Dokku-style deployment.
- Tailwind is built as part of the Rails asset-precompilation task. Verify the
  asset build and normal release checks before an explicitly authorized deployment.
- Do not run `db:seed` as part of normal production deploys. Seeds are intended
  for initial reference data only; pickup locations, printers, and most filament
  colors are managed in `/admin`.
- For persistent storage with Docker, map `storage/` to a volume or use S3.

**Environment Checklist:**
- All required env vars set
- DB running and linked
- Storage configured
- OAuth and Mailgun (or SMTP) set

---

## Contributing

Run the Rails suite against the local test database:

```sh
RAILS_ENV=test DATABASE_URL=postgresql:///make_at_tadl_test RBENV_VERSION=3.4.12 rbenv exec bundle exec rails test
```

Check the staff asset build using the same local test environment:

```sh
RAILS_ENV=test DATABASE_URL=postgresql:///make_at_tadl_test RBENV_VERSION=3.4.12 rbenv exec bundle exec rails assets:precompile
```

See [admin development](docs/admin-development.md) for the custom workspace's
verification workflow. [The November maintenance review](docs/maintenance-2026-11-04.md)
and [the dependency audit](docs/dependency-audit-2026-09-10.md) record historical
checks; their RailsAdmin-specific checks apply to the former interface.

With assets precompiled, Playwright available to Node, and Google Chrome
installed, run `node test/browser/stats_navigation_test.cjs` to check chart
loading during Turbo navigation, filtering, Back navigation, and reload.
This check renders the custom workspace with synthetic data using the local test
database. It checks delayed Chart.js loading, chart cleanup, narrow layouts,
and the readable fallback when charts are unavailable.

Run `node test/browser/admin_layout_test.cjs` against an empty local test
database to check the main staff screens at desktop and mobile widths, model
library navigation, and STL preview controls using synthetic data.
See [the port verification record](docs/admin-verification-2026-11-17.md) for
the initial branch checks and remaining live-validation limits.

1. Fork the repo and clone your fork.
2. Create a feature branch: `git checkout -b my-feature`
3. Run tests and ensure code passes linter.
4. Open a pull request with a detailed description.

PRs are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) if available.

---

## License

[MIT](LICENSE)

---

## Credits

- Developed by Traverse Area District Library Technology Team
- Built with [Ruby on Rails](https://rubyonrails.org/)
- ChatGPT was used to assist with development.

---

*This project is community-driven and open to other libraries!*
