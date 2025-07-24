# MAKEatTADL

**A full-featured 3D Print Job Management Platform for Public Libraries**

[![Ruby](https://img.shields.io/badge/Ruby-3.2.8-red)](https://www.ruby-lang.org)
[![Rails](https://img.shields.io/badge/Rails-7.1.3.3-red)](https://rubyonrails.org/)

---

MAKEatTADL is a web application developed by [Traverse Area District Library (TADL)](https://www.tadl.org) for managing 3D print requests from patrons and staff. The platform streamlines communication, estimation, and fulfillment of 3D printing jobs, designed for real-world use in public libraries.

---

## Table of Contents

- [Features](#features)
- [Screenshots](#screenshots)
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

- 🖨️ **Patron Print Requests** – Simple form for library patrons to submit 3D print jobs, including file uploads (STL, OBJ, ZIP).
- 🗨️ **Conversation Thread** – Messaging system for patron/staff communication per job.
- 🏷️ **Status Tracking** – Granular status management: *pending*, *information requested*, *response received*, *approved*, *in progress*, *ready for pickup*, *cancelled*... Statuses are a model, you can add more as needed.
- 💰 **Cost Estimation** – Staff can provide filament/cost/time estimates and request patron approval.
- 🏢 **Admin UI** – RailsAdmin-based staff portal full oversight, configuration, user/staff management.
- 📨 **Email Notifications** – Automated notifications for key status changes and messages.
- 🔒 **Google OAuth** – Secure staff login via Google Workspace SSO.
- 🗄️ **File Storage** – All print files handled by ActiveStorage, configurable for local or S3.
- ✨ **Accessible UI** – Simple, mobile-friendly design for patrons and staff.

---

## Screenshots

> *(Add actual screenshots here when available)*

![Patron Print Request](docs/screenshots/patron-request.png)
![Admin Dashboard](docs/screenshots/admin-dashboard.png)

---

## Getting Started

### Prerequisites

- **Ruby**: 3.2.8 (use [rbenv](https://github.com/rbenv/rbenv) or [asdf](https://asdf-vm.com/))
- **Rails**: 7.1.3.3
- **PostgreSQL**: 13+
- **Redis**: For Sidekiq jobs/queues
- **Node.js & Yarn**: For JS dependencies
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

Install Ruby gems and JS dependencies:

```sh
bundle install
yarn install
```

Set up the database:

```sh
bin/rails db:setup
```

---

### Configuration

**Environment Variables**

Copy `.env.example` to `.env` and fill in the following at minimum:

```env
GOOGLE_CLIENT_ID=your-google-oauth-client-id
GOOGLE_CLIENT_SECRET=your-google-oauth-client-secret
DEFAULT_ADMIN_EMAIL=admin@yourdomain.org
DEFAULT_ADMIN_PASSWORD=changeme
MAILGUN_DOMAIN=your.mailgun.domain
MAILGUN_API_KEY=your-mailgun-api-key
RAILS_MASTER_KEY=your-master-key
SECRET_KEY_BASE=your-secret-key
```

**Google OAuth Setup**

- Go to Google Cloud Console.
- Create OAuth2 Credentials.
- Set authorized redirect URI to:  
  `https://<your-domain>/users/auth/google_oauth2/callback`
- Fill in `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` in your `.env`.

**Mail Configuration**

- Outbound email is used for notifications.
- Fill in Mailgun API credentials in `.env`.

**ActiveStorage**

- Default: local storage (`storage/` dir)
- For S3, update `config/storage.yml` and set `STORAGE_SERVICE=amazon`.

---

### Development

- Start the Rails server:  
  `bin/rails server`

Visit [http://localhost:3000](http://localhost:3000) to get started.

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

- Log in via Google SSO.
- View, filter, and manage all jobs.
- Use the RailsAdmin panel for advanced management.
- Communicate with patrons via messages.
- Track metrics and status of all jobs.
- Download and prepare print files.

### Admin Panel

- Available at `/admin`.
- Requires staff login.
- Manage users, jobs, printers, statuses, and more.
- All models manageable via RailsAdmin UI.

---

## Architecture

- **Rails 7** app, modular design.
- **ActiveStorage** for all file uploads (optionally S3).
- **OmniAuth** for Google OAuth2 staff authentication.
- **RailsAdmin** for administrative interface.
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
spec/
docs/
```

---

## Deployment

- Supports standard Heroku/Dokku-style deployment (`git push dokku ...`)
- Run database migrations after deploy:  
  `bin/rails db:migrate`
- For persistent storage with Docker, map `storage/` to a volume or use S3.

**Environment Checklist:**
- All required env vars set
- DB running and linked
- Storage configured
- OAuth and Mailgun (or SMTP) set

---

## Contributing

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
