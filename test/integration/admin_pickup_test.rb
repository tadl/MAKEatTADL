require "test_helper"

module LegacyPickupTestSupport
  private

  def pickup_path(job)
    rails_admin.picked_up_path(model_name: "job", id: job.id)
  end

  def sign_in_staff(staff)
    auth = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: staff.uid,
      info: { email: staff.email, name: staff.name, image: "https://example.org/synthetic-avatar.png" },
      extra: { id_info: { hd: "example.org", email_verified: true } })
    with_env("GOOGLE_DOMAIN" => "example.org") do
      get "/auth/test/callback", env: { "omniauth.auth" => auth }
    end
  end

  def assert_pickup_unchanged(job)
    original_attributes = job.attributes
    assert_no_difference -> { job.audits.count } do
      assert_no_enqueued_jobs { yield }
    end
    assert_equal original_attributes, job.reload.attributes
  end
end

class AdminPickupTest < ActionDispatch::IntegrationTest
  include LegacyPickupTestSupport

  setup do
    ensure_base_lookups!
    @staff = create_staff_user(email: "synthetic-pickup@example.org")
    sign_in_staff(@staff)
  end

  test "ordinary staff can pick up ready print and scan jobs with audit attribution" do
    other_patron = create_patron
    [create_print_job(status_code: "ready_for_pickup"), create_scan_job(status_code: "ready_for_pickup")].each do |job|
      original_patron = job.patron
      assert_difference -> { job.audits.count }, 1 do
        assert_no_enqueued_jobs do
          post pickup_path(job), params: { job: { pickup_date: Date.yesterday, patron_id: other_patron.id,
            status_id: Status.find_by!(code: "cancelled").id, actual_cost: "999.99" } }
        end
      end

      assert_response :see_other
      assert_redirected_to rails_admin.dashboard_path
      assert_equal Date.current, job.reload.pickup_date
      assert_equal "archived", job.status.code
      assert_equal original_patron, job.patron
      assert_nil job.actual_cost
      audit = job.audits.reorder(:version).last
      assert_equal @staff, audit.user
      assert_includes audit.audited_changes.keys, "pickup_date"
    end
    assert_not @staff.reload.admin?
  end

  test "staff and administrators retain pickup controls on the dashboard" do
    job = create_print_job(status_code: "ready_for_pickup", attrs: { actual_cost: "12.34" })
    [false, true].each do |admin|
      @staff.update!(admin: admin)
      get rails_admin.dashboard_path

      assert_response :success
      assert_select "form#pickup_form_#{job.id}[method='post']", count: 1 do |forms|
        assert_equal pickup_path(job), URI.parse(forms.first["action"]).path
      end
      assert_includes response.body, "$12.34"
    end
  end

  test "nonready jobs and next day repeated pickups are unchanged" do
    [create_print_job, create_scan_job(status_code: "in_progress")].each do |job|
      assert_pickup_unchanged(job) { post pickup_path(job) }
      assert_response :see_other
      assert_redirected_to rails_admin.dashboard_path
      assert_match "not ready for pickup", flash[:alert]
    end

    job = create_print_job(status_code: "ready_for_pickup")
    post pickup_path(job)
    assert_equal "archived", job.reload.status.code
    travel 1.day do
      assert_pickup_unchanged(job) { post pickup_path(job) }
      assert_response :see_other
      assert_redirected_to rails_admin.dashboard_path
      assert_match "already been picked up", flash[:alert]
    end
  end

  test "a legacy ready job with a pickup date cannot have that date overwritten" do
    job = create_print_job(status_code: "ready_for_pickup")
    job.update_columns(pickup_date: Date.yesterday)

    assert_pickup_unchanged(job) { post pickup_path(job) }

    assert_response :see_other
    assert_redirected_to rails_admin.dashboard_path
    assert_match "already been picked up", flash[:alert]
  end

  test "inactive locations and invalid legacy URLs produce actionable validation errors" do
    inactive_location_job = create_print_job(status_code: "ready_for_pickup")
    ensure_pickup_location.update!(active: false)
    assert_pickup_unchanged(inactive_location_job) { post pickup_path(inactive_location_job) }
    assert_response :see_other
    assert_redirected_to rails_admin.dashboard_path
    assert_match "Correct these details in Edit job", flash[:error]
    assert_match "is not a valid pickup location", flash[:error]

    ensure_pickup_location.update!(active: true)
    invalid_url_job = create_print_job(status_code: "ready_for_pickup")
    invalid_url_job.update_columns(url: "javascript:alert(1)")
    assert_pickup_unchanged(invalid_url_job) { post pickup_path(invalid_url_job) }
    assert_response :see_other
    assert_redirected_to rails_admin.dashboard_path
    assert_match "must be a valid HTTP or HTTPS URL", flash[:error]
  end

  test "pickup validation messages remain escaped in the RailsAdmin flash" do
    job = create_print_job(status_code: "ready_for_pickup")
    job.update_columns(pickup_location: '<img src=x onerror="alert(1)">')
    assert_pickup_unchanged(job) { post pickup_path(job) }
    follow_redirect!

    assert_response :success
    assert_select ".alert img[onerror]", count: 0
    assert_includes response.body, "&lt;img"
  end

  test "anonymous and patron-only sessions cannot pick up their ready jobs" do
    patron = create_patron
    job = create_print_job(patron: patron, status_code: "ready_for_pickup")
    delete "/logout"
    assert_pickup_unchanged(job) { post pickup_path(job) }
    assert_redirected_to "/admin/login"

    post "/dashboard/consume_token", params: { token: patron.access_token }
    assert_redirected_to "/dashboard"
    assert_pickup_unchanged(job) { post pickup_path(job) }
    assert_redirected_to "/admin/login"
  end

  test "pickup grant does not permit administrative operations" do
    ability = Ability.new(@staff)
    [Job, Patron].each do |model|
      %i[create destroy export manage].each { |action| assert_not ability.can?(action, model) }
    end
    assert_not ability.can?(:update, StaffUser)
    assert_not ability.can?(:merge_patron, Patron)
    assert Ability.new(StaffUser.new(admin: true)).can?(:picked_up, Job)
    assert_not Ability.new(nil).can?(:picked_up, Job)
  end
