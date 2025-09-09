# app/models/scan_job.rb
class ScanJob < Job
  self.table_name = 'jobs'

  # Photo uploaded by the patron for scan requests
  has_one_attached :scan_image

  validates :category, presence: true
  validates :status,   presence: true

  # Scan‐specific
  validates :spray_ok, inclusion: { in: [true, false] }
  validates :notes,    length: { maximum: 500 }, allow_blank: true

  # If staff later attach STL(s) to a ScanJob, flip it to a PrintJob.
  # Use after_commit so the ActiveStorage attachments are present.
  after_commit :convert_to_print_job_if_stl_attached, on: %i[create update]

  private

  def convert_to_print_job_if_stl_attached
    # Only for ScanJob records
    return unless self.type == 'ScanJob'

    # Only convert if we truly have at least one STL file attached
    return unless model_files.attached?
    return unless model_files.any? { |f| f.filename.extension&.downcase == 'stl' }

    # Flip STI type without callbacks to avoid loops
    update_column(:type, 'PrintJob')
  end
end
