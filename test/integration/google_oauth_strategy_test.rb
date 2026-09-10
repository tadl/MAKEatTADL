require "test_helper"
require "faraday/adapter/test"

class GoogleOauthStrategyTest < ActiveSupport::TestCase
  setup do
    @signing_key = OpenSSL::PKey::RSA.generate(2048)
    @jwk = JWT::JWK.new(@signing_key)
    @claims = {
      "iss" => "https://accounts.google.com", "aud" => "test-client",
      "exp" => 1.hour.from_now.to_i, "sub" => "test-user",
      "hd" => "example.com", "email_verified" => true
    }
    @userinfo = {
      "sub" => "test-user", "email" => "staff@example.com",
      "email_verified" => true, "hd" => "example.com", "name" => "Test Staff"
    }
    OmniAuth::Strategies::GoogleOauth2.reset_jwks_cache!
  end

  teardown do
    OmniAuth::Strategies::GoogleOauth2.reset_jwks_cache!
  end

  test "authorization code login still supplies the claims used for staff authorization" do
    authenticate("code" => "test-code")

    assert_equal "test-user", @auth.uid
    assert_equal "example.com", @auth.dig("extra", "id_info", "hd")
    assert_authorized_staff
  end

  test "a verified direct ID token for the access token owner is accepted" do
    authenticate("access_token" => "test-access-token", "id_token" => signed_token)

    assert_equal "test-user", @auth.dig("extra", "id_info", "sub")
    assert_authorized_staff
  end

  test "a forged direct ID token cannot supply staff authorization claims" do
    forged = JWT.encode(@claims.merge("hd" => "forged.example"), "test-secret", "HS256")
    authenticate("access_token" => "test-access-token", "id_token" => forged)

    assert_nil @auth.dig("extra", "id_info")
    assert_nil @auth.dig("extra", "id_token")
    assert_equal "staff@example.com", @auth.info.email
  end

  test "a signed ID token for another user cannot supply staff authorization claims" do
    authenticate("access_token" => "test-access-token", "id_token" => signed_token("sub" => "other-user"))

    assert_nil @auth.dig("extra", "id_info")
    assert_equal "test-user", @auth.uid
  end

  test "userinfo from an unverified account cannot authorize staff" do
    @userinfo["email_verified"] = false
    authenticate("access_token" => "test-access-token")

    with_env("GOOGLE_DOMAIN" => "example.com") do
      assert_raises(StaffUser::UnauthorizedDomainError) { StaffUser.authorized_google_account!(@auth) }
    end
  end

  private

  def signed_token(overrides = {})
    JWT.encode(@claims.merge(overrides), @signing_key, "RS256", kid: @jwk.kid)
  end

  def assert_authorized_staff
    with_env("GOOGLE_DOMAIN" => "example.com") do
      assert StaffUser.authorized_google_account!(@auth)
    end
  end

  def authenticate(params)
    json_headers = { "Content-Type" => "application/json" }
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post("https://oauth2.googleapis.com/token") do
        [200, json_headers, { access_token: "test-access-token", id_token: signed_token }.to_json]
      end
      stub.post("https://www.googleapis.com/oauth2/v3/tokeninfo") do
        [200, json_headers, { aud: "test-client", scope: "email profile" }.to_json]
      end
      stub.get("https://www.googleapis.com/oauth2/v3/userinfo") { [200, json_headers, @userinfo.to_json] }
      stub.get("https://www.googleapis.com/oauth2/v3/certs") do
        [200, json_headers, { keys: [@jwk.export] }.to_json]
      end
    end
    # Exercise the real strategy and JWT verification; only Google's HTTP responses are synthetic.
    app = ->(env) { @auth = env.fetch("omniauth.auth"); [200, {}, ["OK"]] }
    strategy = OmniAuth::Strategies::GoogleOauth2.new(app, "test-client", "test-secret",
      client_options: { connection_build: ->(builder) { builder.adapter :test, stubs } })
    query = Rack::Utils.build_query(params.merge("state" => "test-state"))
    env = Rack::MockRequest.env_for("https://example.com/auth/google_oauth2/callback?#{query}")
    env["rack.session"] = { "omniauth.state" => "test-state" }

    assert_equal 200, strategy.call(env).first
  end
end
