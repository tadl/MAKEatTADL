require "test_helper"
require "csv"

class AdminResourcesTest < ActionDispatch::IntegrationTest
  setup do
    ensure_base_lookups!
    @staff = create_staff_user
  end

  test "administrative resource endpoints require staff authentication" do
    status = ensure_status("pending")
    [
      [:get, admin_resources_path(resource: "statuses")],
      [:get, admin_resource_path(resource: "statuses", id: status.id)],
      [:get, new_admin_resource_path(resource: "statuses")],
      [:get, edit_admin_resource_path(resource: "statuses", id: status.id)],
      [:post, admin_resources_path(resource: "statuses")],
      [:patch, admin_resource_path(resource: "statuses", id: status.id)],
      [:delete, admin_resource_path(resource: "statuses", id: status.id)],
      [:post, bulk_destroy_admin_resources_path(resource: "statuses")],
      [:get, export_admin_resources_path(resource: "statuses", format: :csv)],
      [:get, export_admin_resources_path(resource: "statuses", format: :json)],
      [:get, export_admin_resources_path(resource: "statuses", format: :xml)]
    ].each do |method, path|
      public_send(method, path)
      assert_redirected_to admin_login_path
    end
    assert Status.exists?(status.id)
  end

  test "staff can read lookup records but cannot modify or export them" do
    sign_in_staff(@staff)
    status = ensure_status("pending")

    get admin_resources_path(resource: "statuses")
    assert_response :success
    get admin_resource_path(resource: "statuses", id: status.id)
    assert_response :success
    assert_select "a", text: "Edit record", count: 0

    [
      [:get, new_admin_resource_path(resource: "statuses")],
      [:get, edit_admin_resource_path(resource: "statuses", id: status.id)],
      [:post, admin_resources_path(resource: "statuses")],
      [:patch, admin_resource_path(resource: "statuses", id: status.id)],
      [:delete, admin_resource_path(resource: "statuses", id: status.id)],
      [:post, bulk_destroy_admin_resources_path(resource: "statuses")],
      [:get, export_admin_resources_path(resource: "statuses", format: :csv)]
    ].each do |method, path|
      public_send(method, path)
      assert_response :forbidden, "#{method.upcase} #{path} must require an administrator"
    end
    assert_equal "Pending", status.reload.name
  end

  test "staff cannot access hidden operational and identity tables directly" do
    sign_in_staff(@staff)
    job = create_print_job
    message = job.conversation.messages.create!(author: job.patron, body: "Synthetic message")
    records = { "staff_users" => @staff, "conversations" => job.conversation, "messages" => message, "audits" => job.audits.last }

    records.each do |resource, record|
      get admin_resources_path(resource: resource)
      assert_response :forbidden
      get admin_resource_path(resource: resource, id: record.id)
      assert_response :forbidden
      patch admin_resource_path(resource: resource, id: record.id), params: { record: { admin: true } }
      assert_response :forbidden
      delete admin_resource_path(resource: resource, id: record.id)
      assert_response :forbidden
      get export_admin_resources_path(resource: resource, format: :json)
      assert_response :forbidden
    end
    assert_not @staff.reload.admin?
  end

  test "resource URLs use a static allowlist rather than constantizing user input" do
    sign_in_staff(@staff.tap { |staff| staff.update!(admin: true) })

    %w[StaffUser staff_user users Kernel Object active_storage_blobs].each do |resource|
      get admin_resources_path(resource: resource)
      assert_response :not_found
    end
  end

  test "admin cannot directly create identity message or conversation records" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)

    %w[staff_users messages conversations].each do |resource|
      get new_admin_resource_path(resource: resource)
      assert_response :forbidden
      post admin_resources_path(resource: resource), params: { record: { admin: true, body: "Synthetic message", job_id: 1 } }
      assert_response :forbidden
    end
  end

  test "malformed resource parameter roots return bad request" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    status = ensure_status("pending")

    assert_no_difference "Status.count" do
      post admin_resources_path(resource: "statuses"), params: { record: "invalid" }
    end
    assert_response :bad_request

    patch admin_resource_path(resource: "statuses", id: status.id), params: { record: ["invalid"] }
    assert_response :bad_request
    assert_equal "Pending", status.reload.name
  end

  test "admin can edit only the permitted staff role field" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    target = create_staff_user(name: "Original Staff", email: "original-staff@example.org")
    uid = target.uid

    patch admin_resource_path(resource: "staff_users", id: target.id), params: { record: {
      admin: "1", name: "Changed Staff", email: "changed@example.org", uid: "changed-uid",
      avatar_url: "https://example.org/changed.png", encrypted_password: "synthetic-password"
    } }

    assert_redirected_to admin_resource_path(resource: "staff_users", id: target.id)
    target.reload
    assert target.admin?
    assert_equal "Original Staff", target.name
    assert_equal "original-staff@example.org", target.email
    assert_equal uid, target.uid

    get new_admin_resource_path(resource: "staff_users")
    assert_response :forbidden
    post admin_resources_path(resource: "staff_users"), params: { record: { admin: true } }
    assert_response :forbidden
  end

  test "lookup creation and updates retain normal model validation" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)

    post admin_resources_path(resource: "filament_colors"), params: { record: { name: "Sample Color", code: "sample_color", rgb: "not-a-color", active: true } }

    assert_response :unprocessable_content
    assert_nil FilamentColor.find_by(code: "sample_color")

    post admin_resources_path(resource: "filament_colors"), params: { record: { name: "Sample Color", code: "sample_color", rgb: "abc", active: true, type: "StaffUser" } }

    color = FilamentColor.find_by!(code: "sample_color")
    assert_redirected_to admin_resource_path(resource: "filament_colors", id: color.id)
    assert_equal "#aabbcc", color.rgb
  end

  test "message administration rejects arbitrary polymorphic author classes" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    job = create_print_job
    message = job.conversation.messages.create!(author: job.patron, body: "Original message")

    patch admin_resource_path(resource: "messages", id: message.id), params: { record: { author_type: "Kernel", body: "Changed message" } }

    assert_response :unprocessable_content
    assert_equal "Patron", message.reload.author_type
    assert_equal "Original message", message.body
  end

  test "bulk delete rolls all changes back when one record is still referenced" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    unused = ensure_status("unused", name: "Unused", position: -1)
    used = ensure_status("pending")
    job = create_print_job(status_code: used.code)

    post bulk_destroy_admin_resources_path(resource: "statuses"), params: { ids: [unused.id, used.id] }

    assert_redirected_to admin_resources_path(resource: "statuses")
    assert_match "No records were deleted", flash[:alert]
    assert Status.exists?(unused.id)
    assert Status.exists?(used.id)
    assert_equal used.id, job.reload.status_id
  end

  test "resource exports restrict fields and escape formulas after leading whitespace" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    target = create_staff_user(name: " =1+1", email: "export-staff@example.org")

    get export_admin_resources_path(resource: "staff_users", format: :csv, q: target.email)

    assert_response :success
    rows = CSV.parse(response.body, headers: true)
    assert_equal %w[id name email admin], rows.headers
    assert_equal "' =1+1", rows.first["name"]
    assert_not_includes response.body, target.uid

    get export_admin_resources_path(resource: "staff_users", format: :json, q: target.email)

    assert_response :success
    record = JSON.parse(response.body).first
    assert_equal %w[admin email id name], record.keys.sort

    get export_admin_resources_path(resource: "staff_users", format: :xml, q: target.email)

    assert_response :success
    assert_includes response.body, "export-staff@example.org"
    assert_not_includes response.body, target.uid
    assert_not_includes response.body, "encrypted_password"
  end

  test "activity records redact nested credentials in views and exports and are read only" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    patron = create_patron
    audit = Audited::Audit.create!(auditable: patron, user: @staff, action: "update", version: 10,
      audited_changes: {
        "access_token" => ["synthetic-old-token", "synthetic-new-token"],
        "details" => { "client_secret" => "synthetic-client-secret", "name" => "Visible change" }
      })

    [
      admin_resource_path(resource: "audits", id: audit.id),
      export_admin_resources_path(resource: "audits", format: :csv),
      export_admin_resources_path(resource: "audits", format: :json),
      export_admin_resources_path(resource: "audits", format: :xml)
    ].each do |path|
      get path
      assert_response :success
      assert_includes response.body, "[FILTERED]"
      %w[synthetic-old-token synthetic-new-token synthetic-client-secret].each { |secret| assert_not_includes response.body, secret }
    end

    [
      [:get, new_admin_resource_path(resource: "audits")],
      [:get, edit_admin_resource_path(resource: "audits", id: audit.id)],
      [:post, admin_resources_path(resource: "audits")],
      [:patch, admin_resource_path(resource: "audits", id: audit.id)],
      [:delete, admin_resource_path(resource: "audits", id: audit.id)],
      [:post, bulk_destroy_admin_resources_path(resource: "audits")]
    ].each do |method, path|
      public_send(method, path)
      assert_response :forbidden
    end
    assert Audited::Audit.exists?(audit.id)
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
