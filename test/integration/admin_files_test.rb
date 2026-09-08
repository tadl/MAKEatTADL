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
end
