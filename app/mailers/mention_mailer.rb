# app/mailers/mention_mailer.rb
class MentionMailer < ApplicationMailer

  # staff_user: the StaffUser object
  # message: the Message that mentioned them
  def user_mentioned(staff_user, message)
    @staff_user = staff_user
    @message    = message
    @job        = message.conversation.job
    mail(
      to:      @staff_user.email,
      subject: "You were mentioned in Job ##{@job.id}"
    )
  end
end
