# app/models/print_job.rb
class PrintJob < Job
  self.table_name = 'jobs'

  # Sync print_type when a printer is assigned
  before_validation :sync_print_type_from_printer, if: :will_save_change_to_assigned_printer_id?

  # Send cost estimate when slicer_cost is first set
  after_update :send_cost_estimate, if: :just_set_slicer_cost?

  # Send “ready for pickup” notice when both actual_cost and completion_date are set
  after_update :send_ready_for_pickup_notification, if: :just_set_ready_for_pickup?

  belongs_to :assigned_printer, class_name: 'Printer', optional: true

  validates :status,          presence: true
  validates :filament_color,  length: { maximum: 50 }, allow_blank: true

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

  validate :url_or_model_file_present, on: :create, if: :patron_request?

  def print_time_estimate_hm
    return if print_time_estimate.blank?
    hours = print_time_estimate / 60
    minutes = print_time_estimate % 60
    if hours > 0
      format("%d:%02d", hours, minutes)
    else
      format("%d", minutes)
    end
  end

  def print_time_estimate_hm=(value)
    return if value.blank?
    parts = value.strip.split(':').map(&:to_i)
    minutes =
      case parts.length
      when 2 then parts[0] * 60 + parts[1] # HH:MM
      when 1 then parts[0]                 # MM
      else nil
      end
    self.print_time_estimate = minutes
  end

  private

  def sync_print_type_from_printer
    return unless assigned_printer
    self.print_type = assigned_printer.print_type
  end

  def just_set_slicer_cost?
    saved_change_to_slicer_cost? &&
      slicer_cost_previously_was.blank? &&
      slicer_cost.present?
  end

  def send_cost_estimate
    return unless conversation
    info = Status.find_by!(code: 'information_requested')
    update_column(:status_id, info.id) if status_id != info.id

    msg = conversation.messages.create!(
      body: <<~EOS.strip,
        Hello,

        The estimated cost for this order is $#{'%.2f' % slicer_cost}.
        If that sounds ok, let us know and we’ll add you to the queue.

        Thank you
      EOS
      author:          Current.staff_user,
      staff_note_only: false
    )

    JobMailer.notify_patron(msg).deliver_later
  end

  def just_set_ready_for_pickup?
    saved_change_to_actual_cost? && saved_change_to_completion_date?
  end

  def send_ready_for_pickup_notification
    return unless conversation
    ready = Status.find_by!(code: 'ready_for_pickup')
    update_column(:status_id, ready.id) if status_id != ready.id

    location_name = PickupLocation.find_by(code: pickup_location)&.name || pickup_location

    msg = conversation.messages.create!(
      body: <<~EOS.strip,
        Hello,

        Your print is complete and ready for pickup at #{location_name}.
        The total cost is $#{'%.2f' % actual_cost}.

        Thank you for using our service!
      EOS
      author:          Current.staff_user,
      staff_note_only: false
    )

    JobMailer.notify_patron(msg).deliver_later
  end
end
