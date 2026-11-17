abort "Admin browser fixtures must run in the test environment." unless ENV.fetch("RAILS_ENV", "test") == "test"

require_relative "../test_helper"
require "base64"
require "fileutils"

# Export real templates with synthetic records, then roll every record back.
# The static browser server can serve pages.json's URL -> filename mapping.
class AdminBrowserPagesTest < ActionDispatch::IntegrationTest
  SYNTHETIC_STL = <<~STL.freeze
    solid synthetic_tetrahedron
      facet normal 0 0 -1
        outer loop
          vertex 0 0 0
          vertex 0 20 0
          vertex 20 0 0
        endloop
      endfacet
      facet normal 0 -1 0
        outer loop
          vertex 0 0 0
          vertex 20 0 0
          vertex 0 0 20
        endloop
      endfacet
      facet normal -1 0 0
        outer loop
          vertex 0 0 0
          vertex 0 0 20
          vertex 0 20 0
        endloop
      endfacet
      facet normal 0.57735 0.57735 0.57735
        outer loop
          vertex 20 0 0
          vertex 0 20 0
          vertex 0 0 20
        endloop
      endfacet
    endsolid synthetic_tetrahedron
  STL
  SYNTHETIC_PNG = Base64.strict_decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+kJr0AAAAASUVORK5CYII="
  ).freeze

  test "export the synthetic staff workspace" do
    require_local_empty_test_database!
    @directory = ENV.fetch("ADMIN_BROWSER_PAGES")
    FileUtils.mkdir_p(@directory)
    @pages = {}
    ensure_base_lookups!

    @staff = create_staff_user(email: "morgan@example.com", name: "Morgan Example", admin: true)
    @staff.update!(avatar_url: "https://example.org/synthetic-avatar.png", theme: "system", ui_density: "normal")
    colleague = create_staff_user(email: "taylor@example.com", name: "Taylor Example")
    @location = ensure_pickup_location(code: "synthetic_workshop", name: "Example Workshop")
    @printer = Printer.create!(name: "Example FDM printer", pickup_location: @location,
      print_type: PrintType.find_by!(code: "fdm"), printer_model: "Synthetic Printer 200",
      bed_size: "220 × 220 × 250 mm", location: "Example workbench", public: true)
    FilamentColor.find_or_create_by!(code: "black") { |color| color.name = "Black"; color.rgb = "#252525" }
    FilamentColor.find_or_create_by!(code: "blue") { |color| color.name = "Blue"; color.rgb = "#2563eb" }

    @patrons = [
      create_patron(email: "avery@example.com", name: "Avery Example"),
      create_patron(email: "jordan@example.com", name: "Jordan Example"),
      create_patron(email: "riley@example.com", name: "Riley Example")
    ]
    @model = PrintableModel.create!(name: "Cable organizer", code: "example-cable-organizer",
      category: Category.find_by!(name: "Fidget"), weight_grams: 18,
      notes: "Synthetic demonstration model. Successful test: 0.20 mm layers, 15% infill, PLA. Check the mounting holes before printing.")
    @model.model_file.attach(io: StringIO.new(SYNTHETIC_STL), filename: "example-cable-organizer.stl", content_type: "model/stl")
    @model.preview_image.attach(io: StringIO.new(SYNTHETIC_PNG), filename: "example-preview.png", content_type: "image/png")
    second_model = PrintableModel.create!(name: "Page-turning aid", code: "example-page-turner",
      category: Category.find_by!(name: "Assistive"), weight_grams: 24,
      notes: "Synthetic example for reviewing grip shape. Confirm dimensions before preparing a print.")
    second_model.model_file.attach(io: StringIO.new(SYNTHETIC_STL), filename: "example-page-turner.stl", content_type: "model/stl")
    legacy_category = Category.create!(name: "Patron", position: 99)
    legacy_model = PrintableModel.create!(name: "Workshop hook", code: "example-workshop-hook",
      category: legacy_category, weight_grams: 14, notes: "Synthetic staff-only model for reviewing legacy library collections.")
    legacy_model.model_file.attach(io: StringIO.new(SYNTHETIC_STL), filename: "example-workshop-hook.stl", content_type: "model/stl")
    PrintableModel.create!(name: "Missing model file", code: "example-missing-file",
      category: Category.find_by!(name: "Staff"), notes: "Synthetic catalog entry awaiting its actual model file.")
    photo_only_model = PrintableModel.create!(name: "Photo-only model", code: "example-photo-only-model",
      category: Category.find_by!(name: "Staff"), notes: "Synthetic legacy entry with a supplied photo and no model file.")
    photo_only_model.preview_image.attach(@model.preview_image.blob)

    @job = create_print_job(patron: @patrons.first, status_code: "information_requested",
      attrs: { pickup_location: @location.code, printable_model: @model, filament_color: "blue",
        print_type_code: "fdm", slicer_weight: 18, print_time_estimate: 95, quantity: 1,
        notes: "Synthetic request: please keep the mounting holes at 4 mm. This record is for layout review only." })
    @job.model_files.attach(@model.model_file.blob)
    reply = @job.conversation.messages.create!(author: @patrons.first,
      body: "The estimate works for me. Please use blue filament if it is available.")
    note = @job.conversation.messages.create!(author: colleague, staff_note_only: true,
      body: "Synthetic internal note: the test fit looks good. @morgan please check the mounting holes before printing.")
    Notification.create!(staff_user: @staff, message: note)

    %w[pending approved in_progress ready_for_pickup ongoing archived].each_with_index do |status, index|
      attributes = { pickup_location: @location.code, filament_color: "black", print_type_code: "fdm",
        quantity: index + 1, notes: "Synthetic #{status.humanize.downcase} request for interface review.",
        created_at: (index + 1).days.ago }
      attributes[:assigned_printer] = @printer if %w[in_progress ready_for_pickup archived].include?(status)
      if %w[ready_for_pickup archived].include?(status)
        attributes.merge!(completion_date: 2.days.ago.to_date, actual_weight: 24,
          finished_by: @staff, finished_at: 2.days.ago)
      end
      attributes[:pickup_date] = Date.yesterday if status == "archived"
      example_job = create_print_job(patron: @patrons[index % @patrons.size], status_code: status,
        category_name: status == "ongoing" ? "Staff" : "Patron", attrs: attributes)
      @ready_job = example_job if status == "ready_for_pickup"
    end
    create_scan_job(patron: @patrons.last,
      attrs: { pickup_location: @location.code, notes: "Synthetic scan request: small replacement handle.", spray_ok: true })
    prepare_pagination_jobs

    sign_in_synthetic_staff
    export_page(admin_root_path, "overview.html")
    export_page(admin_jobs_path, "jobs.html")
    export_page(admin_jobs_path(page: 2, per_page: 25), "jobs-page-2.html")
    export_page(admin_jobs_path(page: 7, per_page: 25), "jobs-middle-page.html")
    last_page = (Job.active.count / 25.0).ceil
    export_page(admin_jobs_path(page: last_page, per_page: 25), "jobs-last-page.html")
    export_page(admin_jobs_path(per_page: 50), "jobs-50.html")
    export_page(admin_jobs_path(per_page: 100), "jobs-100.html")
    export_page(admin_job_path(@job), "job.html")
    export_page(admin_job_path(@ready_job), "job-ready.html")
    export_page(edit_admin_job_path(@job), "job-edit.html")
    export_page(conversation_admin_job_path(@job), "job-conversation.html")
    export_page(files_admin_job_path(@job), "job-files.html")
    export_page(new_admin_job_path, "job-new.html")
    export_page(admin_patrons_path, "patrons.html")
    export_page(admin_patron_path(@patrons.first), "patron.html")
    export_page(merge_admin_patron_path(@patrons.second), "patron-merge.html")
    export_page(admin_printable_models_path, "models.html")
    export_page(admin_printable_model_path(@model), "model.html")
    export_page(edit_admin_printable_model_path(@model), "model-edit.html")
    export_page(new_admin_printable_model_path, "model-new.html")
    export_page(admin_resources_path(resource: "printers"), "printers.html")
    export_page(admin_resource_path(resource: "printers", id: @printer.id), "printer.html")
    export_page(edit_admin_resource_path(resource: "printers", id: @printer.id), "printer-edit.html")
    export_page(admin_resources_path(resource: "pickup_locations"), "locations.html")
    export_page(admin_resources_path(resource: "audits"), "activity.html")
    export_page(admin_stats_path, "statistics.html")
    export_page(admin_help_path, "help.html")
    export_page(submit_print_path, "public-submit-print.html")

    export_attachment(@model.model_file, "synthetic-model.stl", SYNTHETIC_STL)
    export_attachment(second_model.model_file, "synthetic-model.stl", SYNTHETIC_STL)
    export_attachment(legacy_model.model_file, "synthetic-model.stl", SYNTHETIC_STL)
    export_attachment(@job.model_files.first, "synthetic-model.stl", SYNTHETIC_STL)
    export_attachment(@model.preview_image, "synthetic-preview.png", SYNTHETIC_PNG)
    export_attachment(photo_only_model.preview_image, "synthetic-preview.png", SYNTHETIC_PNG)
    [second_model, legacy_model].each { |model| export_thumbnail(model, "synthetic-thumbnail.svg") }
    File.binwrite(File.join(@directory, "synthetic-avatar.png"), SYNTHETIC_PNG)

    # Real role/preference renders under fixture-only static aliases. These are
    # not application routes or authentication bypasses.
    sign_in_synthetic_staff(colleague)
    export_page(admin_jobs_path, "staff-jobs.html", fixture_path: "/__fixtures__/staff-jobs")
    @staff.update!(theme: "dark", ui_density: "condensed")
    sign_in_synthetic_staff
    export_page(admin_jobs_path, "jobs-dark-condensed.html", fixture_path: "/__fixtures__/jobs-dark-condensed")
    @staff.update!(theme: "system", ui_density: "normal")
    File.write(File.join(@directory, "pages.json"), JSON.pretty_generate(@pages))

    # Opening a conversation marks its reply read, as in the real workspace.
    assert_not_nil reply.reload.read_at
  end

  private

  def require_local_empty_test_database!
    configuration = ActiveRecord::Base.connection_db_config
    assert Rails.env.test?, "This renderer requires Rails' test environment."
    assert_match(/(?:\A|_)test\z/, configuration.database, "Use a dedicated test database.")
    assert_includes [nil, "", "localhost", "127.0.0.1", "::1"], configuration.configuration_hash[:host],
      "This renderer only supports a local test database."
    [Patron, StaffUser, Job, Conversation, Message, Notification, PrintableModel, Printer, Audited::Audit].each do |model|
      assert_equal 0, model.count, "Refusing to export existing #{model.name} records. Use an empty test database."
    end
  end

  def sign_in_synthetic_staff(staff = @staff)
    auth = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: staff.uid,
      info: { email: staff.email, name: staff.name, image: staff.avatar_url.to_s },
      extra: { id_info: { hd: "example.com", email_verified: true } })
    with_env("GOOGLE_DOMAIN" => "example.com") do
      get "/auth/test/callback", env: { "omniauth.auth" => auth }
    end
    staff.admin? ? assert_redirected_to(admin_root_path) : assert_response(:redirect)
  end

  def prepare_pagination_jobs
    # These rollback-only list snapshots need no transition callbacks, audits,
    # messages, or mail. Keep conversations valid for subsequent staff browsing.
    pending_id = Status.find_by!(code: "pending").id
    patron_category_id = Category.order(:id).find_by!(name: "Patron").id
    first_received_at = 90.days.ago.change(usec: 0)
    rows = 400.times.map do |index|
      received_at = first_received_at + index.minutes
      { type: "PrintJob", origin: "print", patron_id: @patrons[index % @patrons.size].id,
        status_id: pending_id, category_id: patron_category_id,
        pickup_location: @location.code, print_type_code: "fdm", quantity: 1,
        url: "https://example.org/synthetic-pagination-models/#{index + 1}",
        notes: "Synthetic pagination example #{index + 1}.", created_at: received_at, updated_at: received_at }
    end
    inserted = Job.insert_all!(rows, returning: %w[id created_at updated_at]).to_a
    Conversation.insert_all!(inserted.map do |job|
      { job_id: job.fetch("id"), conversation_token: "synthetic-browser-job-#{job.fetch('id')}",
        created_at: job.fetch("created_at"), updated_at: job.fetch("updated_at") }
    end)
  end

  def export_page(path, filename, fixture_path: path)
    get path
    assert_response :success, "Failed to render #{filename}."
    File.write(File.join(@directory, filename), response.body)
    @pages[fixture_path] = filename
  end

  def export_attachment(attachment, filename, content)
    path = Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true)
    @pages[path] = filename
    File.binwrite(File.join(@directory, filename), content)
  end

  def export_thumbnail(model, filename)
    path = thumbnail_admin_printable_model_path(model)
    get path
    assert_response :success
    assert_equal "image/svg+xml", response.media_type
    assert_includes response.body, "<polygon", "The fixture thumbnail must render the actual synthetic mesh."
    @pages[path] = filename
    File.write(File.join(@directory, filename), response.body)
  end
end
