require "test_helper"

class InboundMailgunTest < ActionDispatch::IntegrationTest
  def signed_mailgun_params(overrides = {})
    timestamp = overrides.delete(:timestamp) || Time.current.to_i.to_s
    token = overrides.delete(:token) || SecureRandom.hex(8)
    signing_key = ENV.fetch("MAILGUN_WEBHOOK_SIGNING_KEY", "test-signing-key")
    signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key, "#{timestamp}#{token}")

    {
      recipient: @recipient,
      "body-plain" => "Hello from email\n\nOn Fri ... wrote:",
      from: @patron.email,
      timestamp: timestamp,
      token: token,
      signature: signature
    }.merge(overrides)
  end

  setup do
    ensure_base_lookups!
    @patron = create_patron
    @job = create_print_job(patron: @patron)
    @recipient = "make+#{@job.conversation.conversation_token}@example.com"
  end

  test "mailgun inbound webhook requires a configured signing key" do
    with_env("MAILGUN_WEBHOOK_SIGNING_KEY" => nil, "MAILGUN_SIGNING_KEY" => nil) do
      post "/inbound/mailgun", params: signed_mailgun_params
      assert_response :service_unavailable
    end
  end

  test "mailgun inbound webhook accepts valid signatures" do
    with_env("MAILGUN_WEBHOOK_SIGNING_KEY" => "test-signing-key") do
      assert_difference -> { @job.conversation.messages.count }, 1 do
        post "/inbound/mailgun", params: signed_mailgun_params
      end

      assert_response :success
      assert_match(/\AHello from email/, @job.conversation.messages.order(:created_at).last.body)
    end
  end

  test "mailgun inbound webhook rejects replayed deliveries" do
    with_env("MAILGUN_WEBHOOK_SIGNING_KEY" => "test-signing-key") do
      params = signed_mailgun_params(timestamp: Time.current.to_i.to_s, token: "repeat-token")

      post "/inbound/mailgun", params: params
      assert_response :success

      post "/inbound/mailgun", params: params
      assert_response :unauthorized
    end
  end

  test "mailgun inbound webhook rejects mismatched sender email" do
    with_env("MAILGUN_WEBHOOK_SIGNING_KEY" => "test-signing-key") do
      post "/inbound/mailgun", params: signed_mailgun_params(from: "someone@example.org")
      assert_response :unauthorized
    end
  end
end
