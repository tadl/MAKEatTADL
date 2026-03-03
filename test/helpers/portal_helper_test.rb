require "test_helper"

class PortalHelperTest < ActionView::TestCase
  include PortalHelper
  include TestSupport::DataHelper

  test "bootstrap_status_badge uses the configured status class" do
    ensure_base_lookups!
    status = Status.find_by!(code: "ready_for_pickup")

    html = bootstrap_status_badge(status)

    assert_includes html, "bg-success"
    assert_includes html, status.name
  end

  test "author_display_name hides individual staff names" do
    staff = create_staff_user(email: "helper@tadl.org", name: "Visible Name")
    patron = create_patron(name: "Patron Name")

    assert_equal "TADL Staff", author_display_name(staff)
    assert_equal "Patron Name", author_display_name(patron)
  end
end
