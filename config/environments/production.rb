require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for threaded/concurrent performance.
  config.eager_load = true

  # Full error reports are disabled; caching is on.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Do not fall back to assets pipeline if a precompiled asset is missed.
  config.assets.compile = false

  # Store uploaded files on the local file system.
  config.active_storage.service = :local

  # Assume SSL is terminated at the proxy, and enforce HTTPS + secure cookies.
  config.assume_ssl = true
  config.force_ssl  = true

  # Log to STDOUT by default.
  config.logger = ActiveSupport::Logger.new(STDOUT)
    .tap  { |logger| logger.formatter = ::Logger::Formatter.new }
    .then { |logger| ActiveSupport::TaggedLogging.new(logger) }

  # Prepend all log lines with the following tags.
  config.log_tags = [:request_id]

  # Log level (info by default; set RAILS_LOG_LEVEL env to override).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Action Mailer: don't raise on bad addresses, but build links with the right host/proto.
  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = {
    host:     ENV.fetch("APP_HOST",     "make.tadl.org"),
    protocol: ENV.fetch("APP_PROTOCOL", "https")
  }

  # All other URL helpers (job_url, edit_user_url, etc.) should also use the same host/proto.
  Rails.application.routes.default_url_options = {
    host:     ENV.fetch("APP_HOST",     "make.tadl.org"),
    protocol: ENV.fetch("APP_PROTOCOL", "https")
  }

  # Enable locale fallbacks for I18n.
  config.i18n.fallbacks = true

  # Don’t log any deprecations.
  config.active_support.report_deprecations = false

  # Don’t dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # You can uncomment and tweak the following if you need custom host-authorization:
  # config.hosts = ["make.tadl.org"]
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
