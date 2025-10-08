# app/controllers/messages_controller.rb
class MessagesController < ApplicationController
  before_action :set_conversation

  def create
    @message = @conversation.messages.build(message_params)
    @message.author = current_staff_user  # staff authored

    body = @message.body.to_s

    # --- FORCE STAFF NOTE WHENEVER THERE ARE @MENTIONS ---
    has_mentions = body.match?(/@\w+/)
    @message.staff_note_only = true if has_mentions

    if @message.save
      # Mirror RailsAdmin behavior: notify mentioned staff
      if has_mentions
        usernames = body.scan(/@(\w+)/).flatten.uniq
        usernames.each do |username|
          staff_email = "#{username}@#{ENV.fetch('GOOGLE_DOMAIN')}"
          if (staff = StaffUser.find_by(email: staff_email))
            Notification.create!(staff_user: staff, message: @message)
            MentionMailer.user_mentioned(staff, @message).deliver_later
          end
        end
      end

      # No patron email here; if you ever add one, gate it on !@message.staff_note_only
      redirect_to print_job_conversation_path(@conversation.job)
    else
      render 'conversations/show', status: :unprocessable_entity
    end
  end

  private

  def set_conversation
    @conversation = Conversation.find(params[:conversation_id])
  end

  def message_params
    params.require(:message).permit(:body)
  end
end
