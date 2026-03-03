require "test_helper"

class StaffUserTest < ActiveSupport::TestCase
  def omniauth_payload(email:, hd: nil, email_verified: true)
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: SecureRandom.hex(8),
      info: {
        email: email,
        name: "Test Staff",
        image: "https://example.test/avatar.png"
      },
      extra: {
        id_info: {
          hd: hd,
          email_verified: email_verified
        }
      }
    )
  end

  test "authorized_google_account! accepts configured domain" do
    with_env("GOOGLE_DOMAIN" => "tadl.org") do
      assert StaffUser.authorized_google_account!(omniauth_payload(email: "user@tadl.org", hd: "tadl.org"))
    end
  end

  test "authorized_google_account! rejects other domains" do
    with_env("GOOGLE_DOMAIN" => "tadl.org") do
      error = assert_raises(StaffUser::UnauthorizedDomainError) do
        StaffUser.authorized_google_account!(omniauth_payload(email: "user@gmail.com", hd: "gmail.com"))
      end

      assert_match(/unauthorized domain/, error.message)
    end
  end

  test "authorized_google_account! rejects unverified email addresses" do
    with_env("GOOGLE_DOMAIN" => "tadl.org") do
      error = assert_raises(StaffUser::UnauthorizedDomainError) do
        StaffUser.authorized_google_account!(omniauth_payload(email: "user@tadl.org", hd: "tadl.org", email_verified: false))
      end

      assert_match(/unverified email/, error.message)
    end
  end
end
