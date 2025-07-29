namespace :print_jobs do
  desc "Send weekly pickup reminders for jobs in ready_for_pickup status"
  task send_pickup_reminders: :environment do
    robot = StaffUser.find_by(email: 'robot@tadl.org')
    raise "No robot user found" unless robot
    today = Date.current

    jobs = Job
      .joins(:status)
      .where(statuses: { code: 'ready_for_pickup' })
      .where.not(completion_date: nil)

    jobs.each do |job|
      days_since = (today - job.completion_date).to_i
      next unless days_since > 0 && days_since % 7 == 0  # Only on 7, 14, 21, ...

      last_sent = job.last_pickup_reminder_sent_at&.to_date
      next if last_sent && (today - last_sent) < 7

      location_name = PickupLocation.find_by(code: job.pickup_location)&.name || job.pickup_location

      body = <<~MSG.strip

        This is just a friendly reminder from MAKE at TADL that your 3D print job (##{job.id}) is ready for pickup at #{location_name}.

        It’s been #{days_since} days since we let you know your print was ready. The total cost is $#{'%.2f' % job.actual_cost}.

        If you’ve already picked up your print, thank you! If not, stop by whenever you’re ready. Let us know if you have questions.

      MSG

      msg = job.conversation.messages.create!(
        body:            body,
        author:          robot,
        staff_note_only: false
      )

      JobMailer.notify_patron(msg).deliver_later

      # Update the tracking column!
      job.update_column(:last_pickup_reminder_sent_at, Time.current)

      puts "Sent #{days_since}-day reminder for job ##{job.id} (#{job.patron.email})"
    end
  end
end
