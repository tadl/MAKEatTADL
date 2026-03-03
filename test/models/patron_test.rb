require "test_helper"

class PatronTest < ActiveSupport::TestCase
  test "consume_access_token invalidates a valid token" do
    patron = create_patron
    token = patron.access_token

    assert patron.consume_access_token!(token)

    patron.reload
    assert_nil patron.access_token
    assert_nil patron.token_sent_at
  end

  test "consume_access_token rejects the wrong token" do
    patron = create_patron

    assert_not patron.consume_access_token!("wrong-token")
    assert_equal patron.access_token, patron.reload.access_token
  end

  test "consume_access_token rejects expired tokens" do
    patron = create_patron
    patron.update_columns(token_sent_at: 8.days.ago)

    assert_not patron.consume_access_token!(patron.access_token)
    assert_equal patron.access_token, patron.reload.access_token
  end
end
