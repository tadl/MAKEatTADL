# app/models/print_job.rb
class PrintJob < Job
  self.table_name = 'jobs'

  # Sync print_type when a printer is assigned
  before_validation :sync_print_type_from_printer, if: :will_save_change_to_assigned_printer_id?

  # Calculate cost & notify when slicer_weight is first set
  after_update :calculate_cost_and_send_estimate, if: :just_set_slicer_weight?

  # Send “ready for pickup” notice when both actual_cost and completion_date are set
  after_update :send_ready_for_pickup_notification, if: :just_set_ready_for_pickup?

  # Disallow manual updates to slicer_cost (it’s derived)
  before_validation :prevent_manual_slicer_cost_change, on: :update

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
    if hours > 0
      format("%d:%02d", hours, minutes)
    else
      format("%d", minutes)
    end
  end

  def print_time_estimate_hm=(value)
    return if value.blank?
    parts   = value.strip.split(':').map(&:to_i)
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

  # First time slicer_weight gets set
  def just_set_slicer_weight?
    saved_change_to_slicer_weight? &&
      slicer_weight_previously_was.blank? &&
      slicer_weight.present?
  end

  # Pricing: FDM $0.10/g min $1.00; Resin $0.35/g min $3.00; default to FDM if unknown
  def compute_estimated_cost_from(weight_grams)
    w = weight_grams.to_f
    if print_type&.code == 'resin'
      [0.35 * w, 3.00].max
    else
      [0.10 * w, 1.00].max
    end
  end

  # When weight is first set: compute & persist cost (override any manual value), then notify
  def calculate_cost_and_send_estimate
    estimated = compute_estimated_cost_from(slicer_weight)
    update_column(:slicer_cost, estimated) # force our computed value
    send_cost_estimate(estimated)
  end

  # Block manual edits to slicer_cost unless weight is changing (we’ll overwrite anyway)
  def prevent_manual_slicer_cost_change
    if will_save_change_to_slicer_cost? && !will_save_change_to_slicer_weight?
      self.slicer_cost = slicer_cost_was
      errors.add(:slicer_cost, 'is calculated automatically from slicer weight')
    end
  end

  # Send the “cost estimate” message and move status to information_requested
  def send_cost_estimate(amount)
    return unless conversation
    info = Status.find_by!(code: 'information_requested')
    update_column(:status_id, info.id) if status_id != info.id

    msg = conversation.messages.create!(
      body: <<~EOS.strip,
        Hello,

        The estimated cost for this order is $#{format('%.2f', amount)}.
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
