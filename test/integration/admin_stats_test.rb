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

  test "dashboard renders ready jobs unread replies and the current staff member's mentions" do
    job = create_print_job(status_code: "ready_for_pickup")
    message = job.conversation.messages.create!(author: job.patron, body: "Patron reply")
    Notification.create!(staff_user: @staff, message: message)
    other_job = create_print_job
    other_message = other_job.conversation.messages.create!(author: @staff, body: "Other staff note", staff_note_only: true)
    Notification.create!(staff_user: create_staff_user, message: other_message)

    get rails_admin.dashboard_path

    assert_response :success
    assert_select "a[href='#{rails_admin.conversation_path(model_name: 'job', id: job.id)}']", count: 3
    assert_select "a[href='#{rails_admin.conversation_path(model_name: 'job', id: other_job.id)}']", count: 0
    assert_select ".badge.bg-danger", text: "1"
    assert_select ".badge.bg-warning", text: "1"
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
