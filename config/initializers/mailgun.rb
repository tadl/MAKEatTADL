# config/initializers/mailgun.rb
require "mailgun_rails"

if ENV["MAILGUN_API_KEY"].present? && ENV["MAILGUN_DOMAIN"].present?
  Mailgun.configure do |config|
    config.api_key = ENV.fetch("MAILGUN_API_KEY")
    config.domain  = ENV.fetch("MAILGUN_DOMAIN")
  end
else
  Rails.logger.warn "MAILGUN_API_KEY or MAILGUN_DOMAIN not set; skipping Mailgun initialization."
end
