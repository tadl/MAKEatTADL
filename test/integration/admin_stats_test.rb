require "test_helper"

class AdminStatsTest < ActionDispatch::IntegrationTest
  setup do
    @staff = create_staff_user(email: "stats@example.com")
    ensure_pickup_location(code: "east_bay", name: "East Bay")
    sign_in_staff(@staff)
  end

  test "statistics has its own navigation page and preserves the location in presets" do
    get admin_root_path
    assert_response :success
    assert_select "a[href='#{admin_stats_path}']", text: "Statistics"
    assert_select "canvas", count: 0

    get admin_stats_path
    assert_response :success
    assert_select "h1", text: "Statistics"
    assert_select "select[name='location'] option[selected][value='']", text: "All Locations"
    assert_select "[data-controller='admin-stats']", count: 1
    assert_select "canvas", count: 3

    get admin_stats_path(location: "east_bay")
    assert_response :success
    assert_select "select[name='location'] option[selected][value='east_bay']", text: "East Bay"
    assert_select "a[href*='location=east_bay']", text: "Last 7 Days"
    assert_select "details summary", text: "Daily totals"
    assert_select "details summary", text: "Filament colors"
  end

  test "statistics validates dates and location rather than returning a misleading report" do
    [
      { start: "invalid" },
      { start: "2026-02-30" },
      { start: "2026-11-17", end: "2026-11-16" },
      { start: "2000-01-01", end: "2026-11-17" },
      { location: "unconfigured" }
    ].each do |filters|
      get admin_stats_path(filters)
      assert_response :unprocessable_content
      assert_select "[role='alert']", minimum: 1
      assert_select "canvas", count: 0
    end
  end

  test "a single day report preserves metrics and escapes chart data" do
    category = ensure_category("Synthetic </script><script>alert(1)</script>")
    color_code = "</script><script>alert(1)</script>"
    job = create_print_job(attrs: { category: category, status: ensure_status("ready_for_pickup"),
      completion_date: Date.current, actual_weight: 12, quantity: 3 })
    job.update_columns(print_type_code: "fdm", filament_color: color_code)

    get admin_stats_path(start: Date.current.iso8601, end: Date.current.iso8601)

    assert_response :success
    assert_select "dt", text: "Total prints"
    assert_select "script", text: /alert\(1\)/, count: 0
    chart_element = css_select("[data-admin-stats-data-value]").first
    chart_data = JSON.parse(chart_element["data-admin-stats-data-value"])
    assert_equal [Date.current.iso8601], chart_data["labels"]
    assert_equal [3], chart_data["prints"]
    assert_equal [12.0], chart_data["filament"]
    assert_equal [color_code.titleize], chart_data["colorLabels"]
  end

  private

  def sign_in_staff(staff)
    auth = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: staff.uid,
      info: { email: staff.email, name: staff.name, image: "https://example.com/avatar.png" },
      extra: { id_info: { hd: "example.com", email_verified: true } })
    with_env("GOOGLE_DOMAIN" => "example.com") do
      get "/auth/test/callback", env: { "omniauth.auth" => auth }
    end
  end
end
