require "test_helper"

class AdminPermissionsTest < ActionDispatch::IntegrationTest
  test "anonymous staff page and mutation requests require staff login" do
    patron = create_patron
    job = create_print_job(patron: patron)
    requests = [
      [:get, "/admin"],
      [:head, "/admin"],
      [:get, "/admin/stats"],
      [:get, "/admin/help"],
      [:get, "/admin/jobs"],
      [:get, "/admin/jobs/new"],
      [:get, "/admin/jobs/#{job.id}"],
      [:get, "/admin/jobs/#{job.id}/edit"],
      [:patch, "/admin/jobs/#{job.id}"],
      [:delete, "/admin/jobs/#{job.id}"],
      [:post, "/admin/jobs"],
      [:get, "/admin/jobs/export.csv"],
      [:get, "/admin/jobs/export.json"],
      [:get, "/admin/jobs/export.xml"],
      [:post, "/admin/jobs/bulk_destroy"],
      [:get, "/admin/jobs/#{job.id}/conversation"],
      [:post, "/admin/jobs/#{job.id}/conversation"],
      [:get, "/admin/jobs/#{job.id}/files"],
      [:post, "/admin/jobs/#{job.id}/files"],
      [:delete, "/admin/jobs/#{job.id}/files/1"],
      [:post, "/admin/jobs/#{job.id}/picked_up"],
      [:get, "/admin/patrons"],
      [:get, "/admin/patrons/new"],
      [:get, "/admin/patrons/#{patron.id}"],
      [:get, "/admin/patrons/#{patron.id}/edit"],
      [:patch, "/admin/patrons/#{patron.id}"],
      [:delete, "/admin/patrons/#{patron.id}"],
      [:post, "/admin/patrons"],
      [:get, "/admin/patrons/export.csv"],
      [:get, "/admin/patrons/export.json"],
      [:get, "/admin/patrons/export.xml"],
      [:post, "/admin/patrons/bulk_destroy"],
      [:get, "/admin/patrons/#{patron.id}/merge"],
      [:post, "/admin/patrons/#{patron.id}/merge"]
    ]

    requests.each do |method, path|
      public_send(method, path)
      assert_redirected_to admin_login_path, "#{method.upcase} #{path} must require staff login"
    end
    assert Patron.exists?(patron.id)
    assert Job.exists?(job.id)
  end

  test "patron login does not authorize the staff interface" do
    patron = create_patron
    get dashboard_path(token: patron.access_token)
    post consume_dashboard_token_path, params: { token: patron.access_token }

    get admin_patrons_path

    assert_redirected_to admin_login_path
  end

  test "staff login returns to a requested admin page" do
    get admin_patrons_path(q: "sample")
    assert_redirected_to admin_login_path

    sign_in_staff(create_staff_user)

    assert_redirected_to admin_patrons_path(q: "sample")
  end

  test "staff login defaults to the custom admin overview" do
    sign_in_staff(create_staff_user)

    assert_redirected_to admin_root_path
  end

  test "return paths accept only local admin URLs" do
    controller = SessionsController.new

    assert_equal "/admin/jobs?scope=active", controller.send(:safe_admin_return_path, "/admin/jobs?scope=active")
    [nil, "https://example.org/admin", "//example.org/admin", "/dashboard", "/administrator", "/admin/login", "/admin/login?next=1", "/admin/\\evil", "/admin/\r\nevil"].each do |path|
      assert_nil controller.send(:safe_admin_return_path, path), "unsafe return path should be ignored"
    end
  end

  test "logout revokes access to custom staff pages" do
    sign_in_staff(create_staff_user)
    delete logout_path
    assert_redirected_to root_path

    get admin_patrons_path
    assert_redirected_to admin_login_path
  end

  test "staff responses cannot be restored from browser or Turbo snapshots after logout" do
    sign_in_staff(create_staff_user)
    get admin_root_path

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "meta[name='turbo-cache-control'][content='no-cache']"
  end

  test "ordinary staff cannot invoke administrative patron operations directly" do
    patron = create_patron
    sign_in_staff(create_staff_user)

    [
      [:get, new_admin_patron_path],
      [:post, admin_patrons_path],
      [:delete, admin_patron_path(patron)],
      [:get, export_admin_patrons_path(format: :csv)],
      [:get, export_admin_patrons_path(format: :json)],
      [:get, export_admin_patrons_path(format: :xml)],
      [:post, bulk_destroy_admin_patrons_path],
      [:get, merge_admin_patron_path(patron)],
      [:post, merge_admin_patron_path(patron)]
    ].each do |method, path|
      public_send(method, path)
      assert_response :forbidden, "#{method.upcase} #{path} must require admin privileges"
    end
    assert Patron.exists?(patron.id)
  end

  private

  def sign_in_staff(staff)
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: staff.uid,
      info: { email: staff.email, name: staff.name, image: "https://example.org/avatar.png" },
      extra: { id_info: { hd: "example.org", email_verified: true } }
    )
    with_env("GOOGLE_DOMAIN" => "example.org") do
      get "/auth/test/callback", env: { "omniauth.auth" => auth }
    end
  end
end
