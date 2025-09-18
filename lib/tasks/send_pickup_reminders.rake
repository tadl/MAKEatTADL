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
namespace :print_jobs do
  desc "Preview (dry run) which pickup reminders would be sent today"
  task pickup_reminders_preview: :environment do
    today = Date.current

    jobs = Job
      .joins(:status)
      .where(statuses: { code: 'ready_for_pickup' })
      .where.not(completion_date: nil)

    ready_total   = jobs.count
    eligible_cnt  = 0
    skipped_cnt   = 0
    reasons_count = Hash.new(0)

    puts "== DRY RUN: Weekly pickup reminders preview (as of #{today}) =="
    puts "Ready-for-pickup jobs: #{ready_total}"
    puts

    jobs.find_each do |job|
      days_since     = (today - job.completion_date).to_i
      last_sent_date = job.last_pickup_reminder_sent_at&.to_date

      # Same rules as the real task:
      # - only on 7/14/21/... days since completion
      # - and not if a reminder was sent in the last 7 days
      reason = nil
      should_send = true

      if days_since <= 0
        should_send = false
        reason = "completed today (days_since=#{days_since})"
      elsif (days_since % 7) != 0
        should_send = false
        reason = "not a 7-day interval (days_since=#{days_since})"
      elsif last_sent_date && (today - last_sent_date) < 7
        should_send = false
        reason = "last reminder #{(today - last_sent_date).to_i} day(s) ago"
      end

      location_name = PickupLocation.find_by(code: job.pickup_location)&.name || job.pickup_location
      cost_str      = job.actual_cost.present? ? ('%.2f' % job.actual_cost) : '0.00'

      printf "Job #%-6d %-30s completed: %-10s (%3dd ago) last_sent: %-10s | %s\n",
             job.id,
             job.patron&.email.to_s,
             job.completion_date,
             days_since,
             (last_sent_date || '—'),
             (should_send ?
               "WOULD SEND (#{location_name}, $#{cost_str})" :
               "skip — #{reason}")

      if should_send
        eligible_cnt += 1
      else
        skipped_cnt  += 1
        reasons_count[reason] += 1 if reason
      end
    end

    puts
    puts "== Summary =="
    puts "Eligible to send now : #{eligible_cnt}"
    puts "Skipped              : #{skipped_cnt}"
    if reasons_count.any?
      puts "Skip reasons:"
      reasons_count.each { |r, c| puts "  - #{r}: #{c}" }
    end
    puts "Total considered     : #{ready_total}"
  end
end
