require "test_helper"
require_relative "../../lib/development/demo_assets"

class AdminModelThumbnailsTest < ActionDispatch::IntegrationTest
  setup do
    @staff = create_staff_user
    @model = PrintableModel.create!(name: "Thumbnail model", code: "thumbnail-model", category: ensure_category("Staff"))
    @model.model_file.attach(io: StringIO.new(Development::DemoAssets.stl), filename: "thumbnail.stl", content_type: "model/stl")
  end

  test "anonymous thumbnail requests require staff authentication" do
    get thumbnail_admin_printable_model_path(@model)

    assert_redirected_to admin_login_path
  end

  test "staff can read a protected thumbnail without creating records" do
    sign_in_staff

    assert_no_difference ["ActiveStorage::Blob.count", "ActiveStorage::Attachment.count", "Audited::Audit.count"] do
      get thumbnail_admin_printable_model_path(@model)
    end

    assert_response :success
    assert_equal "image/svg+xml", response.media_type
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "default-src 'none'; sandbox", response.headers["Content-Security-Policy"]
    assert_includes response.body, "<polygon"
    assert_not_includes response.body, @model.model_file.filename.to_s
  end

  test "malformed geometry and absent files return renderable placeholders" do
    sign_in_staff
    @model.model_file.attach(io: StringIO.new("invalid mesh"), filename: "invalid.stl", content_type: "model/stl")

    get thumbnail_admin_printable_model_path(@model)

    assert_response :success
    assert_equal "image/svg+xml", response.media_type
    assert_equal ModelThumbnail.placeholder, response.body

    model_without_file = PrintableModel.create!(name: "No attached file", code: "no-attached-file", category: @model.category)
    get thumbnail_admin_printable_model_path(model_without_file)
    assert_response :success
    assert_equal ModelThumbnail.placeholder, response.body
  end

  test "unknown models remain not found" do
    sign_in_staff

    get thumbnail_admin_printable_model_path(id: 0)

    assert_response :not_found
  end

  private

  def sign_in_staff
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: @staff.uid,
      info: { email: @staff.email, name: @staff.name, image: "https://example.org/avatar.png" },
      extra: { id_info: { hd: "example.org", email_verified: true } }
    )
    with_env("GOOGLE_DOMAIN" => "example.org") do
      get "/auth/test/callback", env: { "omniauth.auth" => auth }
    end
  end
end
