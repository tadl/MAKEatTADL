require "test_helper"
require "csv"
require "base64"

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

    get admin_printable_models_path(q: "Tested print setup", collection: "staff")

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

  test "collection filters have three distinct choices and group legacy patron models into staff library" do
    duplicate_patron = Category.create!(name: "Patron")
    legacy = PrintableModel.create!(name: "Legacy Staff Design", code: "legacy-staff-design", category: duplicate_patron)
    assistive = PrintableModel.create!(name: "Assistive Design", code: "assistive-design", category: ensure_category("Assistive"))
    fidget = PrintableModel.create!(name: "Fidget Design", code: "fidget-design", category: ensure_category("Fidget"))
    sign_in_staff(@staff)

    get admin_printable_models_path(collection: "staff")

    assert_response :success
    assert_equal ["All collections", "Staff library", "Assistive", "Fidget"], css_select("select[name='collection'] option").map(&:text)
    assert_select "a[href='#{admin_printable_model_path(@model)}']", minimum: 1
    assert_select "a[href='#{admin_printable_model_path(legacy)}']", minimum: 1
    assert_select "a[href='#{admin_printable_model_path(assistive)}']", count: 0
    assert_select "a[href='#{admin_printable_model_path(fidget)}']", count: 0
    assert_select "span.admin-badge", text: "Patron", count: 0

    get admin_printable_models_path(collection: "assistive", q: "Assistive Design")
    assert_response :success
    assert_select "a[href='#{admin_printable_model_path(assistive)}']", minimum: 1
    assert_select "a[href='#{admin_printable_model_path(@model)}']", count: 0
  end

  test "new model defaults to staff library and form excludes duplicate or unrelated categories" do
    @staff.update!(admin: true)
    duplicate_staff = Category.create!(name: "Staff")
    Category.create!(name: "Patron")
    sign_in_staff(@staff)

    get new_admin_printable_model_path

    assert_response :success
    assert_equal ["Staff library", "Assistive", "Fidget"], css_select("select[name='printable_model[category_id]'] option").map(&:text)
    assert_select "select[name='printable_model[category_id]'] option[selected][value='#{ensure_category('Staff').id}']", text: "Staff library"
    assert_select "select[name='printable_model[category_id]'] option[value='#{duplicate_staff.id}']", count: 0

    assert_no_difference "Category.count" do
      post admin_printable_models_path, params: { printable_model: { name: "Staff-only default", model_file: model_upload } }
    end

    saved = PrintableModel.find_by!(code: "staff-only-default")
    assert_redirected_to admin_printable_model_path(saved)
    assert_equal "Staff", saved.category.name
  end

  test "only canonical staff assistive or fidget categories can be selected on writes" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    duplicate_staff = Category.create!(name: "Staff")

    [@model.category_id, duplicate_staff.id, 999_999_999].each do |category_id|
      assert_no_difference "PrintableModel.count" do
        post admin_printable_models_path, params: { printable_model: { name: "Invalid collection", code: "invalid-collection", category_id: category_id } }
      end
      assert_response :unprocessable_content
      assert_includes response.body, "Collection must be Staff library, Assistive, or Fidget."
    end

    patch admin_printable_model_path(@model), params: { printable_model: { name: "Should not save", category_id: @model.category_id } }
    assert_response :unprocessable_content
    assert_equal "Sample Model", @model.reload.name

    %w[Assistive Fidget].each do |collection|
      post admin_printable_models_path, params: { printable_model: { name: "Public #{collection}", category_id: ensure_category(collection).id } }
      saved = PrintableModel.find_by!(code: "public-#{collection.downcase}")
      assert_redirected_to admin_printable_model_path(saved)
      assert_equal collection, saved.category.name
    end
  end

  test "partial edits preserve legacy category until a collection is explicitly chosen" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    legacy_category_id = @model.category_id

    patch admin_printable_model_path(@model), params: { printable_model: { notes: "Updated printing settings" } }
    assert_redirected_to admin_printable_model_path(@model)
    assert_equal legacy_category_id, @model.reload.category_id

    get edit_admin_printable_model_path(@model)
    assert_response :success
    assert_select "select[name='printable_model[category_id]'] option[selected]", text: "Staff library"

    patch admin_printable_model_path(@model), params: { printable_model: { category_id: ensure_category("Staff").id } }
    assert_redirected_to admin_printable_model_path(@model)
    assert_equal "Staff", @model.reload.category.name
  end

  test "model cards use generated thumbnails and uploaded previews take precedence" do
    sign_in_staff(@staff)
    get admin_printable_models_path
    assert_response :success
    assert_select "img[src='#{thumbnail_admin_printable_model_path(@model)}']", count: 1

    png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")
    @model.preview_image.attach(io: StringIO.new(png), filename: "preview.png", content_type: "image/png")
    get admin_printable_model_path(@model)
    assert_response :success
    assert_select "img[src='#{rails_blob_path(@model.preview_image)}']", count: 1
    assert_select "img[src='#{thumbnail_admin_printable_model_path(@model)}']", count: 0

    @model.model_file.detach
    get admin_printable_models_path(q: @model.name)
    assert_response :success
    assert_select "img[src='#{rails_blob_path(@model.preview_image)}']", count: 1
    assert_includes response.body, "No model file"

    get admin_printable_model_path(@model)
    assert_response :success
    assert_select "img[src='#{rails_blob_path(@model.preview_image)}']", count: 1
    assert_includes response.body, "No model file"
    assert_select "a", text: "Print again", count: 0
  end

  test "models without files show a clear placeholder and no print-again control" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    missing = PrintableModel.create!(name: "Missing File Design", code: "missing-file-design", category: ensure_category("Staff"))

    get admin_printable_models_path(q: "Missing File Design")
    assert_response :success
    assert_includes response.body, "No model file"
    assert_select "article img", count: 0

    get admin_printable_model_path(missing)
    assert_response :success
    assert_includes response.body, "No model file"
    assert_select "a", text: "Print again", count: 0
    assert_select "img[src='#{thumbnail_admin_printable_model_path(missing)}']", count: 0
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
    assert_select "textarea[name='printable_model[notes]']", text: /Estimated weight for source run: 18 g/
    assert_select "select[name='printable_model[category_id]'] option[selected]", text: "Staff library"
    assert_not_includes css_select("textarea[name='printable_model[notes]']").first.text, job.notes

    assert_difference "PrintableModel.count", 1 do
      post admin_printable_models_path, params: {
        source_job_id: job.id, attachment_id: source_file.id,
        printable_model: { name: "Saved Selected Model", code: "", category_id: ensure_category("Staff").id, notes: "Curated printing notes" }
      }
    end

    saved = PrintableModel.find_by!(code: "saved-selected-model")
    assert_redirected_to admin_printable_model_path(saved)
    assert_equal source_file.blob_id, saved.model_file.blob_id
    assert_equal source_file.blob_id, job.reload.model_files.first.blob_id
    assert_equal "Curated printing notes", saved.notes
    assert_equal "Staff", saved.category.name

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
        printable_model: { name: "Disallowed Source", code: "disallowed-source", category_id: ensure_category("Staff").id }
      }
    end

    assert_response :not_found
  end

  test "invalid model and preview uploads do not enter the library" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)

    assert_no_difference "PrintableModel.count" do
      post admin_printable_models_path, params: { printable_model: {
        name: "Invalid file", code: "invalid-file", category_id: ensure_category("Staff").id,
        model_file: upload("model.gcode", "text/plain")
      } }
    end
    assert_response :unprocessable_content
    assert_select "[role='alert']", text: /must be an STL or 3MF file/

    assert_no_difference "PrintableModel.count" do
      post admin_printable_models_path, params: { printable_model: {
        name: "Invalid preview", code: "invalid-preview", category_id: ensure_category("Staff").id,
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
        name: "Scalar preview", code: "scalar-preview", category_id: ensure_category("Staff").id,
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

  test "source notes contain only printing settings and clearly distinguish totals from per-copy defaults" do
    @staff.update!(admin: true)
    sign_in_staff(@staff)
    patron = create_patron(name: "Private Synthetic Patron", email: "private-patron@example.test")
    printer = Printer.create!(name: "Reference Printer", pickup_location: ensure_pickup_location, print_type: ensure_print_type("fdm"))
    job = create_print_job(patron: patron, status_code: "ready_for_pickup", attrs: {
      assigned_printer: printer, filament_color: "black", quantity: 4, actual_weight: 40,
      slicer_weight: 80, print_time_estimate: 150, notes: "Private synthetic request instructions",
      url: "https://example.org/private-model?token=synthetic-private-query"
    })
    job.model_files.attach(io: StringIO.new("synthetic reference model"), filename: "reference.stl", content_type: "model/stl")
    job.conversation.messages.create!(body: "Private synthetic conversation", author: patron)

    get new_admin_printable_model_path(source_job_id: job.id, attachment_id: job.model_files.first.id)

    assert_response :success
    notes = css_select("textarea[name='printable_model[notes]']").first.text
    assert_includes notes, "Printer: Reference Printer"
    assert_includes notes, "Print process: FDM"
    assert_includes notes, "Quantity in source run: 4"
    assert_includes notes, "Estimated duration for source run: 2:30"
    assert_includes notes, "Actual weight for source run: 40 g (10 g per copy)"
    assert_includes notes, "Estimated weight for source run: 80 g (20 g per copy)"
    assert_includes notes, "Default weight per copy: 10 g"
    [patron.name, patron.email, job.notes, "Private synthetic conversation", job.url].each do |private_value|
      assert_not_includes notes, private_value
    end
    assert_select "select[name='printable_model[category_id]'] option[selected]", text: "Staff library"

    post admin_printable_models_path, params: {
      source_job_id: job.id, attachment_id: job.model_files.first.id,
      printable_model: { name: "Curated settings defaults" }
    }
    saved = PrintableModel.find_by!(code: "curated-settings-defaults")
    assert_equal notes, saved.notes
    assert_equal "Staff", saved.category.name
    assert_equal 10, saved.weight_grams
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
    assert_equal %w[id name code collection weight_grams notes], rows.headers
    assert_equal "Staff library", rows.first["collection"]
    assert_equal "' \uFEFF=1+1", rows.first["notes"]

    get export_admin_printable_models_path(format: :json)

    assert_response :success
    assert_equal %w[code collection id name notes weight_grams], JSON.parse(response.body).first.keys.sort
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
