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

  test "appearance preferences default to system theme and normal density" do
    staff = create_staff_user

    assert_equal "system", StaffUser.new.theme
    assert_equal "normal", StaffUser.new.ui_density
    assert_equal "system", staff.reload.theme
    assert_equal "normal", staff.ui_density
  end

  test "appearance preferences accept only the supported values" do
    staff = create_staff_user

    StaffUser::THEMES.each do |theme|
      staff.theme = theme
      assert staff.valid?, staff.errors.full_messages.join(", ")
    end
    StaffUser::UI_DENSITIES.each do |density|
      staff.ui_density = density
      assert staff.valid?, staff.errors.full_messages.join(", ")
    end

    staff.theme = "automatic"
    staff.ui_density = "compact"
    assert_not staff.valid?
    assert staff.errors.added?(:theme, :inclusion, value: "automatic")
    assert staff.errors.added?(:ui_density, :inclusion, value: "compact")

    staff.theme = nil
    staff.ui_density = nil
    assert_not staff.valid?
  end

  test "database constraints enforce appearance preferences when validations are bypassed" do
    staff = create_staff_user

    [{ theme: "automatic" }, { ui_density: "compact" }, { theme: nil }, { ui_density: nil }].each do |attributes|
      assert_raises(ActiveRecord::StatementInvalid) do
        StaffUser.transaction(requires_new: true) { staff.update_columns(attributes) }
      end
    end
    assert_equal "system", staff.reload.theme
    assert_equal "normal", staff.ui_density
  end

  test "google profile refresh preserves appearance preferences" do
    staff = create_staff_user(email: "before@example.org", name: "Original Staff")
    staff.update!(theme: "dark", ui_density: "condensed")
    auth = omniauth_payload(email: "updated@example.org", hd: "example.org")
    auth.uid = staff.uid
    auth.info.name = "Updated Staff"
    auth.info.image = "https://example.org/updated-avatar.png"

    with_env("GOOGLE_DOMAIN" => "example.org") { StaffUser.from_omniauth(auth) }

    staff.reload
    assert_equal "Updated Staff", staff.name
    assert_equal "updated@example.org", staff.email
    assert_equal "https://example.org/updated-avatar.png", staff.avatar_url
    assert_equal "dark", staff.theme
    assert_equal "condensed", staff.ui_density
  end
end
