# app/models/scan_job.rb
class ScanJob < Job
  self.table_name = 'jobs'

  has_one_attached :scan_image

  validates :category, presence: true

  validates :status, presence: true

  after_save :convert_to_print_job, if: -> { model_file.attached? && self.type == 'ScanJob' }

  # Scan‐specific
  validates :spray_ok, inclusion: { in: [true, false] }
  validates :notes,    length: { maximum: 500 }, allow_blank: true

  private

  def convert_to_print_job
    update_column(:type, 'PrintJob')
  end
end
