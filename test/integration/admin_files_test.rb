require "test_helper"

class AdminFilesTest < ActionDispatch::IntegrationTest
  setup do
    staff = create_staff_user(email: "files@example.com")
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: staff.uid,
      info: { email: staff.email, name: staff.name, image: "https://example.com/avatar.png" },
      extra: { id_info: { hd: "example.com", email_verified: true } }
    )
    with_env("GOOGLE_DOMAIN" => "example.com") do
      get "/auth/test/callback", env: { "omniauth.auth" => auth }
    end
  end

  test "staff can upload scan results without converting the job or reporting an attachment error" do
    job = create_scan_job
    path = files_admin_job_path(job)

    post path, params: {
      scan_job: { model_files: [fixture_file_upload("test-model.stl", "model/stl")] }
    }

    assert_redirected_to path
    assert_equal "1 file attached.", flash[:success]
    assert_nil flash[:error]
    assert_equal "ScanJob", job.reload.type
    assert_equal 1, job.model_files.count

    follow_redirect!
    assert_response :success
    assert_select "a", text: "test-model.stl"
  end

  test "admin job details escape model filenames while preserving previews and downloads" do
    job = create_print_job
    %w[stl 3mf].each do |extension|
      job.model_files.attach(io: StringIO.new("synthetic model #{extension}"),
        filename: "part &copy; <img src=x onerror=alert(1)>.#{extension}", content_type: "application/octet-stream")
    end

    get admin_job_path(job)

    assert_response :success
    assert_select "img[onerror]", count: 0
    assert_select "details .stlviewer[data-file-url]", count: 1
    job.model_files.each do |file|
      file_path = Rails.application.routes.url_helpers.rails_blob_path(file, only_path: true)
      assert_select "a[href='#{file_path}']", text: file.filename.to_s
    end
  end

  test "admin job details do not link legacy URLs with executable schemes" do
    job = create_print_job
    job.update_column(:url, "javascript:alert(1)//https://example.org/model")

    get admin_job_path(job)

    assert_response :success
    assert_select "a[href^='javascript:']", count: 0
    assert_includes response.body, "javascript:alert(1)//https://example.org/model"
  end

  test "catalog model previews and edit links preserve literal filenames" do
    StaffUser.find_by!(email: "files@example.com").update!(admin: true)
    model = PrintableModel.create!(name: "Catalog model", code: "catalog_model",
      category: ensure_category("Fidget"))
    model.model_file.attach(io: StringIO.new("synthetic STL"),
      filename: "catalog &copy;.stl", content_type: "model/stl")

    get admin_printable_model_path(model)

    assert_response :success
    assert_select "details .stlviewer[data-file-url]", count: 1
    assert_select "a", text: model.model_file.filename.to_s

    get edit_admin_printable_model_path(model)

    assert_response :success
    assert_select "a", text: model.model_file.filename.to_s
  end

  test "uploads append files and accept ZIP MIME only for 3MF" do
    job = create_print_job
    job.model_files.attach(io: StringIO.new("existing synthetic model"), filename: "existing.stl", content_type: "model/stl")

    post files_admin_job_path(job), params: { job: { model_files: [model_upload(filename: "test-model.3mf", content_type: "application/zip")] } }

    assert_redirected_to files_admin_job_path(job)
    assert_equal 2, job.reload.model_files.count
    assert_equal "1 file attached.", flash[:success]

    post files_admin_job_path(job), params: { job: { model_files: [model_upload(content_type: "application/zip")] } }

    assert_redirected_to files_admin_job_path(job)
    assert_equal 2, job.reload.model_files.count
    assert_match "Only STL or 3MF", flash[:alert]
  end

  test "file deletion is scoped to the current job" do
    job = create_print_job
    other = create_print_job
    other.model_files.attach(io: StringIO.new("another synthetic model"), filename: "other.stl", content_type: "model/stl")
    file = other.model_files.first

    delete file_admin_job_path(job, file_id: file.id)

    assert_response :not_found
    assert other.reload.model_files.attached?

    delete file_admin_job_path(other, file_id: file.id)

    assert_redirected_to files_admin_job_path(other)
    assert_not other.reload.model_files.attached?
  end

  test "non-upload values cannot attach existing blobs or crash the file action" do
    job = create_scan_job

    post files_admin_job_path(job), params: { job: { model_files: ["not-an-upload"] } }

    assert_redirected_to files_admin_job_path(job)
    assert_not job.reload.model_files.attached?
    assert_match "valid, nonempty", flash[:alert]

    post files_admin_job_path(job), params: { job: "not-a-parameter-object" }
    assert_redirected_to files_admin_job_path(job)
    assert_not job.reload.model_files.attached?
  end
end
