require "test_helper"

class AdminStatsTest < ActionDispatch::IntegrationTest
  setup do
    @staff = create_staff_user(email: "stats@tadl.org")
    ensure_pickup_location(code: "east_bay", name: "East Bay")
    sign_in_staff(@staff)
  end

  test "stats has its own navigation page with a location filter" do
    get rails_admin.dashboard_path

    assert_response :success
    assert_select "a[href='#{rails_admin.stats_path}']", text: "Stats"
    assert_select "h3", text: /3D Print Stats/, count: 0

    get rails_admin.stats_path

    assert_response :success
    assert_select "select[name='location'] option[selected][value='']", text: "All Locations"

    get rails_admin.stats_path(location: "east_bay")

    assert_response :success
    assert_select "h3", text: /3D Print Stats/
    assert_select "select[name='location'] option[selected][value='east_bay']", text: "East Bay"
    assert_select "select[name='location'] option[value='']", text: "All Locations"
    assert_select "a[href*='location=east_bay']", text: "Last 7 Days"
  end

  private

  def sign_in_staff(staff)
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: staff.uid,
      info: {
        email: staff.email,
        name: staff.name,
        image: "https://example.test/avatar.png"
      },
      extra: {
        id_info: {
          hd: "tadl.org",
          email_verified: true
        }
      }
    )

    with_env("GOOGLE_DOMAIN" => "tadl.org") do
      get "/auth/test/callback", env: { "omniauth.auth" => auth }
    end
  end
end
