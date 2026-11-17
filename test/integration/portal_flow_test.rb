require "test_helper"

class PortalFlowTest < ActionDispatch::IntegrationTest
  test "patron job details do not link legacy URLs with executable schemes" do
    patron = create_patron
    job = create_print_job(patron: patron)
    job.update_column(:url, "javascript:alert(1)//https://example.org/model")
    post consume_dashboard_token_path, params: { token: patron.access_token }

    get job_path(job)

    assert_response :success
    assert_select "a[href^='javascript:']", count: 0
    assert_includes response.body, "javascript:alert(1)//https://example.org/model"
  end

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

class PortalCatalogSelectionTest < ActionDispatch::IntegrationTest
  setup do
    ensure_base_lookups!
    @public_models = %w[fidget assistive].index_with do |collection|
      PrintableModel.create!(name: "Synthetic #{collection}", code: "synthetic-#{collection}",
                             category: ensure_category(collection.capitalize), weight_grams: 12,
                             model_file: model_upload)
    end
    @staff_model = PrintableModel.create!(name: "Synthetic staff design", code: "synthetic-staff-design",
                                         category: ensure_category("Staff"), model_file: model_upload)
    @original_verifier = PortalController.instance_method(:verify_recaptcha_with_logging!)
    PortalController.define_method(:verify_recaptcha_with_logging!) { |**| true }
  end

  teardown do
    PortalController.define_method(:verify_recaptcha_with_logging!, @original_verifier)
  end

  test "public collections accept their own models with the existing file pricing and status behavior" do
    @public_models.each do |collection, model|
      assert_difference ["PrintJob.count", "Patron.count", "Conversation.count"], 1 do
        assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
          post collection_path(collection), params: request_params(model.id)
        end
      end

      assert_redirected_to thank_you_path(kind: collection)
      job = PrintJob.order(:id).last
      assert_equal model.id, job.printable_model_id
      assert_equal collection.capitalize, job.category.name
      assert_equal "approved", job.status.code
      assert_equal "fdm", job.print_type_code
      assert_equal 1, job.quantity
      assert_equal 12, job.slicer_weight
      assert_equal 0, job.slicer_cost
      assert_equal [model.model_file.blob_id], job.model_files.map(&:blob_id)
    end
  end

  test "public collections reject models from the other public collection" do
    @public_models.each_key do |collection|
      other_model = @public_models.fetch(collection == "fidget" ? "assistive" : "fidget")
      assert_rejected_selection(collection, other_model.id)
      assert_select "input[name='job[printable_model_id]'][value='#{other_model.id}']", count: 0
    end
  end

  test "public collections reject staff library models without copying their files" do
    @public_models.each_key do |collection|
      assert_rejected_selection(collection, @staff_model.id)
      assert_select "input[name='job[printable_model_id]'][value='#{@staff_model.id}']", count: 0
    end
  end

  test "public collections require an existing model selection" do
    @public_models.each_key do |collection|
      [nil, "", "not-an-id", 9_999_999_999].each do |model_id|
        assert_rejected_selection(collection, model_id)
      end
    end
  end

  test "generic patron requests reject crafted catalog IDs even with a valid model URL" do
    [@staff_model, *@public_models.values].each do |model|
      assert_no_difference ["PrintJob.count", "Patron.count", "Conversation.count", "ActiveStorage::Attachment.count"] do
        assert_no_enqueued_jobs do
          post create_print_job_path, params: request_params(model.id, url: "https://example.org/model.stl")
        end
      end

      assert_response :unprocessable_content
      assert_match "Please use the appropriate device form to select a catalog model.", response.body
    end
  end

  test "generic patron requests still accept their own model URL without a catalog selection" do
    assert_difference "PrintJob.count", 1 do
      assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
        post create_print_job_path, params: request_params(nil, url: "https://example.org/model.stl")
      end
    end

    assert_redirected_to thank_you_path(kind: "patron")
    job = PrintJob.order(:id).last
    assert_nil job.printable_model_id
    assert_empty job.model_files
    assert_equal "Patron", job.category.name
    assert_equal "pending", job.status.code
  end

  test "public collection form errors retain only eligible model choices" do
    @public_models.each do |collection, model|
      payload = request_params(model.id)
      payload[:patron][:email] = "invalid"
      assert_no_difference ["PrintJob.count", "Patron.count"] do
        post collection_path(collection), params: payload
      end

      assert_response :unprocessable_content
      assert_match "Please enter a valid email address", response.body
      assert_select "input[name='job[printable_model_id]'][value='#{model.id}'][checked]"
      assert_select "input[name='job[printable_model_id]'][value='#{@staff_model.id}']", count: 0
    end
  end

  test "public collection submissions still require CAPTCHA before saving or copying files" do
    PortalController.define_method(:verify_recaptcha_with_logging!) { |**| false }

    @public_models.each do |collection, model|
      assert_no_difference ["PrintJob.count", "Patron.count", "ActiveStorage::Attachment.count"] do
        assert_no_enqueued_jobs do
          post collection_path(collection), params: request_params(model.id)
        end
      end

      assert_response :unprocessable_content
      assert_match "reCAPTCHA failed", response.body
      assert_select "input[name='job[printable_model_id]'][value='#{model.id}'][checked]"
    end
  end

  test "public collection job validation errors render the selected eligible model" do
    model = @public_models.fetch("fidget")
    assert_no_difference ["PrintJob.count", "ActiveStorage::Attachment.count"] do
      post collection_path("fidget"), params: request_params(model.id, pickup_location: "not-a-location")
    end

    assert_response :unprocessable_content
    assert_match "not-a-location is not a valid pickup location", response.body
    assert_select "input[name='job[printable_model_id]'][value='#{model.id}'][checked]"
  end

  private

  def collection_path(collection)
    collection == "fidget" ? create_fidget_job_path : create_assistive_job_path
  end

  def request_params(model_id, **attributes)
    { patron: { first_name: "Synthetic", last_name: "Requester", email: unique_email("public-catalog") },
      job: { printable_model_id: model_id, pickup_location: ensure_pickup_location.code,
             filament_color: "red" }.merge(attributes) }
  end

  def assert_rejected_selection(collection, model_id)
    assert_no_difference ["PrintJob.count", "Patron.count", "Conversation.count", "Message.count", "ActiveStorage::Attachment.count"] do
      assert_no_enqueued_jobs do
        post collection_path(collection), params: request_params(model_id)
      end
    end

    assert_response :unprocessable_content
    assert_match "Please select a model from the #{collection} collection.", response.body
    assert_select "input[name='job[printable_model_id]'][value='#{@public_models.fetch(collection).id}']"
  end
end
