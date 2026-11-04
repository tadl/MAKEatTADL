require "test_helper"

class StaffDashboardTest < ActiveSupport::TestCase
  test "dashboard counts messages and only the current staff member's unread mentions" do
    staff = create_staff_user
    other_staff = create_staff_user
    job = create_print_job(status_code: "ready_for_pickup")
    first = job.conversation.messages.create!(author: job.patron, body: "First reply")
    second = job.conversation.messages.create!(author: job.patron, body: "Second reply")
    job.conversation.messages.create!(author: job.patron, body: "Already read", read_at: Time.current)
    note = job.conversation.messages.create!(author: staff, body: "Staff note", staff_note_only: true)
    Notification.create!(staff_user: staff, message: note)
    Notification.create!(staff_user: staff, message: first, read_at: Time.current)
    Notification.create!(staff_user: other_staff, message: second)

    dashboard = StaffDashboard.new(staff_user: staff)

    assert_equal 1, dashboard.job_counts[job.status_id]
    assert_equal [job.id], dashboard.ready_jobs.map(&:id)
    assert_equal({ job.id => 2 }, dashboard.unread_counts)
    assert_equal({ job.id => 1 }, dashboard.mention_counts)
    assert_equal job.patron, dashboard.message_jobs.fetch(job.id).patron
    assert_equal "Woodmere", dashboard.pickup_location_names[job.pickup_location]
  end

  test "dashboard queries stay bounded as statuses and unread jobs grow" do
    staff = create_staff_user
    add_unread_job(staff, 0)
    StaffDashboard.new(staff_user: staff)
    small_queries = capture_selects { read_dashboard(staff) }

    9.times { |index| add_unread_job(staff, index + 1) }
    large_queries = capture_selects { read_dashboard(staff) }

    assert_operator large_queries.size, :<=, small_queries.size
  end

  private

  def read_dashboard(staff)
    dashboard = StaffDashboard.new(staff_user: staff)
    dashboard.ready_jobs.each { |job| job.patron.name }
    dashboard.message_jobs.each_value { |job| job.patron.name }
  end

  def add_unread_job(staff, index)
    ensure_status("dashboard_status_#{index}")
    job = create_print_job(status_code: "ready_for_pickup")
    message = job.conversation.messages.create!(author: job.patron, body: "Reply #{index}")
    Notification.create!(staff_user: staff, message: message)
  end
end
