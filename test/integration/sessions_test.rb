require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  test "admin login page renders the google sign-in prompt" do
    get admin_login_path

    assert_response :success
    assert_match "Staff Login Required", response.body
    assert_match "/auth/google_oauth2", response.body
  end
end
