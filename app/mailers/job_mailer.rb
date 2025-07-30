# app/mailers/job_mailer.rb
class JobMailer < ApplicationMailer
  MAIL_DOMAIN = ENV.fetch("MAILGUN_DOMAIN")

  def job_received(job)
    @job          = job
    @patron       = job.patron
    @conversation = @job.conversation || @job.create_conversation!

    @patron.regenerate_access_token!
    @url          = job_url(@job, token: @patron.access_token)

    reply_address = "MAKE at TADL <make+#{@conversation.conversation_token}@#{MAIL_DOMAIN}>"

    mail to:      @patron.email,
         from:    reply_address,
         reply_to: reply_address,
         subject: "We’ve received your #{@job.is_a?(PrintJob) ? 'print' : 'scan'} job ##{@job.id}"
  end

  def notify_patron(message)
    @message      = message
    @conversation = message.conversation
    @job          = @conversation.job
    @patron       = @job.patron

    @patron.regenerate_access_token!
    @url = job_url(@job, token: @patron.access_token)

    # use the conversation’s conversation_token for plus‐addressing
    reply_address = "MAKE at TADL <make+#{@conversation.conversation_token}@#{MAIL_DOMAIN}>"

    job_label = @job.is_a?(PrintJob) ? "print" : "scan"

    mail to:      @patron.email,
         from:    reply_address,
         reply_to: reply_address,
         subject: "New message on your #{job_label} job ##{@job.id}"
  end
end
