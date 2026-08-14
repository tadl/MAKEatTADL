require "test_helper"

class InformationRequestAutomationTest < ActiveSupport::TestCase
  test "entering information requested records when the response window started" do
    job = create_print_job

    assert_changes -> { job.information_requested_at }, from: nil do
      job.update!(status: Status.find_by!(code: "information_requested"))
    end

    assert_in_delta Time.current, job.information_requested_at, 1.second
  end

  test "re-entering information requested starts a new response window" do
    job = create_print_job(status_code: "information_requested")
    first_anchor = job.information_requested_at

    travel 1.day do
      job.update!(status: Status.find_by!(code: "approved"))
      job.update!(status: Status.find_by!(code: "information_requested"))

      assert_operator job.information_requested_at, :>, first_anchor
      assert_in_delta Time.current, job.information_requested_at, 1.second
    end
  end

  test "entering estimated weight starts the response window when the quote is sent" do
    job = create_print_job(attrs: { print_type: ensure_print_type("resin", name: "Resin") })
    staff = create_staff_user

    Current.staff_user = staff
    job.update!(slicer_weight: 11.66)

    job.reload
    assert_equal "information_requested", job.status.code
    assert_in_delta Time.current, job.information_requested_at, 1.second
    assert_equal 4.08, job.slicer_cost
  ensure
    Current.staff_user = nil
  end

  test "sending a quote refreshes an existing response window" do
    job = create_print_job(
      status_code: "information_requested",
      attrs: { print_type: ensure_print_type("resin", name: "Resin") }
    )
    staff = create_staff_user
    old_anchor = 3.months.ago
    job.update_columns(
      information_requested_at: old_anchor,
      last_quote_reminder_sent_at: 2.months.ago
    )

    Current.staff_user = staff
    job.update!(slicer_weight: 11.66)

    assert_operator job.reload.information_requested_at, :>, old_anchor
    assert_in_delta Time.current, job.information_requested_at, 1.second
    assert_nil job.last_quote_reminder_sent_at
  ensure
    Current.staff_user = nil
  end
end
