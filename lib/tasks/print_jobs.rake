# lib/tasks/print_jobs.rake
module PrintJobsTasks
  module_function

  # ---------- Shared helpers ----------

  def robot_user!
    StaffUser.find_by(email: 'robot@tadl.org') ||
      raise("No robot user found (robot@tadl.org)")
  end

  def location_name_for(job)
    PickupLocation.find_by(code: job.pickup_location)&.name || job.pickup_location
  end

  def ensure_conversation!(job)
    job.build_conversation! unless job.conversation
  end

  # ---------- Info Requested helpers ----------

  def info_requested_scope
    PrintJob
      .joins(:status)
      .where(statuses: { code: 'information_requested' })
      .includes(conversation: :messages)
  end

  def last_public_message_at(job)
    job.conversation&.messages&.where(staff_note_only: false)&.maximum(:created_at)
  end

  def category_is_patron?(job)
    job.category&.name == 'Patron'
  end

  def can_send_quote?(job)
    category_is_patron?(job) && job.slicer_cost.to_f > 0
  end

  def resend_quote!(job, author)
    ensure_conversation!(job)
    msg = job.conversation.messages.create!(
      body: <<~EOS.strip,
        Hello,

        Just checking in — the estimated cost for this order is $#{format('%.2f', job.slicer_cost)}.
        If that sounds ok, reply here and we’ll add you to the print queue.

        Thank you
      EOS
      author:          author,
      staff_note_only: false
    )
    JobMailer.notify_patron(msg).deliver_later
  end

  def cancel_job!(job, author)
    prev = Current.staff_user
    Current.staff_user = author
    begin
      cancelled = Status.find_by!(code: 'cancelled')
      job.update!(status: cancelled) # triggers callback to notify the patron
    ensure
      Current.staff_user = prev
    end
  end

  # ---------- Pickup Reminder helpers ----------

  def ready_for_pickup_scope
    Job
      .joins(:status)
      .where(statuses: { code: 'ready_for_pickup' })
      .where.not(completion_date: nil)
  end

  # Next reminder is due 7 days after the later of completion_date or last reminder
  def next_pickup_reminder_due_date(job)
    anchor = job.last_pickup_reminder_sent_at&.to_date || job.completion_date
    anchor + 7
  end

  # Intuitive due/overdue rule (no modulo): send if today >= next_due
  def should_send_pickup_reminder?(job, today)
    return [false, "no completion_date"] if job.completion_date.blank?

    next_due = next_pickup_reminder_due_date(job)
    if today >= next_due
      [true, nil]
    else
      days_left = (next_due - today).to_i
      [false, "next due in #{days_left} day(s)"]
    end
  end

  def send_pickup_reminder!(job, author, today)
    ensure_conversation!(job)
    days_since   = (today - job.completion_date).to_i
    location     = location_name_for(job)
    cost_str     = job.actual_cost.present? ? ('%.2f' % job.actual_cost) : '0.00'

    body = <<~MSG.strip

      This is just a friendly reminder from MAKE at TADL that your 3D print job (##{job.id}) is ready for pickup at #{location}.

      It’s been #{days_since} days since we let you know your print was ready. The total cost is $#{cost_str}.

      If you’ve already picked up your print, thank you! If not, stop by whenever you’re ready. Let us know if you have questions.

    MSG

    msg = job.conversation.messages.create!(
      body:            body,
      author:          author,
      staff_note_only: false
    )
    JobMailer.notify_patron(msg).deliver_later

    job.update_column(:last_pickup_reminder_sent_at, Time.current)
  end
end

namespace :print_jobs do
  # ===========================
  # Information Requested tasks
  # ===========================

  desc "Preview (dry run): follow-ups/cancellations for jobs stuck in information_requested"
  task info_requests_preview: :environment do
    include PrintJobsTasks

    today = Date.current
    jobs  = info_requested_scope

    puts "== DRY RUN: information_requested follow-ups (as of #{today}) =="
    puts "Jobs in information_requested: #{jobs.count}"
    puts

    to_nudge   = 0
    to_cancel  = 0
    skipped    = 0
    reasons    = Hash.new(0)

    jobs.find_each do |job|
      last_at = last_public_message_at(job)
      if last_at.nil?
        skipped += 1
        reasons["no public messages yet"] += 1
        printf "Job #%-6d %-30s | skip — no public messages yet\n",
               job.id, job.patron&.email.to_s
        next
      end

      days     = (today - last_at.to_date).to_i
      location = location_name_for(job)
      cost_str = job.slicer_cost.present? ? format('%.2f', job.slicer_cost) : '—'

      if days >= 14
        to_cancel += 1
        printf "Job #%-6d %-30s last_msg: %-10s (%3dd) | WOULD CANCEL (location: %s)\n",
               job.id, job.patron&.email.to_s, last_at.to_date, days, location
      elsif days >= 7
        if can_send_quote?(job)
          to_nudge += 1
          printf "Job #%-6d %-30s last_msg: %-10s (%3dd) | WOULD NUDGE (quote: $%s)\n",
                 job.id, job.patron&.email.to_s, last_at.to_date, days, cost_str
        else
          skipped += 1
          reasons["no slicer_cost or non-Patron"] += 1
          printf "Job #%-6d %-30s last_msg: %-10s (%3dd) | skip — no slicer_cost or non-Patron\n",
                 job.id, job.patron&.email.to_s, last_at.to_date, days
        end
      else
        skipped += 1
        reasons["<7 days since last public message"] += 1
        printf "Job #%-6d %-30s last_msg: %-10s (%3dd) | skip — not due yet\n",
               job.id, job.patron&.email.to_s, last_at.to_date, days
      end
    end

    puts
    puts "== Summary =="
    puts "Would nudge (send quote): #{to_nudge}"
    puts "Would cancel            : #{to_cancel}"
    puts "Skipped                 : #{skipped}"
    reasons.each { |r, c| puts "  - #{r}: #{c}" } if reasons.any?
  end

  desc "Send follow-ups/cancel jobs stuck in information_requested (7–13d nudge, ≥14d cancel)"
  task info_requests_nudge_and_cancel: :environment do
    include PrintJobsTasks

    robot = robot_user!
    today = Date.current
    jobs  = info_requested_scope

    puts "== LIVE RUN: information_requested follow-ups (#{today}) =="
    puts "Jobs in information_requested: #{jobs.count}"
    puts

    nudged    = 0
    cancelled = 0
    skipped   = 0

    jobs.find_each do |job|
      last_at = last_public_message_at(job)
      if last_at.nil?
        skipped += 1
        puts "Job ##{job.id} — skip: no public messages yet"
        next
      end

      days = (today - last_at.to_date).to_i

      if days >= 14
        cancel_job!(job, robot)
        cancelled += 1
        puts "Job ##{job.id} — CANCELLED (≥14 days since last public message)"
      elsif days >= 7
        if can_send_quote?(job)
          resend_quote!(job, robot)
          nudged += 1
          puts "Job ##{job.id} — nudged (sent quote reminder)"
        else
          skipped += 1
          puts "Job ##{job.id} — skip: no slicer_cost or non-Patron"
        end
      else
        skipped += 1
        puts "Job ##{job.id} — skip: days_since_last_public_message=#{days}"
      end
    end

    puts
    puts "== Summary =="
    puts "Nudged (quotes sent): #{nudged}"
    puts "Cancelled           : #{cancelled}"
    puts "Skipped             : #{skipped}"
  end

  # ========================
  # Pickup reminder tasks
  # ========================

  desc "Send weekly pickup reminders for jobs in ready_for_pickup status"
  task send_pickup_reminders: :environment do
    include PrintJobsTasks

    robot = robot_user!
    today = Date.current
    jobs  = ready_for_pickup_scope

    jobs.find_each do |job|
      should_send, reason = should_send_pickup_reminder?(job, today)
      unless should_send
        puts "Job ##{job.id} — skip: #{reason}"
        next
      end

      send_pickup_reminder!(job, robot, today)
      next_due = next_pickup_reminder_due_date(job) # after update_column this is anchored to today
      puts "Sent pickup reminder for job ##{job.id} (next due in #{(next_due - today).to_i} day[s])"
    end
  end

  desc "Preview (dry run) which pickup reminders would be sent today"
  task pickup_reminders_preview: :environment do
    include PrintJobsTasks

    today       = Date.current
    jobs        = ready_for_pickup_scope
    ready_total = jobs.count

    eligible_cnt  = 0
    skipped_cnt   = 0

    puts "== DRY RUN: Weekly pickup reminders preview (as of #{today}) =="
    puts "Ready-for-pickup jobs: #{ready_total}"
    puts

    jobs.find_each do |job|
      days_since = (today - job.completion_date).to_i
      last_sent  = job.last_pickup_reminder_sent_at&.to_date
      next_due   = next_pickup_reminder_due_date(job)

      should_send, reason = should_send_pickup_reminder?(job, today)

      if should_send
        overdue_days = (today - next_due).to_i
        eligible_cnt += 1
        printf "Job #%-6d %-30s completed: %-10s (%3dd ago) last_sent: %-10s | WOULD SEND (due %dd ago)\n",
               job.id,
               job.patron&.email.to_s,
               job.completion_date,
               days_since,
               (last_sent || '—'),
               overdue_days
      else
        skipped_cnt  += 1
        printf "Job #%-6d %-30s completed: %-10s (%3dd ago) last_sent: %-10s | skip — %s\n",
               job.id,
               job.patron&.email.to_s,
               job.completion_date,
               days_since,
               (last_sent || '—'),
               reason
      end
    end

    puts
    puts "== Summary =="
    puts "Eligible to send now : #{eligible_cnt}"
    puts "Skipped              : #{skipped_cnt}"
    puts "Total considered     : #{ready_total}"
  end

  desc "Nightly maintenance: nudge/cancel info-requests, then send pickup reminders"
  task nightly_maintenance: :environment do
    puts "== Nightly: info_requests_nudge_and_cancel =="

    begin
      t = Rake::Task["print_jobs:info_requests_nudge_and_cancel"]
      t.reenable
      t.invoke
    rescue => e
      warn "[nightly] info_requests_nudge_and_cancel failed: #{e.class}: #{e.message}"
    end

    puts "\n== Nightly: send_pickup_reminders =="

    begin
      t = Rake::Task["print_jobs:send_pickup_reminders"]
      t.reenable
      t.invoke
    rescue => e
      warn "[nightly] send_pickup_reminders failed: #{e.class}: #{e.message}"
    end

    puts "\n== Nightly maintenance complete =="
  end
end
