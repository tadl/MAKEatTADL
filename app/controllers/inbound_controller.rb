# app/controllers/inbound_controller.rb
class InboundController < ActionController::API
  require 'email_reply_parser'
  WEBHOOK_TTL = 15.minutes

  # pull in the Rails CSRF protection callbacks
  include ActionController::RequestForgeryProtection

  # use the normal exception strategy everywhere…
  protect_from_forgery with: :exception

  # …but turn it off for Mailgun’s inbound webhook
  skip_before_action :verify_authenticity_token, only: :mailgun

  # POST /inbound/mailgun
  def mailgun
    return head :service_unavailable unless webhook_signing_key.present?
    return head :unauthorized unless valid_mailgun_signature?

    recipient   = params[:recipient]
    raw_body    = params['body-plain']
    from_header = params[:from]
    cleaned     = EmailReplyParser.parse_reply(raw_body)

    # 1) extract conversation token
    token = recipient[/\Amake\+([^@]+)@/, 1]
    return head :bad_request unless token

    # 2) find the conversation
    conversation = Conversation.find_by(conversation_token: token)
    return head :not_found unless conversation

    # 3) parse out actual email address of sender
    #    Mailgun gives `"Name <email@domain>"` in `params[:from]`
    from_email = Mail::Address.new(from_header).address rescue nil
    return head :bad_request unless from_email

    # 4) ensure that this email belongs to the patron on this conversation’s job
    job    = conversation.job
    patron = job.patron
    unless patron.email.downcase == from_email.downcase
      return head :unauthorized
    end

    # 5) build the inbound message
    conversation.messages.create!(
      body:        cleaned,
      author:      patron
    )

    head :ok
  end

  private

  def webhook_signing_key
    ENV["MAILGUN_WEBHOOK_SIGNING_KEY"].presence || ENV["MAILGUN_SIGNING_KEY"].presence
  end

  def valid_mailgun_signature?
    timestamp = params[:timestamp].to_s
    token     = params[:token].to_s
    signature = params[:signature].to_s
    return false if timestamp.blank? || token.blank? || signature.blank?
    return false if webhook_timestamp_expired?(timestamp)
    return false if replayed_mailgun_token?(timestamp, token)

    digest = OpenSSL::HMAC.hexdigest("SHA256", webhook_signing_key, "#{timestamp}#{token}")
    ActiveSupport::SecurityUtils.secure_compare(digest, signature)
  rescue
    false
  end

  def webhook_timestamp_expired?(timestamp)
    issued_at = Time.zone.at(timestamp.to_i)
    issued_at < WEBHOOK_TTL.ago || issued_at > 5.minutes.from_now
  rescue
    true
  end

  def replayed_mailgun_token?(timestamp, token)
    cache_key = "mailgun:webhook:#{timestamp}:#{token}"
    return true if Rails.cache.exist?(cache_key)

    Rails.cache.write(cache_key, true, expires_in: 1.day)
    false
  end
end
