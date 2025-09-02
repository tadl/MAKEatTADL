# app/models/print_job.rb
class PrintJob < Job
  self.table_name = 'jobs'

  # Sync print_type when a printer is assigned
  before_validation :sync_print_type_from_printer, if: :will_save_change_to_assigned_printer_id?

  # Derived costs (re)computed any time weights change
  before_validation :compute_slicer_cost, if: -> { will_save_change_to_slicer_weight? }
  before_validation :compute_actual_cost, if: -> { will_save_change_to_actual_weight? }

  # Notify flows
  after_update :send_cost_estimate_if_first_weight, if: :just_set_slicer_weight?
  after_update :finalize_and_notify_if_actual_weight_set, if: :just_set_actual_weight?

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
    self.print_type = assigned_printer.print_type
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

  # Single pricing helper
  # FDM: $0.10/g, min $1.00
  # Resin: $0.35/g, min $3.00
  def estimated_cost_for(weight_grams)
    w = weight_grams.to_f
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

  # Notify patron with estimate the first time weight is entered
  def send_cost_estimate_if_first_weight
    return unless conversation

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
  def finalize_and_notify_if_actual_weight_set
    return unless conversation

    ready_status = Status.find_by!(code: 'ready_for_pickup')
    cost         = estimated_cost_for(actual_weight)

    # Set fields without retriggering callbacks
    update_columns(
      completion_date: (completion_date.presence || Date.current),
      actual_cost:     cost,
      status_id:       ready_status.id
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
end