end

class AdminPickupCsrfTest < ActionDispatch::IntegrationTest
  include LegacyPickupTestSupport

  setup do
    ensure_base_lookups!
    @staff = create_staff_user(email: "synthetic-csrf@example.org")
    @job = create_print_job(status_code: "ready_for_pickup")
    @original_forgery_protection = RailsAdmin::ApplicationController.allow_forgery_protection
    RailsAdmin::ApplicationController.allow_forgery_protection = true
    sign_in_staff(@staff)
  end

  teardown do
    RailsAdmin::ApplicationController.allow_forgery_protection = @original_forgery_protection
  end

  test "a token from the real dashboard form permits pickup" do
    token = dashboard_pickup_token
    post pickup_path(@job), params: { authenticity_token: token }

    assert_response :see_other
    assert_redirected_to rails_admin.dashboard_path
    assert_equal Date.current, @job.reload.pickup_date
    assert_equal "archived", @job.status.code
  end

  test "missing and invalid tokens reject changes and recover through a refreshed dashboard" do
    [nil, "not-a-valid-token"].each do |token|
      dashboard_pickup_token
      assert_pickup_unchanged(@job) do
        post pickup_path(@job), params: { authenticity_token: token }
      end

      assert_response :see_other
      assert_redirected_to rails_admin.dashboard_path
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_match "Nothing was saved", flash[:alert]
    end

    post pickup_path(@job), params: { authenticity_token: dashboard_pickup_token }
    assert_equal "archived", @job.reload.status.code
  end

  test "a stale token from before signout is rejected but a current token works" do
    stale_token = dashboard_pickup_token
    delete "/logout"
    sign_in_staff(@staff)
    dashboard_pickup_token

    assert_pickup_unchanged(@job) do
      post pickup_path(@job), params: { authenticity_token: stale_token }
    end
    assert_response :see_other
    assert_redirected_to rails_admin.dashboard_path
    assert_match "Nothing was saved", flash[:alert]

    post pickup_path(@job), params: { authenticity_token: dashboard_pickup_token }
    assert_equal "archived", @job.reload.status.code
  end

  test "cross-origin requests are rejected even with a valid token" do
    token = dashboard_pickup_token
    assert_pickup_unchanged(@job) do
      post pickup_path(@job), params: { authenticity_token: token }, headers: { "HTTP_ORIGIN" => "https://example.net" }
    end

    assert_response :see_other
    assert_redirected_to rails_admin.dashboard_path
  end

  test "missing CSRF on an expired staff session recovers to login" do
    delete "/logout"
    assert_pickup_unchanged(@job) { post pickup_path(@job) }

    assert_response :see_other
    assert_redirected_to "/admin/login"
    assert_match "Nothing was saved", flash[:alert]
  end

  test "JSON CSRF failures return errors without a redirect or mutation" do
    assert_pickup_unchanged(@job) { post pickup_path(@job), as: :json }

    assert_response :unprocessable_content
    assert_nil response.headers["Location"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_match "Nothing was saved", response.parsed_body.fetch("errors").first
    assert_nil flash[:alert]
  end

  private

  def dashboard_pickup_token
    get rails_admin.dashboard_path
    assert_response :success
    form = css_select("form#pickup_form_#{@job.id}").first
    assert_not_nil form
    assert_equal pickup_path(@job), URI.parse(form["action"]).path
    field = form.at_css("input[name='authenticity_token']")
    assert_not_nil field
    assert field["value"].present?
    field["value"]
  end
end
