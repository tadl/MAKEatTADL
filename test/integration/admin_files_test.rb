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
    path = rails_admin.files_path(model_name: "job", id: job.id)

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

    get rails_admin.show_path(model_name: "job", id: job.id)

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

    get rails_admin.show_path(model_name: "job", id: job.id)

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

    get rails_admin.show_path(model_name: "printable_model", id: model.id)

    assert_response :success
    assert_select "details .stlviewer[data-file-url]", count: 1
    assert_select "a", text: model.model_file.filename.to_s

    get rails_admin.edit_path(model_name: "printable_model", id: model.id)

    assert_response :success
    assert_select "a", text: model.model_file.filename.to_s
  end
end
