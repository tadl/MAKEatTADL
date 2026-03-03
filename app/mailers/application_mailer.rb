# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  default from:     -> { default_from_address }
  default reply_to: -> { default_reply_to_address }
  layout "mailer"

  def self.default_url_options
    Rails.application.config.action_mailer.default_url_options
  end

  private

  def mailgun_domain
    ENV["MAILGUN_DOMAIN"].presence
  end

  def default_from_address
    if mailgun_domain
      "MAKE at TADL <make@#{mailgun_domain}>"
    else
      "MAKE at TADL <no-reply@localhost>"
    end
  end

  def default_reply_to_address
    default_from_address
  end

  def conversation_reply_address(conversation)
    return default_reply_to_address unless mailgun_domain && conversation&.conversation_token.present?

    "MAKE at TADL <make+#{conversation.conversation_token}@#{mailgun_domain}>"
  end
end
