require "test_helper"

class AdminDashboardTest < ActionDispatch::IntegrationTest
  setup do
    ensure_base_lookups!
    @staff = create_staff_user(email: "dashboard@example.com")
  end

  test "anonymous visitors must sign in to the dashboard statistics and help" do
    [admin_root_path, admin_stats_path, admin_help_path].each do |path|
      get path
      assert_redirected_to "/admin/login"
    end
  end

  test "dashboard shows ready jobs unread patron replies and only this staff user's mentions" do
    sign_in_staff(@staff)
    job = create_print_job(status_code: "ready_for_pickup")
    message = job.conversation.messages.create!(author: job.patron, body: "Synthetic patron reply")
    Notification.create!(staff_user: @staff, message: message)
    other_job = create_print_job
    other_message = other_job.conversation.messages.create!(author: @staff, body: "Synthetic staff note", staff_note_only: true)
    Notification.create!(staff_user: create_staff_user, message: other_message)

    get admin_root_path

    assert_response :success
    assert_select "a[href='#{conversation_admin_job_path(job)}']", count: 3
    assert_select "a[href='#{conversation_admin_job_path(other_job)}']", count: 0
    assert_select "form[action='#{picked_up_admin_job_path(job)}']", count: 0
    ongoing = Status.find_by!(code: "ongoing")
    assert_select "a[href='#{admin_jobs_path(status_id: ongoing.id, scope: 'ongoing')}']", count: 1
    assert_nil message.reload.read_at
  end

  test "pickup button is reserved for administrators" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    job = create_print_job(status_code: "ready_for_pickup")

    get admin_root_path

    assert_response :success
    assert_select "form[action='#{picked_up_admin_job_path(job)}'][method='post']", count: 1
    assert_select "form[data-turbo-confirm] button", text: "Mark picked up"
  end

  test "dashboard respects scanning availability and workflow guide is available to staff" do
    sign_in_staff(@staff)
    PickupLocation.update_all(scanner: false)

    get admin_root_path
    assert_response :success
    assert_select "a[href='#{submit_scan_path}']", count: 0

    get admin_help_path
    assert_response :success
    assert_select "h1", text: "Workflow guide"
    assert_select "h2", text: "Automations"
    assert_includes response.body, "14 days"
    assert_includes response.body, "30 days"
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
