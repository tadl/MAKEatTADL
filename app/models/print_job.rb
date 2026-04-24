# app/models/print_job.rb
class PrintJob < Job
  self.table_name = 'jobs'

  # Sync print_type when a printer is assigned
  before_validation :sync_print_type_from_printer, if: :will_save_change_to_assigned_printer_id?

  # Derived costs (re)computed any time material usage changes
  before_validation :compute_slicer_cost, if: -> { will_save_change_to_slicer_weight? }
  before_validation :compute_actual_cost, if: -> { will_save_change_to_actual_weight? }
  before_validation :compute_resin_cost,  if: -> { will_save_change_to_resin_volume_ml? }

  # Notify flows (🚫 suppressed when status == 'ongoing')
  after_update :send_cost_estimate_if_first_weight,       if: -> { just_set_slicer_weight? && !automations_suppressed? }
  after_update :finalize_and_notify_if_actual_weight_set, if: -> { just_set_actual_weight?  && !automations_suppressed? }
  after_update :finalize_and_notify_if_resin_volume_set,  if: -> { just_set_resin_volume?  && !automations_suppressed? }
  after_update :notify_in_progress_if_opted,              if: :should_notify_in_progress?

  def should_notify_in_progress?
    saved_change_to_status_id? &&
      Status.find(status_id).code == 'in_progress' &&
      print_notify &&
      assigned_printer&.public? &&
      !automations_suppressed?
  end

  belongs_to :assigned_printer, class_name: 'Printer', optional: true

  validates :status,         presence: true
  validates :filament_color, length: { maximum: 50 }, allow_blank: true

  validates :url,
            format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]),
                      message: 'must be a valid URL' },
            allow_blank: true

  validates :pickup_location,
            presence: true,
            inclusion: {
              in:  ->(_) { PickupLocation.active.pluck(:code) },
              message: "%{value} is not a valid pickup location"
            }

  validate :url_or_model_file_present, on: :create

  def url_or_model_file_present
    return unless category&.name&.downcase == 'patron'
    if model_files.blank? && url.blank?
      errors.add(:base, "Either a model file or a URL is required for patron jobs")
    end
  end

  def print_time_estimate_hm
    return if print_time_estimate.blank?
    hours   = print_time_estimate / 60
    minutes = print_time_estimate % 60
    hours > 0 ? format("%d:%02d", hours, minutes) : format("%d", minutes)
  end

  def print_time_estimate_hm=(value)
    return if value.blank?
    parts = value.strip.split(':').map(&:to_i)
    minutes = case parts.length
              when 2 then parts[0] * 60 + parts[1] # HH:MM
              when 1 then parts[0]                 # MM
              end
    self.print_time_estimate = minutes
  end

  private

  def sync_print_type_from_printer
    return unless assigned_printer

    # Keep print_type in sync
    self.print_type = assigned_printer.print_type

    # ✅ Do NOT auto-advance if job is explicitly marked as 'ongoing'
    blocked = %w[cancelled rejected archived ready_for_pickup abandoned ongoing]
    current = status&.code

    if current.blank? || (!blocked.include?(current) && current != 'in_progress')
      self.status = Status.find_by!(code: 'in_progress')
    end
  end

  # Treat Assistive / Staff / Fidget as "free" categories
  def free_category?
    name = category&.name
    name == 'Assistive' || name == 'Staff' || name == 'Fidget'
  end

  def resin_print?
    (print_type&.code || assigned_printer&.print_type&.code) == 'resin'
  end

  # First time slicer_weight gets set
  def just_set_slicer_weight?
    saved_change_to_slicer_weight? &&
      slicer_weight_previously_was.blank? &&
      slicer_weight.present?
  end

  # First time actual_weight gets set
  def just_set_actual_weight?
    saved_change_to_actual_weight? &&
      actual_weight_previously_was.blank? &&
      actual_weight.present?
  end

  # First time resin_volume_ml gets set
  def just_set_resin_volume?
    saved_change_to_resin_volume_ml? &&
      resin_volume_ml_previously_was.blank? &&
      resin_volume_ml.present?
  end

  # Single pricing helper
  # Patron:
  #   - FDM: $0.10/g, min $1.00
  #   - Resin: $0.35/ml, min $3.00
  # Assistive/Staff/Fidget: always $0.00
  def estimated_cost_for(weight_grams_or_volume_ml)
    return 0.00 if free_category?

    w = weight_grams_or_volume_ml.to_f
    type_code = print_type&.code || assigned_printer&.print_type&.code
    rate, minimum = (type_code == 'resin') ? [0.35, 3.00] : [0.10, 1.00]
    [(w * rate), minimum].max.round(2)
  end

  def compute_slicer_cost
    self.slicer_cost = estimated_cost_for(slicer_weight)
  end

  def compute_actual_cost
    self.actual_cost = estimated_cost_for(actual_weight)
  end

  def compute_resin_cost
    return unless resin_print?
    self.actual_cost = estimated_cost_for(resin_volume_ml)
  end

  # Notify patron with estimate the first time weight is entered — Patron only
  def send_cost_estimate_if_first_weight
    return if automations_suppressed?
    return unless conversation
    return unless category&.name == 'Patron' # suppress for Assistive/Staff/Fidget

    info = Status.find_by!(code: 'information_requested')
    update_column(:status_id, info.id) if status_id != info.id

    msg = conversation.messages.create!(
      body: <<~EOS.strip,
        Hello,

        The estimated cost for this order is $#{format('%.2f', slicer_cost)}.
        If that sounds ok, let us know and we’ll add you to the queue.

        Thank you
      EOS
      author:          Current.staff_user,
      staff_note_only: false
    )

    JobMailer.notify_patron(msg).deliver_later
  end

  # When actual_weight is first set, finalize & notify
  # - Patron: compute actual cost from weight
  # - Assistive/Staff/Fidget: force $0.00
  def finalize_and_notify_if_actual_weight_set
    return if automations_suppressed?
    return unless conversation

    ready_status = Status.find_by!(code: 'ready_for_pickup')
    cost         = free_category? ? 0.00 : estimated_cost_for(actual_weight)

    update_columns(
      completion_date: (completion_date.presence || Date.current),
      actual_cost:     cost,
      status_id:       ready_status.id,
      finished_by_id:  finished_by_id || Current.staff_user&.id,
      finished_at:     finished_at || Time.current
    )

    location_name = PickupLocation.find_by(code: pickup_location)&.name || pickup_location

    msg = conversation.messages.create!(
      body: <<~EOS.strip,
        Hello,

        Your print is complete and ready for pickup at #{location_name}.
        The total cost is $#{format('%.2f', cost)}.

        Thank you for using our service!
      EOS
      author:          Current.staff_user,
      staff_note_only: false
    )

    JobMailer.notify_patron(msg).deliver_later
  end

  # When resin_volume_ml is first set (resin prints), finalize & notify
  # - Patron: compute actual cost from resin volume
  # - Assistive/Staff/Fidget: force $0.00
  def finalize_and_notify_if_resin_volume_set
    return if automations_suppressed?
    return unless conversation
    return unless resin_print?

    ready_status = Status.find_by!(code: 'ready_for_pickup')
    cost         = free_category? ? 0.00 : estimated_cost_for(resin_volume_ml)

    update_columns(
      completion_date: (completion_date.presence || Date.current),
      actual_cost:     cost,
      status_id:       ready_status.id,
      finished_by_id:  finished_by_id || Current.staff_user&.id,
      finished_at:     finished_at || Time.current
    )

    location_name = PickupLocation.find_by(code: pickup_location)&.name || pickup_location

    msg = conversation.messages.create!(
      body: <<~EOS.strip,
        Hello,

        Your resin print is complete and ready for pickup at #{location_name}.
        The total cost is $#{format('%.2f', cost)}.

        Thank you for using our service!
      EOS
      author:          Current.staff_user,
      staff_note_only: false
    )

    JobMailer.notify_patron(msg).deliver_later
  end

  def notify_in_progress_if_opted
    return if automations_suppressed?
    return unless print_notify
    return unless assigned_printer&.public?

    build_conversation! unless conversation

    location_name =
      assigned_printer&.pickup_location&.name ||
      PickupLocation.find_by(code: pickup_location)&.name ||
      pickup_location

    # Post a visible message for the portal
    conversation.messages.create!(
      body: <<~EOS.strip,
        Hello,

        Your print has started on #{assigned_printer&.name || assigned_printer&.printer_model}.
        Location: #{location_name}.

        You can follow along or message us in your portal.
      EOS
      author:          Current.staff_user,
      staff_note_only: false
    )

    # Send the dedicated email
    JobMailer.job_in_progress(self).deliver_later
  end
end
