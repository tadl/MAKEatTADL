require "test_helper"

class MentionMailerTest < ActiveSupport::TestCase
  test "mentions link directly to the custom staff conversation" do
    staff = create_staff_user
    job = create_print_job
    message = job.conversation.messages.create!(body: "A staff note", author: staff, staff_note_only: true)

    mail = MentionMailer.user_mentioned(staff, message)

    assert_equal [staff.email], mail.to
    assert_includes mail.body.encoded, "/admin/jobs/#{job.id}/conversation"
  end
end
