require "test_helper"

class AdminPickupCsrfTest < ActionDispatch::IntegrationTest
  setup do
    ensure_base_lookups!
    @staff = create_staff_user(email: "pickup@example.com")
    @job = create_print_job(status_code: "ready_for_pickup")
    @forgery_settings = [Admin::DashboardController, Admin::JobsController].to_h do |controller|
      [controller, controller.allow_forgery_protection]
    end
    @forgery_settings.each_key { |controller| controller.allow_forgery_protection = true }
    sign_in_staff
  end

  teardown do
    @forgery_settings&.each { |controller, original| controller.allow_forgery_protection = original }
  end

  test "staff can submit the actual dashboard pickup form with CSRF protection enabled" do
    token = dashboard_pickup_token

    post picked_up_admin_job_path(@job), params: { authenticity_token: token }

    assert_response :see_other
    assert_redirected_to admin_root_path
    assert_equal Date.current, @job.reload.pickup_date
    assert_equal "archived", @job.status.code
    assert_equal @staff, @job.audits.reorder(:version).last.user
  end

  test "missing and invalid CSRF tokens reject pickup with an actionable refresh message" do
    [nil, "invalid-synthetic-token"].each do |token|
      dashboard_pickup_token
      original_attributes = @job.reload.attributes

      assert_no_difference -> { @job.audits.count } do
        assert_no_enqueued_jobs do
          post picked_up_admin_job_path(@job), params: { authenticity_token: token }.compact
        end
      end

      assert_response :see_other
      assert_redirected_to admin_root_path
      assert_includes flash[:alert], "Reload the page and try again"
      assert_equal original_attributes, @job.reload.attributes
    end
  end

  test "a pickup form from before a new login is rejected without modifying the job" do
    stale_token = dashboard_pickup_token
    sign_in_staff
    original_attributes = @job.reload.attributes

    assert_no_difference -> { @job.audits.count } do
      assert_no_enqueued_jobs do
        post picked_up_admin_job_path(@job), params: { authenticity_token: stale_token }
      end
    end

    assert_response :see_other
    assert_redirected_to admin_root_path
    assert_includes flash[:alert], "Reload the page and try again"
    assert_equal original_attributes, @job.reload.attributes
  end

  test "JSON CSRF failures return an error instead of following a background redirect" do
    dashboard_pickup_token
    original_attributes = @job.reload.attributes

    assert_no_difference -> { @job.audits.count } do
      post picked_up_admin_job_path(@job), as: :json
    end

    assert_response :unprocessable_content
    assert_includes response.parsed_body.fetch("errors").join, "Reload the page and try again"
    assert_nil flash[:alert]
    assert_equal original_attributes, @job.reload.attributes
  end

  test "a legacy dashboard global token permits the legacy pickup POST after cutover" do
    dashboard_pickup_token
    # The legacy hidden form used form_authenticity_token without per-form
    # options, the same global token format used by csrf_meta_tags.
    token = css_select("meta[name='csrf-token']").first["content"]
    assert token.present?

    post admin_legacy_picked_up_job_path(@job), params: { authenticity_token: token }

    assert_response :see_other
    assert_redirected_to admin_root_path
    assert_equal Date.current, @job.reload.pickup_date
    assert_equal "archived", @job.status.code
  end

  test "legacy pickup rejects invalid tokens without changing the job" do
    dashboard_pickup_token
    original_attributes = @job.reload.attributes

    assert_no_difference -> { @job.audits.count } do
      post admin_legacy_picked_up_job_path(@job), params: { authenticity_token: "invalid-synthetic-token" }
    end

    assert_response :see_other
    assert_redirected_to admin_root_path
    assert_includes flash[:alert], "Nothing was saved"
    assert_equal original_attributes, @job.reload.attributes
  end

  test "cross-origin pickup is rejected even with a valid form token" do
    token = dashboard_pickup_token
    original_attributes = @job.reload.attributes

    assert_no_difference -> { @job.audits.count } do
      post picked_up_admin_job_path(@job), params: { authenticity_token: token },
        headers: { "HTTP_ORIGIN" => "https://example.net" }
    end

    assert_response :see_other
    assert_redirected_to admin_root_path
    assert_equal original_attributes, @job.reload.attributes
  end

  private

  def dashboard_pickup_token
    get admin_root_path
    assert_response :success
    token = nil
    assert_select "form[action='#{picked_up_admin_job_path(@job)}'] input[name='authenticity_token']" do |inputs|
      token = inputs.first["value"]
    end
    assert token.present?, "The real pickup form must carry a CSRF token."
    token
  end

  def sign_in_staff
    auth = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: @staff.uid,
      info: { email: @staff.email, name: @staff.name, image: "https://example.com/avatar.png" },
      extra: { id_info: { hd: "example.com", email_verified: true } })
    with_env("GOOGLE_DOMAIN" => "example.com") do
      get "/auth/test/callback", env: { "omniauth.auth" => auth }
    end
  end
end
