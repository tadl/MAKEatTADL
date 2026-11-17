require "test_helper"

class AdminHelperTest < ActionView::TestCase
  include Admin::AdminHelper

  test "page windows show both ends and the current neighborhood" do
    assert_equal [1, 2, 3, nil, 21, 22, 23], admin_pagination_pages(current_page: 1, total_pages: 23)
    assert_equal [1, 2, 3, nil, 10, 11, 12, 13, 14, nil, 21, 22, 23],
      admin_pagination_pages(current_page: 12, total_pages: 23)
    assert_equal [1, 2, 3, nil, 21, 22, 23], admin_pagination_pages(current_page: 23, total_pages: 23)
  end

  test "small page sets and single missing neighbors do not need ellipses" do
    assert_equal [1], admin_pagination_pages(current_page: 1, total_pages: 1)
    assert_equal (1..7).to_a, admin_pagination_pages(current_page: 1, total_pages: 7)
    assert_equal (1..10).to_a, admin_pagination_pages(current_page: 5, total_pages: 10)
  end

  test "a large collection still has a bounded set of page links" do
    pages = admin_pagination_pages(current_page: 5_000, total_pages: 10_000)
    assert_equal [1, 2, 3, nil, 4_998, 4_999, 5_000, 5_001, 5_002, nil, 9_998, 9_999, 10_000], pages
  end

  test "avatars use HTTPS profile images and reject unsafe URLs" do
    staff = StaffUser.new(avatar_url: "https://example.org/synthetic-avatar.png")
    assert_equal staff.avatar_url, admin_avatar_url(staff)
    [nil, "", "javascript:alert(1)", "http://example.org/avatar.png", "//example.org/avatar.png",
     "https://synthetic:credentials@example.org/avatar.png", "https://invalid host/avatar.png"].each do |value|
      staff.avatar_url = value
      assert_nil admin_avatar_url(staff)
    end
  end

  test "avatar fallback uses name initials or the email initial" do
    staff = StaffUser.new(name: "Morgan Example", email: "morgan@example.org")
    assert_equal "ME", admin_user_initials(staff)
    staff.name = ""
    assert_equal "M", admin_user_initials(staff)
  end
end
