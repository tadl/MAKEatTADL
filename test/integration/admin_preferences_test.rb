require "test_helper"

class AdminPreferencesTest < ActionDispatch::IntegrationTest
  setup do
    @staff = create_staff_user
  end

  test "appearance updates require staff authentication for HTML and JSON requests" do
    patch admin_preferences_path, params: { preferences: { theme: "dark" } }
    assert_redirected_to admin_login_path

    patch admin_preferences_path, params: { preferences: { theme: "dark" } }, as: :json
    assert_redirected_to admin_login_path
    assert_equal "system", @staff.reload.theme
  end

  test "ordinary staff can persist their own theme and density without general staff edit access" do
    sign_in_staff(@staff)
    assert_not Ability.new(@staff).can?(:update, StaffUser)

    patch admin_preferences_path, params: { preferences: { theme: "dark", ui_density: "condensed" } }, as: :json

    assert_response :success
    assert_equal({ "theme" => "dark", "ui_density" => "condensed" }, JSON.parse(response.body))
    assert_equal "dark", @staff.reload.theme
    assert_equal "condensed", @staff.ui_density
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_not Ability.new(@staff).can?(:update, StaffUser)
  end

  test "a partial preference update preserves the other choice" do
    @staff.update!(theme: "dark", ui_density: "condensed")
    sign_in_staff(@staff)

    patch admin_preferences_path, params: { preferences: { theme: "light" } }, as: :json

    assert_response :success
    assert_equal({ "theme" => "light", "ui_density" => "condensed" }, JSON.parse(response.body))
  end

  test "administrators can change their own appearance" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)

    patch admin_preferences_path, params: { preferences: { theme: "light", ui_density: "normal" } }, as: :json

    assert_response :success
    assert_equal "light", @staff.reload.theme
    assert @staff.admin?
  end

  test "forged record IDs and identity attributes cannot affect another staff member or grant privileges" do
    other = create_staff_user(name: "Other Staff")
    original = @staff.attributes.slice("name", "email", "uid", "avatar_url", "admin")
    sign_in_staff(@staff)

    patch admin_preferences_path, params: {
      id: other.id, staff_user_id: other.id,
      preferences: {
        id: other.id, staff_user_id: other.id, theme: "dark", ui_density: "condensed",
        admin: true, name: "Forged Name", email: "forged@example.org", uid: "forged-uid",
        avatar_url: "https://example.org/forged.png"
      }
    }, as: :json

    assert_response :success
    assert_equal "dark", @staff.reload.theme
    assert_equal original, @staff.attributes.slice("name", "email", "uid", "avatar_url", "admin")
    assert_equal "system", other.reload.theme
    assert_equal "normal", other.ui_density
  end

  test "invalid JSON preferences return validation errors without a partial update" do
    sign_in_staff(@staff)

    patch admin_preferences_path, params: { preferences: { theme: "automatic", ui_density: "condensed" } }, as: :json

    assert_response :unprocessable_content
    assert_kind_of Array, JSON.parse(response.body).fetch("errors")
    assert_equal "system", @staff.reload.theme
    assert_equal "normal", @staff.ui_density
  end

  test "malformed preference parameter roots return bad request" do
    sign_in_staff(@staff)

    patch admin_preferences_path, params: { preferences: "dark" }, as: :json
    assert_response :bad_request

    patch admin_preferences_path, params: { preferences: ["dark"] }, as: :json
    assert_response :bad_request
    assert_equal "system", @staff.reload.theme
  end

  test "HTML preference updates return to a local referring page" do
    sign_in_staff(@staff)

    patch admin_preferences_path, params: { preferences: { theme: "light" } }, headers: { "HTTP_REFERER" => "http://www.example.com/admin/jobs?scope=all" }

    assert_redirected_to "http://www.example.com/admin/jobs?scope=all"
    assert_equal 303, response.status
    assert_equal "light", @staff.reload.theme
  end

  test "HTML preference updates ignore external referrers and redirect parameters" do
    sign_in_staff(@staff)

    patch admin_preferences_path, params: {
      preferences: { theme: "dark" }, return_to: "https://example.org/elsewhere"
    }, headers: { "HTTP_REFERER" => "https://example.org/elsewhere" }

    assert_redirected_to admin_root_path
    assert_equal 303, response.status
    assert_equal "dark", @staff.reload.theme
  end

  test "invalid HTML preferences return a useful validation error" do
    sign_in_staff(@staff)

    patch admin_preferences_path, params: { preferences: { theme: "system", ui_density: "compact" } }

    assert_response :unprocessable_content
    assert_includes response.body, "Ui density"
    assert_equal "normal", @staff.reload.ui_density
  end

  private

  def sign_in_staff(staff)
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: staff.uid,
      info: { email: staff.email, name: staff.name, image: staff.avatar_url },
      extra: { id_info: { hd: "example.org", email_verified: true } }
    )
    with_env("GOOGLE_DOMAIN" => "example.org") do
      get "/auth/test/callback", env: { "omniauth.auth" => auth }
    end
  end
end
