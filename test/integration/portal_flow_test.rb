require "test_helper"

class PortalFlowTest < ActionDispatch::IntegrationTest
  test "magic link get shows an interstitial without consuming the token" do
    patron = create_patron
    token = patron.access_token

    get dashboard_path(token: token)

    assert_response :success
    assert_match "Continue to Your Dashboard", response.body
    assert_equal token, patron.reload.access_token
  end

  test "magic links are one-time after the interstitial post while the issued cookie remains usable" do
    patron = create_patron
    token = patron.access_token

    get dashboard_path(token: token)
    assert_response :success

    post consume_dashboard_token_path, params: { token: token }
    assert_redirected_to dashboard_path

    follow_redirect!
    assert_response :success

    get dashboard_path
    assert_response :success

    open_session do |fresh_session|
      fresh_session.post consume_dashboard_token_path, params: { token: token }
      fresh_session.assert_redirected_to login_path
    end
  end

  test "job magic link get shows an interstitial and post signs the patron in" do
    patron = create_patron
    job = create_print_job(patron: patron)
    token = patron.access_token

    get job_path(job, token: token)
    assert_response :success
    assert_match "Continue to Your Job", response.body
    assert_equal token, patron.reload.access_token

    post consume_job_token_job_path(job), params: { token: token }
    assert_redirected_to job_path(job)

    follow_redirect!
    assert_response :success
    assert_match "##{job.id}", response.body
  end

  test "job magic link post does not consume token for a job owned by another patron" do
    patron = create_patron
    other_job = create_print_job(patron: create_patron)
    token = patron.access_token

    post consume_job_token_job_path(other_job), params: { token: token }

    assert_redirected_to login_path
    assert_equal token, patron.reload.access_token
  end

  test "failed recaptcha does not create a patron for print submissions" do
    ensure_base_lookups!
    email = unique_email("captcha-fail")
    original_verifier = PortalController.instance_method(:verify_recaptcha_with_logging!)
    PortalController.define_method(:verify_recaptcha_with_logging!) { |**| false }

    assert_no_difference("Patron.count") do
      post create_print_job_path, params: {
        patron: {
          first_name: "Captcha",
          last_name: "Failure",
          email: email
        },
        job: {
          url: "https://example.com/model.stl",
          filament_color: "red",
          pickup_location: ensure_pickup_location.code
        }
      }
    end

    assert_response :unprocessable_content
  ensure
    PortalController.define_method(:verify_recaptcha_with_logging!, original_verifier) if original_verifier
  end

  test "failed recaptcha does not create a patron for scan submissions" do
    ensure_base_lookups!
    email = unique_email("scan-captcha-fail")
    original_verifier = PortalController.instance_method(:verify_recaptcha_with_logging!)
    PortalController.define_method(:verify_recaptcha_with_logging!) { |**| false }

    assert_no_difference("Patron.count") do
      post create_scan_job_path, params: {
        patron: {
          first_name: "Scan",
          last_name: "Failure",
          email: email
        },
        job: {
          spray_ok: true,
          notes: "Scan this",
          pickup_location: ensure_pickup_location.code
        }
      }
    end

    assert_response :unprocessable_content
  ensure
    PortalController.define_method(:verify_recaptcha_with_logging!, original_verifier) if original_verifier
  end

  test "magic link requests stay neutral for unknown email addresses" do
    assert_no_enqueued_jobs do
      post send_login_path, params: { patron: { email: unique_email("missing") } }
    end

    assert_redirected_to token_thank_you_path
  end

  test "magic link requests enqueue a mail for known patrons" do
    patron = create_patron

    assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
      post send_login_path, params: { patron: { email: patron.email } }
    end

    assert_redirected_to token_thank_you_path
  end

  test "follow-up model uploads require ownership of the job" do
    owner = create_patron
    intruder = create_patron
    job = create_print_job(patron: owner)

    get dashboard_path(token: intruder.access_token)
    post consume_dashboard_token_path, params: { token: intruder.access_token }
    follow_redirect!

    patch attach_model_files_job_path(job), params: {
      job: {
        model_files: [model_upload]
      }
    }

    assert_response :not_found
    assert_equal 0, job.reload.model_files.count
  end

  test "follow-up model uploads accept 3mf files for the owning patron" do
    patron = create_patron
    job = create_print_job(patron: patron)

    get dashboard_path(token: patron.access_token)
    post consume_dashboard_token_path, params: { token: patron.access_token }
    follow_redirect!

    patch attach_model_files_job_path(job), params: {
      job: {
        model_files: [model_upload(filename: "test-model.3mf", content_type: "application/zip")]
      }
    }

    assert_redirected_to job_path(job)
    assert_equal 1, job.reload.model_files.count
    assert_equal "test-model.3mf", job.model_files.first.filename.to_s
  end
end
