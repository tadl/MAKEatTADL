require_relative "../test_helper"

# Render real templates with synthetic data for the browser navigation regression.
# Rails' test transaction rolls back all records when this test finishes.
class StatsBrowserPagesTest < ActionDispatch::IntegrationTest
  test "export stats navigation pages" do
    directory = ENV.fetch("STATS_BROWSER_PAGES")
    ensure_base_lookups!
    staff = create_staff_user(email: "charts@example.com")
    auth = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: staff.uid,
      info: { email: staff.email, name: staff.name, image: "https://example.com/avatar.png" },
      extra: { id_info: { hd: "example.com", email_verified: true } })
    with_env("GOOGLE_DOMAIN" => "example.com") do
      get "/auth/test/callback", env: { "omniauth.auth" => auth }
    end

    get rails_admin.dashboard_path
    assert_response :success
    File.write(File.join(directory, "dashboard.html"), response.body)

    get rails_admin.stats_path
    assert_response :success
    File.write(File.join(directory, "stats.html"), response.body)

    get rails_admin.stats_path(start: Date.current.iso8601, end: Date.current.iso8601)
    assert_response :success
    File.write(File.join(directory, "filtered.html"), response.body)
  end
end
