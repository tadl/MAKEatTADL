# app/models/print_job.rb
class PrintJob < Job
  self.table_name = 'jobs'

  # after you assign a printer, sync its print_type
  before_validation :sync_print_type_from_printer, if: :will_save_change_to_assigned_printer_id?

  after_update :send_cost_estimate, if: :just_set_slicer_cost?

  belongs_to :assigned_printer,
             class_name: 'Printer',
             optional:   true

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

  private

  def sync_print_type_from_printer
    return unless assigned_printer
    self.print_type = assigned_printer.print_type
  end

  def patron_request?
    category&.name == 'Patron'
  end

  def url_or_model_file_present
    if url.blank? && !model_file.attached?
      errors.add(:base, "You must provide either a file upload or a URL")
    end
  end

  def just_set_slicer_cost?
    saved_change_to_slicer_cost? &&
      slicer_cost_previously_was.blank? &&
      slicer_cost.present?
  end

  def send_cost_estimate
    return unless conversation     # ensure there's a conversation
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

    # fire off the mailing
    JobMailer.notify_patron(msg).deliver_later
  end
end
