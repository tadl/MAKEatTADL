require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "patron replies move information requested jobs to response received" do
    patron = create_patron
    job = create_print_job(patron: patron, status_code: "information_requested")

    job.conversation.messages.create!(body: "Here is the missing info", author: patron)

    assert_equal "response_received", job.reload.status.code
  end

  test "staff notes do not change job status" do
    patron = create_patron
    staff = create_staff_user(email: "staff-note@tadl.org")
    job = create_print_job(patron: patron, status_code: "information_requested")

    job.conversation.messages.create!(body: "Internal note", author: staff, staff_note_only: true)

    assert_equal "information_requested", job.reload.status.code
  end

  test "mark_read sets read_at" do
    patron = create_patron
    job = create_print_job(patron: patron)
    message = job.conversation.messages.create!(body: "Unread", author: patron)

    assert_nil message.read_at

    message.mark_read!

    assert_not_nil message.reload.read_at
  end
end
