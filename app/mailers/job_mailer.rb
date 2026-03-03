# app/mailers/job_mailer.rb
class JobMailer < ApplicationMailer
  def job_received(job)
    @job          = job
    @patron       = job.patron
    @conversation = @job.conversation || @job.create_conversation!

    @patron.regenerate_access_token!
    @url          = job_url(@job, token: @patron.access_token)

    reply_address = conversation_reply_address(@conversation)

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
    reply_address = conversation_reply_address(@conversation)

    job_label = @job.is_a?(PrintJob) ? "print" : "scan"

    mail to:      @patron.email,
         from:    reply_address,
         reply_to: reply_address,
         subject: "New message on your #{job_label} job ##{@job.id}"
  end

  def job_in_progress(job)
    @job          = job
    @patron       = job.patron
    @conversation = job.conversation || job.create_conversation!

    @patron.regenerate_access_token!
    @url = job_url(@job, token: @patron.access_token)

    reply_address = conversation_reply_address(@conversation)

    printer_name  = job.assigned_printer&.name || job.assigned_printer&.printer_model || 'a library printer'
    location_name =
      job.assigned_printer&.pickup_location&.name ||
      PickupLocation.find_by(code: job.pickup_location)&.name ||
      job.pickup_location

    mail to:       @patron.email,
         from:     reply_address,
         reply_to: reply_address,
         subject:  "Your print is now in progress on #{printer_name} (#{location_name})"
  end

end
