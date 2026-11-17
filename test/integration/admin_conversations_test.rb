require "test_helper"
require "base64"

class AdminConversationsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @staff = create_staff_user(email: "conversation-operator@example.com")
    auth = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: @staff.uid,
      info: { email: @staff.email, name: @staff.name }, extra: { id_info: { hd: "example.com", email_verified: true } })
    with_env("GOOGLE_DOMAIN" => "example.com") { get "/auth/test/callback", env: { "omniauth.auth" => auth } }
    @job = create_print_job
  end

  test "opening a conversation marks patron messages and only this staff member's mentions read" do
    patron_message = @job.conversation.messages.create!(body: "A patron reply", author: @job.patron)
    note = @job.conversation.messages.create!(body: "Private discussion", author: @staff, staff_note_only: true)
    other = create_staff_user
    mine = Notification.create!(staff_user: @staff, message: note)
    theirs = Notification.create!(staff_user: other, message: note)

    get conversation_admin_job_path(@job)

    assert_response :success
    assert_not_nil patron_message.reload.read_at
    assert_not_nil mine.reload.read_at
    assert_nil theirs.reload.read_at
    assert_includes response.body, "Private discussion"
  end

  test "ordinary staff replies are public and queue patron mail" do
    assert_enqueued_emails 1 do
      post conversation_admin_job_path(@job), params: { conversation: { message_body: "Your model looks good." } }
    end

    assert_redirected_to conversation_admin_job_path(@job)
    message = @job.conversation.messages.last
    assert_equal @staff, message.author
    assert_not message.staff_note_only?
    assert_equal "Your model looks good.", message.body
  end

  test "explicit staff notes do not email the patron" do
    assert_no_enqueued_emails do
      post conversation_admin_job_path(@job), params: { conversation: { message_body: "Internal preparation", staff_note_only: "1" } }
    end
    assert @job.conversation.messages.last.staff_note_only?
  end

  test "mentions force a private note and notify each matched staff user only once" do
    recipient = create_staff_user(email: "specialist@example.com")
    with_env("GOOGLE_DOMAIN" => "example.com") do
      assert_enqueued_emails 1 do
        post conversation_admin_job_path(@job), params: { conversation: { message_body: "@specialist please review. Thanks @specialist", staff_note_only: "0" } }
      end
    end

    message = @job.conversation.messages.last
    assert message.staff_note_only?
    assert_equal [recipient.id], message.notifications.pluck(:staff_user_id)
    assert_enqueued_email_with MentionMailer, :user_mentioned, args: [recipient, message]
  end

  test "unknown mentions still force privacy without sending email" do
    with_env("GOOGLE_DOMAIN" => "example.com") do
      assert_no_enqueued_emails do
        post conversation_admin_job_path(@job), params: { conversation: { message_body: "@missing-person take a look" } }
      end
    end
    assert @job.conversation.messages.last.staff_note_only?
  end

  test "empty messages show errors and do not send mail" do
    assert_no_difference -> { @job.conversation.messages.count } do
      assert_no_enqueued_emails do
        post conversation_admin_job_path(@job), params: { conversation: { message_body: " " } }
      end
    end
    assert_response :unprocessable_content
    assert_includes response.body, "Body can&#39;t be blank"
  end

  test "malformed conversation envelopes return bad request without saving or sending" do
    assert_no_difference -> { @job.conversation.messages.count } do
      assert_no_enqueued_emails do
        ["not-an-object", "", []].each do |payload|
          post conversation_admin_job_path(@job), params: { conversation: payload }, as: :json
          assert_response :bad_request
        end
      end
    end
  end

  test "invalid image values do not partially save a conversation message" do
    ["not-a-signed-blob-id", ["not-a-signed-blob-id"], { filename: "not-an-upload" }].each do |images|
      assert_no_difference -> { @job.conversation.messages.count } do
        assert_no_enqueued_emails do
          post conversation_admin_job_path(@job), params: { conversation: { message_body: "Synthetic reply", images: images } }
        end
      end
      assert_response :unprocessable_content
      assert_includes response.body, "must be nonempty JPEG, PNG, GIF, WebP, or HEIC uploads"
    end

    assert_no_difference -> { @job.conversation.messages.count } do
      assert_no_enqueued_emails do
        post conversation_admin_job_path(@job), params: { conversation: { message_body: "Synthetic reply", images: [model_upload] } }
      end
    end
    assert_response :unprocessable_content
  end

  test "valid image uploads are saved with their message" do
    png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")
    image = Rack::Test::UploadedFile.new(StringIO.new(png), "image/png", original_filename: "synthetic.png")

    assert_difference -> { @job.conversation.messages.count }, 1 do
      assert_enqueued_emails 1 do
        post conversation_admin_job_path(@job), params: { conversation: { message_body: "Reference photo", images: [image] } }
      end
    end

    assert_redirected_to conversation_admin_job_path(@job)
    message = @job.conversation.messages.last
    assert_equal ["synthetic.png"], message.images.map { |attachment| attachment.filename.to_s }
  end

  test "conversation renders message text as escaped content" do
    @job.conversation.messages.create!(body: "<script>alert('synthetic')</script>Visible text", author: @staff)

    get conversation_admin_job_path(@job)

    assert_response :success
    assert_select "article script", count: 0
    assert_includes response.body, "Visible text"
  end
end
