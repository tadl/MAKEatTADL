require "test_helper"

class ScanningAvailabilityTest < ActionDispatch::IntegrationTest
  setup do
    ensure_base_lookups!
    @location = ensure_pickup_location
    PickupLocation.update_all(scanner: false)
    @location.reload.update!(active: true, scanner: true)
    @original_verifier = PortalController.instance_method(:verify_recaptcha_with_logging!)
    PortalController.define_method(:verify_recaptcha_with_logging!) { |**| true }
  end

  teardown do
    PortalController.define_method(:verify_recaptcha_with_logging!, @original_verifier)
  end

  test "active scanner locations enable public scanning and new scan requests" do
    get root_path
    assert_select "a[href='#{submit_scan_path}']", text: "Request a Scan"
    assert_select ".hero__subtitle", text: /Printing & Scanning/
    get token_thank_you_path
    assert_select "a[href='#{submit_scan_path}']"
    sign_in_patron(create_patron)
    get dashboard_path
    assert_select "a[href='#{submit_scan_path}']"

    get submit_scan_path
    assert_response :success
    assert_select "select[name='job[pickup_location]'] option[value='#{@location.code}']"

    assert_difference "ScanJob.count", 1 do
      assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
        post create_scan_job_path, params: scan_params
      end
    end
    assert_redirected_to thank_you_path(kind: "scan")
  end

  test "disabling every scanner hides public offers and blocks bookmarked forms and stale posts" do
    @location.update!(scanner: false)
    get root_path
    assert_response :success
    assert_select "a[href='#{submit_scan_path}']", count: 0
    assert_select ".hero__subtitle", text: /3D Printing for Our Community/
    assert_select ".about-card", text: /Scanning/, count: 0
    assert_select "a[href='#{submit_print_path}']"
    get submit_print_path
    assert_response :success

    get token_thank_you_path
    assert_select "a[href='#{submit_scan_path}']", count: 0
    sign_in_patron(create_patron)
    get dashboard_path
    assert_select "a[href='#{submit_scan_path}']", count: 0

    get submit_scan_path
    assert_redirected_to root_path
    assert_equal "3D scanning is currently unavailable.", flash[:alert]
    assert_no_difference ["ScanJob.count", "Patron.count", "Message.count"] do
      assert_no_enqueued_jobs do
        post create_scan_job_path, params: scan_params
      end
    end
    assert_response :see_other
    assert_redirected_to root_path
  end

  test "inactive locations do not enable scanning and reactivation restores it on the next request" do
    @location.update!(active: false)
    get root_path
    assert_select "a[href='#{submit_scan_path}']", count: 0
    get submit_scan_path
    assert_redirected_to root_path

    @location.update!(active: true)
    get root_path
    assert_select "a[href='#{submit_scan_path}']"
    get submit_scan_path
    assert_response :success
  end

  test "public submissions reject disabled inactive and nonexistent scanner locations" do
    other = ensure_pickup_location(code: "other", name: "Other Library")
    [[true, false], [false, true]].each do |active, scanner|
      other.update!(active: active, scanner: scanner)
      get submit_scan_path
      assert_select "select[name='job[pickup_location]'] option[value='#{other.code}']", count: 0
      assert_invalid_location(other.code)
    end
    assert_invalid_location("nonexistent")
  end

  test "existing scans remain accessible and editable when scanning is disabled" do
    job = create_scan_job
    @location.update!(scanner: false)
    sign_in_patron(job.patron)
    get dashboard_path
    assert_select "a[href='#{job_path(job)}']"
    get job_path(job)
    assert_response :success

    job.update!(notes: "Existing scan still in progress.")
    patch attach_model_files_job_path(job), params: { job: { model_files: [model_upload] } }
    assert_redirected_to job_path(job)
    assert_equal "ScanJob", job.reload.type
    assert_equal 1, job.model_files.count
  end

  private

  def scan_params(location = @location.code)
    {
      patron: { first_name: "Test", last_name: "Patron", email: unique_email("scan") },
      job: { spray_ok: true, notes: "Synthetic scan request", pickup_location: location }
    }
  end

  def sign_in_patron(patron)
    post consume_dashboard_token_path, params: { token: patron.access_token }
    assert_redirected_to dashboard_path
  end

  def assert_invalid_location(code)
    assert_no_difference ["ScanJob.count", "Patron.count", "Message.count"] do
      assert_no_enqueued_jobs do
        post create_scan_job_path, params: scan_params(code)
      end
    end
    assert_response :unprocessable_content
    assert_match "Please select a location that currently offers 3D scanning.", response.body
  end
end
