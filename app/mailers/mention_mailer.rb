# app/mailers/mention_mailer.rb
class MentionMailer < ApplicationMailer
  # staff_user: the StaffUser object
  # message: the Message that mentioned them
  def user_mentioned(staff_user, message)
    @staff_user = staff_user
    @message    = message
    @job        = message.conversation.job

    # Build the RailsAdmin URL for the custom "conversation" action
    host = ActionMailer::Base.default_url_options&.[](:host) ||
           Rails.application.routes.default_url_options&.[](:host) ||
           ENV['APP_HOST'] || 'localhost:3000'

    @admin_conversation_url =
      RailsAdmin::Engine.routes.url_helpers.url_for(
        controller: 'rails_admin/main',
        action:     'conversation',
        model_name: 'job',
        id:         @job.id,
        host:       host,
        only_path:  false
      )

    mail(
      to:      @staff_user.email,
      subject: "You were mentioned in Job ##{@job.id}"
    )
  end
end
