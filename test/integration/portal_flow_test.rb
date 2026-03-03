require "test_helper"

class PortalFlowTest < ActionDispatch::IntegrationTest
  test "magic links are one-time while the issued cookie remains usable" do
    patron = create_patron
    token = patron.access_token

    get dashboard_path(token: token)
    assert_redirected_to dashboard_path

    follow_redirect!
    assert_response :success

    get dashboard_path
    assert_response :success

    open_session do |fresh_session|
      fresh_session.get dashboard_path(token: token)
      fresh_session.assert_redirected_to login_path
    end
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
