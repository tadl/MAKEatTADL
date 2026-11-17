require "test_helper"

class AdminLegacyTest < ActionDispatch::IntegrationTest
  test "historic staff email conversation links require login and redirect to the new conversation" do
    job = create_print_job
    get "/admin/job/#{job.id}/conversation"
    assert_redirected_to admin_login_path

    sign_in_staff(create_staff_user)
    get "/admin/job/#{job.id}/conversation"
    assert_response :moved_permanently
    assert_redirected_to conversation_admin_job_path(job)
    follow_redirect!
    assert_response :success
  end

  test "historic job list filters and help links remain usable" do
    job = create_print_job
    sign_in_staff(create_staff_user)
    get "/admin/job", params: { scope: "inactive", query: "sample", f: { status: { "0" => { o: "is", v: job.status_id } } } }
    assert_redirected_to admin_jobs_path(scope: "inactive", q: "sample", status_id: job.status_id)

    get "/admin/job/help"
    assert_redirected_to admin_help_path

    get "/admin/job", params: { f: "malformed legacy filter" }
    assert_redirected_to admin_jobs_path
  end

  test "historic settings bookmarks retain server authorization" do
    sign_in_staff(create_staff_user)
    get "/admin/status"
    assert_redirected_to admin_resources_path(resource: "statuses")
    get "/admin/staff_user"
    assert_response :forbidden
    get "/admin/job/export"
    assert_response :forbidden
  end

  test "historic merge and edit bookmarks point to the corresponding custom screens" do
    patron = create_patron
    sign_in_staff(create_staff_user(admin: true))
    get "/admin/patron/#{patron.id}/merge_patron"
    assert_redirected_to merge_admin_patron_path(patron)
    get "/admin/patron/#{patron.id}/edit"
    assert_redirected_to edit_admin_patron_path(patron)
    get "/admin/job/new"
    assert_redirected_to new_admin_job_path
  end

  test "legacy writes cannot bypass the new mutation routes" do
    job = create_print_job
    sign_in_staff(create_staff_user(admin: true))
    assert_no_difference "Message.count" do
      post "/admin/job/#{job.id}/conversation", params: { conversation: { message_body: "stale form" } }
      assert_response :not_found
    end
  end

  private

  def sign_in_staff(staff)
    auth = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: staff.uid,
      info: { email: staff.email, name: staff.name },
      extra: { id_info: { hd: "example.org", email_verified: true } })
    with_env("GOOGLE_DOMAIN" => "example.org") { get "/auth/test/callback", env: { "omniauth.auth" => auth } }
  end
end
