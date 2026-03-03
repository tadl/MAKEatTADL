# app/models/scan_job.rb
class ScanJob < Job
  self.table_name = 'jobs'

  # Photo uploaded by the patron for scan requests
  has_one_attached :scan_image

  # --- Validations ---
  validates :category, presence: true
  validates :status,   presence: true

  # Scan‐specific
  validates :spray_ok, inclusion: { in: [true, false] }
  validates :notes,    length: { maximum: 500 }, allow_blank: true

  # Strict server-side allowlist for the scan image
  validate :scan_image_must_be_allowed_photo_type

  # If staff later attach printable model files to a ScanJob, flip it to a PrintJob.
  # Use after_commit so the ActiveStorage attachments are present.
  after_commit :convert_to_print_job_if_model_attached, on: %i[create update]

  private

  def scan_image_must_be_allowed_photo_type
    return unless scan_image.attached?

    blob         = scan_image.blob
    content_type = (blob.content_type || '').downcase
    ext          = File.extname(blob.filename.to_s).downcase

    # Accept common Apple & web photo formats
    allowed_cts  = %w[image/jpeg image/png image/heic image/heif image/heic-sequence image/heif-sequence]
    allowed_exts = %w[.jpg .jpeg .png .heic .heif]

    ok = allowed_cts.include?(content_type) && allowed_exts.include?(ext)
    unless ok
      errors.add(:scan_image, 'must be a PNG, JPEG, or HEIC (.png, .jpg, .jpeg, .heic, .heif)')
      scan_image.purge_later if persisted?
    end
  end

  def convert_to_print_job_if_model_attached
    return unless self.type == 'ScanJob'
    return unless model_files.attached?
    return unless model_files.any? { |f| f.filename.extension&.downcase.in?(%w[stl 3mf]) }

    update_column(:type, 'PrintJob')
  end
end
