require "test_helper"
require "csv"

class AdminModelLibraryTest < ActionDispatch::IntegrationTest
  setup do
    ensure_base_lookups!
    @staff = create_staff_user
    @model = PrintableModel.create!(name: "Sample Model", code: "sample-model", category: ensure_category("Patron"), notes: "Tested print setup", weight_grams: 12)
    @model.model_file.attach(io: StringIO.new("synthetic saved model"), filename: "saved-model.stl", content_type: "model/stl")
  end

  test "anonymous visitors cannot access model library pages or mutations" do
    [
      [:get, admin_printable_models_path],
      [:get, admin_printable_model_path(@model)],
      [:get, new_admin_printable_model_path],
      [:get, edit_admin_printable_model_path(@model)],
      [:post, admin_printable_models_path],
      [:patch, admin_printable_model_path(@model)],
      [:delete, admin_printable_model_path(@model)],
      [:post, bulk_destroy_admin_printable_models_path],
      [:get, export_admin_printable_models_path(format: :csv)],
      [:get, export_admin_printable_models_path(format: :json)],
      [:get, export_admin_printable_models_path(format: :xml)]
    ].each do |method, path|
      public_send(method, path)
      assert_redirected_to admin_login_path
    end
    assert PrintableModel.exists?(@model.id)
  end

  test "staff can find and read saved models without write controls" do
    sign_in_staff(@staff)

    get admin_printable_models_path(q: "Tested print setup", category_id: @model.category_id)

    assert_response :success
    assert_select "a[href='#{admin_printable_model_path(@model)}']", minimum: 1
    assert_select "a[href='#{new_admin_printable_model_path}']", count: 0

    get admin_printable_model_path(@model)

    assert_response :success
    assert_select "a", text: "saved-model.stl"
    assert_select "a", text: "Print again", count: 0
    assert_select "a", text: "Edit model", count: 0
  end

  test "staff cannot invoke library writes exports or new print directly" do
    sign_in_staff(@staff)

    [
      [:get, new_admin_printable_model_path],
      [:get, edit_admin_printable_model_path(@model)],
      [:post, admin_printable_models_path],
      [:patch, admin_printable_model_path(@model)],
      [:delete, admin_printable_model_path(@model)],
      [:post, bulk_destroy_admin_printable_models_path],
      [:get, export_admin_printable_models_path(format: :csv)],
      [:get, export_admin_printable_models_path(format: :json)],
      [:get, export_admin_printable_models_path(format: :xml)],
      [:get, new_admin_job_path(printable_model_id: @model.id)],
      [:post, admin_jobs_path]
    ].each do |method, path|
      public_send(method, path)
      assert_response :forbidden
    end
    assert PrintableModel.exists?(@model.id)
  end

  test "admin saves a selected job file without copying requestor contact notes" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    job = create_print_job(attrs: { notes: "Synthetic requestor contact notes", slicer_weight: 18 })
    job.model_files.attach(io: StringIO.new("synthetic selected model"), filename: "selected-model.3mf", content_type: "application/zip")
    source_file = job.model_files.first

    get new_admin_printable_model_path(source_job_id: job.id, attachment_id: source_file.id)

    assert_response :success
    assert_select "input[name='source_job_id'][value='#{job.id}']"
    assert_select "input[name='attachment_id'][value='#{source_file.id}']"
    assert_select "textarea[name='printable_model[notes]']", text: ""

    assert_difference "PrintableModel.count", 1 do
      post admin_printable_models_path, params: {
        source_job_id: job.id, attachment_id: source_file.id,
        printable_model: { name: "Saved Selected Model", code: "", category_id: job.category_id, notes: "Curated printing notes" }
      }
    end

    saved = PrintableModel.find_by!(code: "saved-selected-model")
    assert_redirected_to admin_printable_model_path(saved)
    assert_equal source_file.blob_id, saved.model_file.blob_id
    assert_equal source_file.blob_id, job.reload.model_files.first.blob_id
    assert_equal "Curated printing notes", saved.notes

    get admin_printable_model_path(saved)
    assert_response :success
    assert_select "a[href='#{admin_job_path(job)}']", text: "##{job.id}"

    delete file_admin_job_path(job, file_id: source_file.id)
    assert_redirected_to files_admin_job_path(job)
    assert_equal 0, job.reload.model_files.count
    assert saved.reload.model_file.attached?
    assert ActiveStorage::Blob.exists?(saved.model_file.blob_id)
  end

  test "source attachment must belong to the selected job" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    job = create_print_job
    other_job = create_print_job
    other_job.model_files.attach(io: StringIO.new("synthetic other model"), filename: "other.stl", content_type: "model/stl")

    assert_no_difference "PrintableModel.count" do
      post admin_printable_models_path, params: {
        source_job_id: job.id, attachment_id: other_job.model_files.first.id,
        printable_model: { name: "Disallowed Source", code: "disallowed-source", category_id: job.category_id }
      }
    end

    assert_response :not_found
  end

  test "invalid model and preview uploads do not enter the library" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)

    assert_no_difference "PrintableModel.count" do
      post admin_printable_models_path, params: { printable_model: {
        name: "Invalid file", code: "invalid-file", category_id: @model.category_id,
        model_file: upload("model.gcode", "text/plain")
      } }
    end
    assert_response :unprocessable_content
    assert_select "[role='alert']", text: /must be an STL or 3MF file/

    assert_no_difference "PrintableModel.count" do
      post admin_printable_models_path, params: { printable_model: {
        name: "Invalid preview", code: "invalid-preview", category_id: @model.category_id,
        model_file: model_upload, preview_image: upload("preview.svg", "image/svg+xml")
      } }
    end
    assert_response :unprocessable_content
    assert_select "[role='alert']", text: /must be a JPEG, PNG, or WebP image/
  end

  test "malformed model parameter roots return bad request" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)

    assert_no_difference "PrintableModel.count" do
      post admin_printable_models_path, params: { printable_model: "invalid" }
    end
    assert_response :bad_request

    patch admin_printable_model_path(@model), params: { printable_model: ["invalid"] }
    assert_response :bad_request
    assert_equal "Sample Model", @model.reload.name
  end

  test "library uploads reject arbitrary signed blob IDs and scalar values" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    original_blob_id = @model.model_file.blob_id
    original_name = @model.name

    [@model.model_file.blob.signed_id, "not-a-file", 123, false].each do |value|
      patch admin_printable_model_path(@model), params: { printable_model: { name: "Changed name", model_file: value } }

      assert_response :unprocessable_content
      @model.reload
      assert_equal original_name, @model.name
      assert_equal original_blob_id, @model.model_file.blob_id
    end

    assert_no_difference "PrintableModel.count" do
      post admin_printable_models_path, params: { printable_model: {
        name: "Scalar preview", code: "scalar-preview", category_id: @model.category_id,
        preview_image: @model.model_file.blob.signed_id
      } }
    end
    assert_response :unprocessable_content
  end

  test "one invalid upload prevents other replacement fields from being saved" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    original_blob_id = @model.model_file.blob_id

    patch admin_printable_model_path(@model), params: { printable_model: {
      name: "Changed name", model_file: @model.model_file.blob.signed_id,
      preview_image: upload("preview.png", "image/png")
    } }

    assert_response :unprocessable_content
    @model.reload
    assert_equal "Sample Model", @model.name
    assert_equal original_blob_id, @model.model_file.blob_id
    assert_not @model.preview_image.attached?
  end

  test "saving a multi-copy source pre-fills per-copy actual weight" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    job = create_print_job(attrs: { actual_weight: 40, slicer_weight: 80, quantity: 4 })
    job.model_files.attach(io: StringIO.new("synthetic batch model"), filename: "batch.stl", content_type: "model/stl")

    get new_admin_printable_model_path(source_job_id: job.id, attachment_id: job.model_files.first.id)

    assert_response :success
    assert_select "input[name='printable_model[weight_grams]'][value='10']"
  end

  test "invalid replacement leaves the saved model file intact" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    original_blob_id = @model.model_file.blob_id

    patch admin_printable_model_path(@model), params: { printable_model: { model_file: upload("replacement.txt", "text/plain") } }

    assert_response :unprocessable_content
    assert_equal original_blob_id, @model.reload.model_file.blob_id
  end

  test "print again creates a new linked job and retains the saved file version" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    original_job = create_print_job(status_code: "ready_for_pickup", attrs: { printable_model: @model })
    original_status = original_job.status_id
    patron = create_patron

    get new_admin_job_path(printable_model_id: @model.id)

    assert_response :success
    assert_select "input[name='job[printable_model_id]'][value='#{@model.id}']"

    assert_difference "Job.count", 1 do
      post admin_jobs_path, params: { job: {
        type: "PrintJob", patron_id: patron.id, printable_model_id: @model.id,
        category_id: @model.category_id, status_id: ensure_status("pending").id,
        pickup_location: ensure_pickup_location.code, quantity: 2
      } }
    end

    reprint = Job.order(:id).last
    assert_redirected_to admin_job_path(reprint)
    assert_equal @model.id, reprint.printable_model_id
    assert_equal 2, reprint.quantity
    assert_equal @model.model_file.blob_id, reprint.model_files.first.blob_id
    assert_equal original_status, original_job.reload.status_id
    saved_blob_id = reprint.model_files.first.blob_id

    patch admin_printable_model_path(@model), params: { printable_model: { model_file: upload("new-version.stl", "model/stl") } }

    assert_redirected_to admin_printable_model_path(@model)
    assert_not_equal saved_blob_id, @model.reload.model_file.blob_id
    assert_equal saved_blob_id, reprint.reload.model_files.first.blob_id
  end

  test "bulk delete preserves all models when one is in print history" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    unused = PrintableModel.create!(name: "Unused Model", code: "unused-model", category: @model.category, position: -1)
    create_print_job(attrs: { printable_model: @model })

    post bulk_destroy_admin_printable_models_path, params: { ids: [unused.id, @model.id] }

    assert_redirected_to admin_printable_models_path
    assert_match "No models were deleted", flash[:alert]
    assert PrintableModel.exists?(unused.id)
    assert PrintableModel.exists?(@model.id)
  end

  test "model exports allowlist metadata and protect formula cells" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    @model.update!(notes: " \uFEFF=1+1")

    get export_admin_printable_models_path(format: :csv)

    assert_response :success
    rows = CSV.parse(response.body, headers: true)
    assert_equal %w[id name code category weight_grams notes], rows.headers
    assert_equal "' \uFEFF=1+1", rows.first["notes"]

    get export_admin_printable_models_path(format: :json)

    assert_response :success
    assert_equal %w[category code id name notes weight_grams], JSON.parse(response.body).first.keys.sort
    assert_not_includes response.body, @model.model_file.blob.key

    get export_admin_printable_models_path(format: :xml)

    assert_response :success
    assert_includes response.body, "sample-model"
    assert_not_includes response.body, @model.model_file.blob.key
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

  def upload(filename, content_type)
    Rack::Test::UploadedFile.new(StringIO.new("synthetic file contents"), content_type, original_filename: filename)
  end
end
