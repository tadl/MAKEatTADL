# MAKE at TADL

**A 3D-printing & scanning request portal for the Traverse Area District Library (TADL).**
MAKE at TADL lets patrons submit jobs, tracks status from “pending” through “ready for pickup,” and gives staff a beautiful RailsAdmin dashboard to manage the queue.

---

## 🚀 Features

- **Multi-step request forms** for 3D printing, scanning, fidget and assistive-tech devices, and staff jobs
- **reCAPTCHA** integration to block bots
- **Mailgun API** for reliable transactional email (job confirmations & notifications)
- **Google OAuth** for staff logins
- **Role-based UI**: patrons vs. staff, with a dedicated RailsAdmin console
- **Job status lifecycle**: pending → information\_requested → queued → in\_progress → ready\_for\_pickup → archived
- **Custom scopes** (active/inactive) to keep past jobs tidy
- **Active Storage** file uploads (STL models, object photos, etc.)
- **Rich job detail pages** with slicer metrics, cost estimates, and messaging

---

## 📦 Tech Stack

- **Ruby on Rails** 7.1
- **PostgreSQL** (production & development)
- **RailsAdmin** for the staff console
- **Stimulus / Bootstrap 5** for interactive forms & layout
- **Active Storage** (local or cloud-backed) for file uploads
- **Sidekiq / ActiveJob** for mail delivery

---

## 🔧 Quickstart

### Prerequisites

- Ruby 3.2.x
- PostgreSQL 14+
- Node.js & Yarn
- Redis (for ActiveJob/Sidekiq, optional)
- Mailgun account
- Google Cloud OAuth credentials
- reCAPTCHA v2 keys

### Clone & Install

```bash
git clone https://github.com/tadl/MAKEatTADL.git
cd MAKEatTADL

# Ruby gems
bundle install

# JS/CSS packages
yarn install
```

### Environment

Copy and edit the example:

```bash
cp .env.example .env
```

Fill in your:

- `MAILGUN_API_KEY` & `MAILGUN_DOMAIN`
- `RECAPTCHA_SITE_KEY` & `RECAPTCHA_SECRET_KEY`
- `GOOGLE_CLIENT_ID` & `GOOGLE_CLIENT_SECRET` & `GOOGLE_DOMAIN`
- `APP_PUBLIC_HOST` (e.g. `https://make.tadl.org`)

### Database

```bash
rails db:create db:migrate db:seed
```

### Start the App

```bash
rails server
# → http://localhost:3000
```

Staff console sits at `/admin`. Sign in via Google.

---

## 🚢 Deployment

We deploy to Dokku (or your favorite PaaS). Make sure:

- Env vars match `.env.example`
- A Postgres add-on is attached
- Active Storage is configured for S3 (or local)

---

## 🤝 Contributing

1. Fork
2. Create a feature branch (`git checkout -b feature/foo`)
3. Commit changes (`git commit -m 'Add foo'`)
4. Push and open a Pull Request

Please follow the [Rails Style Guide] and include tests for new features.

---

*Made with ♥ by the TADL Tech Team*

