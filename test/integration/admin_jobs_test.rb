require "test_helper"
require "csv"

class AdminJobsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    ensure_base_lookups!
    @staff = create_staff_user(email: "job-operator@example.com")
    sign_in_staff(@staff)
  end

  test "staff can browse search filter and edit jobs" do
    job = create_print_job
    archived = create_print_job(status_code: "archived")
    scan = create_scan_job

    get admin_jobs_path
    assert_response :success
    assert_select "a[href='#{admin_job_path(job)}']"
    assert_select "a[href='#{admin_job_path(archived)}']", count: 0
    assert_select "a[href='#{new_admin_job_path}']", count: 0

    get admin_jobs_path(type: "ScanJob", q: scan.id.to_s)
    assert_response :success
    assert_select "a[href='#{admin_job_path(scan)}']"
    assert_select "a[href='#{admin_job_path(job)}']", count: 0

    get admin_jobs_path(scope: "inactive")
    assert_select "a[href='#{admin_job_path(archived)}']"

    get edit_admin_job_path(job)
    assert_response :success
    assert_select "input[name='job[actual_cost]']", count: 0
    assert_select "input[name='job[type]']", count: 0
    assert_select "input[name='job[patron_id]']", count: 0
  end

  test "staff edits preserve quote automation attribution and computed costs" do
    job = create_print_job
    original_patron = job.patron
    outsider = create_patron

    assert_enqueued_emails 1 do
      patch admin_job_path(job), params: { job: { slicer_weight: "22", slicer_cost: "999", actual_cost: "999",
        patron_id: outsider.id, type: "ScanJob", origin: "scan", started_by_id: 999 } }
    end

    assert_redirected_to admin_job_path(job)
    job.reload
    assert_equal "PrintJob", job.type
    assert_equal "print", job.origin
    assert_equal original_patron, job.patron
    assert_equal BigDecimal("2.2"), job.slicer_cost
    assert_nil job.actual_cost
    assert_nil job.started_by_id
    assert_equal "information_requested", job.status.code
    assert_not_nil job.information_requested_at
    assert_equal @staff, job.conversation.messages.last.author
  end

  test "staff completion preserves callback attribution and notification" do
    job = create_print_job(status_code: "in_progress")

    assert_enqueued_emails 1 do
      patch admin_job_path(job), params: { job: { actual_weight: "15.5" } }
    end

    assert_redirected_to admin_job_path(job)
    job.reload
    assert_equal "ready_for_pickup", job.status.code
    assert_equal @staff.id, job.finished_by_id
    assert_equal Date.current, job.completion_date
    assert_equal BigDecimal("1.55"), job.actual_cost
  end

  test "ongoing job edits suppress material notifications" do
    job = create_print_job(status_code: "ongoing")

    assert_no_enqueued_emails do
      patch admin_job_path(job), params: { job: { slicer_weight: "10", actual_weight: "12" } }
    end

    assert_equal "ongoing", job.reload.status.code
    assert_nil job.completion_date
  end

  test "invalid updates redisplay validation errors without changing the job" do
    job = create_print_job
    patch admin_job_path(job), params: { job: { url: "javascript:alert(1)" } }

    assert_response :unprocessable_content
    assert_select "form[action='#{admin_job_path(job)}']"
    assert_includes response.body, "must be a valid HTTP or HTTPS URL"
    assert_equal "https://example.com/model", job.reload.url
  end

  test "malformed job parameter envelopes return bad request" do
    job = create_print_job
    ["not-an-object", "", []].each do |payload|
      patch admin_job_path(job), params: { job: payload }, as: :json
      assert_response :bad_request
    end

    @staff.update!(admin: true)
    ["not-an-object", "", []].each do |payload|
      post admin_jobs_path, params: { job: payload }, as: :json
      assert_response :bad_request
    end
    assert_equal "pending", job.reload.status.code
  end

  test "invalid foreign IDs redisplay an input error instead of reaching database constraints" do
    job = create_print_job
    patch admin_job_path(job), params: { job: { assigned_printer_id: 999_999_999 } }

    assert_response :unprocessable_content
    assert_includes response.body, "Assigned printer does not exist"
    assert_nil job.reload.assigned_printer_id

    @staff.update!(admin: true)
    assert_no_difference -> { Job.count } do
      post admin_jobs_path, params: { job: { type: "PrintJob", patron_id: 999_999_999,
        status_id: Status.find_by!(code: "pending").id, category_id: Category.find_by!(name: "Patron").id,
        pickup_location: ensure_pickup_location.code, url: "https://example.org/synthetic-model" } }
    end
    assert_response :unprocessable_content
    assert_includes response.body, "Patron does not exist"
  end

  test "staff cannot create delete bulk delete or export jobs" do
    job = create_print_job(status_code: "ready_for_pickup")
    get new_admin_job_path
    assert_response :forbidden
    post admin_jobs_path, params: { job: { type: "PrintJob" } }
    assert_response :forbidden
    delete admin_job_path(job)
    assert_response :forbidden
    post bulk_destroy_admin_jobs_path, params: { ids: [job.id] }
    assert_response :forbidden
    %w[csv json xml].each do |format|
      get export_admin_jobs_path(format: format)
      assert_response :forbidden
    end
    assert_nil job.reload.pickup_date
  end

  test "staff pickup archives ready print and scan jobs with the current date and audit actor" do
    other_patron = create_patron
    jobs = [create_print_job(status_code: "ready_for_pickup"), create_scan_job(status_code: "ready_for_pickup")]

    jobs.each do |job|
      protected_attributes = job.attributes.slice("patron_id", "actual_cost", "type", "origin", "started_by_id", "finished_by_id")
      assert_difference -> { job.audits.count }, 1 do
        assert_no_enqueued_emails do
          post picked_up_admin_job_path(job), params: { job: { pickup_date: Date.yesterday,
            status_id: Status.find_by!(code: "cancelled").id, patron_id: other_patron.id, actual_cost: "999.99" } }
        end
      end

      assert_response :see_other
      assert_redirected_to admin_root_path
      assert_equal Date.current, job.reload.pickup_date
      assert_equal "archived", job.status.code
      assert_equal protected_attributes, job.attributes.slice(*protected_attributes.keys)
      audit = job.audits.reorder(:version).last
      assert_equal @staff, audit.user
      assert_equal "update", audit.action
      assert_includes audit.audited_changes.keys, "pickup_date"
    end
  end

  test "staff cannot pick up jobs that are not ready" do
    jobs = [create_print_job, create_scan_job(status_code: "in_progress"), create_print_job(status_code: "cancelled")]
    jobs.each do |job|
      original_attributes = job.attributes
      assert_no_difference -> { job.audits.count } do
        assert_no_enqueued_emails { post picked_up_admin_job_path(job) }
      end

      assert_response :see_other
      assert_redirected_to admin_job_path(job)
      assert_equal "This job is not ready for pickup.", flash[:alert]
      assert_equal original_attributes, job.reload.attributes
    end
  end

  test "repeated staff pickup does not rewrite the date or add an audit" do
    job = create_print_job(status_code: "ready_for_pickup")
    post picked_up_admin_job_path(job)
    assert_redirected_to admin_root_path
    original_attributes = job.reload.attributes

    travel 1.day do
      assert_no_difference -> { job.audits.count } do
        assert_no_enqueued_emails { post picked_up_admin_job_path(job) }
      end

      assert_response :see_other
      assert_redirected_to admin_job_path(job)
      assert_equal "This job is not ready for pickup.", flash[:alert]
      assert_equal original_attributes, job.reload.attributes
    end
  end

  test "staff pickup reports an inactive pickup location without changing the job" do
    job = create_print_job(status_code: "ready_for_pickup")
    ensure_pickup_location.update!(active: false)
    original_attributes = job.attributes

    assert_no_difference -> { job.audits.count } do
      assert_no_enqueued_emails { post picked_up_admin_job_path(job) }
    end

    assert_response :see_other
    assert_redirected_to admin_root_path
    assert_includes flash[:alert], "is not a valid pickup location"
    assert_equal original_attributes, job.reload.attributes
  end

  test "an existing pickup date is preserved even if a legacy job is still marked ready" do
    job = create_print_job(status_code: "ready_for_pickup")
    job.update_columns(pickup_date: Date.yesterday)
    original_attributes = job.attributes

    assert_no_difference -> { job.audits.count } do
      post picked_up_admin_job_path(job)
    end

    assert_response :see_other
    assert_redirected_to admin_job_path(job)
    assert_equal original_attributes, job.reload.attributes
  end

  test "pickup validation errors are escaped when shown on the overview" do
    job = create_print_job(status_code: "ready_for_pickup")
    invalid_location = "<script data-synthetic-pickup>ignored</script>"
    job.update_columns(pickup_location: invalid_location)

    post picked_up_admin_job_path(job)
    assert_redirected_to admin_root_path
    follow_redirect!

    assert_response :success
    assert_select "[role='alert']" do |alerts|
      assert_includes alerts.first.text, invalid_location
      assert_select "script", count: 0
    end
    assert_nil job.reload.pickup_date
    assert_equal "ready_for_pickup", job.status.code
  end

  test "staff pickup reports an invalid legacy URL without bypassing validation" do
    job = create_print_job(status_code: "ready_for_pickup")
    job.update_columns(url: "javascript:alert(1)")
    original_attributes = job.attributes

    assert_no_difference -> { job.audits.count } do
      assert_no_enqueued_emails { post picked_up_admin_job_path(job) }
    end

    assert_response :see_other
    assert_redirected_to admin_root_path
    assert_includes flash[:alert], "must be a valid HTTP or HTTPS URL"
    assert_equal original_attributes, job.reload.attributes
  end

  test "administrators can create either job type and retain scan identity on edit" do
    @staff.update!(admin: true)
    patron = create_patron
    get new_admin_job_path(type: "PrintJob")
    assert_response :success

    assert_difference -> { PrintJob.count }, 1 do
      post admin_jobs_path, params: { job: { type: "PrintJob", patron_id: patron.id,
        status_id: Status.find_by!(code: "pending").id, category_id: Category.find_by!(name: "Patron").id,
        pickup_location: ensure_pickup_location.code, url: "https://example.org/new-model" } }
    end
    assert_redirected_to admin_job_path(Job.order(:id).last)

    get new_admin_job_path(type: "ScanJob")
    assert_response :success
    assert_difference -> { ScanJob.count }, 1 do
      post admin_jobs_path, params: { job: { type: "ScanJob", patron_id: patron.id,
        status_id: Status.find_by!(code: "pending").id, category_id: Category.find_by!(name: "Patron").id,
        pickup_location: ensure_pickup_location.code, spray_ok: "1", notes: "A synthetic scan request" } }
    end
    scan = ScanJob.order(:id).last
    patch admin_job_path(scan), params: { job: { type: "PrintJob", notes: "Scan updated" } }
    assert_redirected_to admin_job_path(scan)
    assert_equal "ScanJob", scan.reload.type
  end

  test "catalog model creates a fresh linked job with the saved model file" do
    @staff.update!(admin: true)
    model = PrintableModel.create!(name: "Reusable design", code: "reusable-design", category: ensure_category("Fidget"), weight_grams: 8)
    model.model_file.attach(io: StringIO.new("synthetic model"), filename: "reusable.stl", content_type: "model/stl")
    patron = create_patron

    get new_admin_job_path(printable_model_id: model.id)
    assert_response :success
    assert_select "input[name='job[printable_model_id]'][value='#{model.id}']"
    assert_select "input[name='job[slicer_weight]']" do |inputs|
      assert_equal 8, inputs.first["value"].to_f
    end

    assert_difference -> { PrintJob.count }, 1 do
      post admin_jobs_path, params: { job: { type: "PrintJob", patron_id: patron.id,
        printable_model_id: model.id, status_id: Status.find_by!(code: "pending").id,
        category_id: Category.find_by!(name: "Patron").id, pickup_location: ensure_pickup_location.code } }
    end
    job = PrintJob.order(:id).last
    assert_equal model, job.printable_model
    assert_equal model.model_file.blob, job.model_files.first.blob
    assert_equal 1, job.quantity
    assert_equal 8, job.slicer_weight
    assert_equal "pending", job.status.code
    assert_nil job.actual_cost
    assert_nil job.finished_by_id
  end

  test "admin picked-up action and deletion require valid state" do
    @staff.update!(admin: true)
    job = create_print_job
    post picked_up_admin_job_path(job)
    assert_redirected_to admin_job_path(job)
    assert_nil job.reload.pickup_date

    job.update!(status: Status.find_by!(code: "ready_for_pickup"))
    post picked_up_admin_job_path(job)
    assert_redirected_to admin_root_path
    assert_equal Date.current, job.reload.pickup_date
    assert_equal "archived", job.status.code

    delete admin_job_path(job)
    assert_redirected_to admin_jobs_path
    assert_not Job.exists?(job.id)
  end

  test "exports preserve filtered results and exclude login tokens" do
    @staff.update!(admin: true)
    patron = create_patron(name: "=SYNTHETIC()")
    job = create_print_job(patron: patron, attrs: { notes: "  \uFEFF@synthetic formula" })
    create_print_job

    get export_admin_jobs_path(format: "csv", q: job.id.to_s)
    assert_response :success
    rows = CSV.parse(response.body, headers: true)
    assert_equal 1, rows.size
    assert_equal "'=SYNTHETIC()", rows.first["Patron"]
    assert_equal "'  \uFEFF@synthetic formula", rows.first["Notes"]
    assert_not_includes response.body, patron.access_token

    get export_admin_jobs_path(format: "json", q: job.id.to_s)
    assert_response :success
    assert_equal [job.id], JSON.parse(response.body).map { |row| row.fetch("id") }
    assert_not_includes response.body, "access_token"

    get export_admin_jobs_path(format: "xml", q: job.id.to_s)
    assert_response :success
    assert_includes response.body, "<id type=\"integer\">#{job.id}</id>"
    assert_not_includes response.body, "access-token"
  end

  private

  def sign_in_staff(staff)
    auth = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: staff.uid,
      info: { email: staff.email, name: staff.name }, extra: { id_info: { hd: "example.com", email_verified: true } })
    with_env("GOOGLE_DOMAIN" => "example.com") { get "/auth/test/callback", env: { "omniauth.auth" => auth } }
  end
end
