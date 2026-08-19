require "test_helper"
require "rake"

load Rails.root.join("lib/tasks/print_jobs.rake") unless defined?(PrintJobsTasks)

class PrintJobsTasksTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  test "information request anchor ignores old messages and job creation" do
    job = create_print_job
    staff = create_staff_user
    explicit_anchor = Time.current.change(usec: 0)

    job.conversation.messages.create!(
      body: "An old patron response",
      author: job.patron,
      staff_note_only: false,
      created_at: 3.months.ago
    )
    job.conversation.messages.create!(
      body: "An unrelated old staff message",
      author: staff,
      staff_note_only: false,
      created_at: 3.months.ago
    )
    job.update!(status: Status.find_by!(code: "information_requested"))
    job.update_column(:information_requested_at, explicit_anchor)

    kind, anchor_at = PrintJobsTasks.info_request_anchor(job.reload)

    assert_equal :information_requested_at, kind
    assert_equal explicit_anchor, anchor_at
  end

  test "information request anchor is missing rather than inferred" do
    job = create_print_job(status_code: "information_requested")
    job.update_column(:information_requested_at, nil)

    assert_equal [:missing_anchor, nil], PrintJobsTasks.info_request_anchor(job.reload)
  end

  test "cancellation refuses a stale request window" do
    job = create_print_job(status_code: "information_requested")
    staff = create_staff_user
    stale_anchor = job.information_requested_at

    job.update_column(:information_requested_at, 1.day.from_now)

    assert_not PrintJobsTasks.cancel_job!(job, staff, expected_anchor_at: stale_anchor)
    assert_equal "information_requested", job.reload.status.code
  end

  test "successful cancellation is audited as the automation user" do
    job = create_print_job(status_code: "information_requested")
    robot = create_staff_user(email: "robot@tadl.org")
    anchor = job.information_requested_at

    assert_no_enqueued_jobs do
      assert_emails 1 do
        assert PrintJobsTasks.cancel_job!(job, robot, expected_anchor_at: anchor)
      end
    end

    status_audit = job.audits.reload.reverse.find do |audit|
      audit.audited_changes.key?("status_id")
    end
    assert_equal "cancelled", job.reload.status.code
    assert_equal robot, status_audit.user
  end

  test "abandonment is audited as the automation user" do
    job = create_print_job(
      status_code: "ready_for_pickup",
      attrs: { completion_date: 31.days.ago.to_date }
    )
    robot = create_staff_user(email: "robot@tadl.org")

    assert_no_enqueued_jobs do
      assert_emails 1 do
        PrintJobsTasks.abandon_job!(job, robot)
      end
    end

    status_audit = job.audits.reload.reverse.find do |audit|
      audit.audited_changes.key?("status_id")
    end
    assert_equal "abandoned", job.reload.status.code
    assert_equal robot, status_audit.user
  end

  test "pickup reminders stop when a job is eligible for abandonment" do
    job = create_print_job(
      status_code: "ready_for_pickup",
      attrs: { completion_date: 30.days.ago.to_date }
    )

    should_send, reason = PrintJobsTasks.should_send_pickup_reminder?(job, Date.current)

    assert_not should_send
    assert_equal "eligible for abandonment", reason
  end

  test "quote reminder tracking does not depend on message wording" do
    job = create_print_job(status_code: "information_requested")
    reminder_at = 2.days.ago.change(usec: 0)
    job.update_column(:last_quote_reminder_sent_at, reminder_at)

    assert_equal reminder_at, PrintJobsTasks.last_quote_nudge_at(job.reload)
  end

  test "quote reminders are delivered before the automation exits" do
    job = create_print_job(
      status_code: "information_requested",
      attrs: { slicer_cost: 4.08 }
    )
    robot = create_staff_user(email: "robot@tadl.org")

    assert_no_enqueued_jobs do
      assert_emails 1 do
        PrintJobsTasks.resend_quote!(job, robot)
      end
    end

    assert_not_nil job.reload.last_quote_reminder_sent_at
  end

  test "pickup reminders are delivered before the automation exits" do
    job = create_print_job(
      status_code: "ready_for_pickup",
      attrs: { completion_date: 8.days.ago.to_date, actual_cost: 3.25 }
    )
    robot = create_staff_user(email: "robot@tadl.org")

    assert_no_enqueued_jobs do
      assert_emails 1 do
        PrintJobsTasks.send_pickup_reminder!(job, robot, Date.current)
      end
    end

    assert_not_nil job.reload.last_pickup_reminder_sent_at
  end
end
