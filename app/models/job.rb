# app/models/job.rb
class Job < ApplicationRecord
  audited
  belongs_to :patron
  belongs_to :status
  belongs_to :category

  belongs_to :assigned_printer,
             class_name: 'Printer',
             optional:   true

  belongs_to :print_type,
             primary_key: :code,
             foreign_key: :print_type_code,
             optional:   true

  belongs_to :printable_model, optional: true

  # Staff tracking
  belongs_to :started_by,  class_name: 'StaffUser', optional: true
  belongs_to :finished_by, class_name: 'StaffUser', optional: true

  has_many_attached :model_files

  def model_files=(attachables)
    # RailsAdmin sends [""] if nothing was selected, don't clear files in that case!
    return if attachables == [""]
    super(attachables)
  end

  has_one :conversation, dependent: :destroy

  after_create :build_conversation!

  # Archive automatically when pickup_date is set
  after_update :archive_if_picked_up, if: :saved_change_to_pickup_date?

  after_update :notify_cancellation, if: :just_cancelled?
  after_update :notify_rejection,   if: :just_rejected?

  validates :status, presence: true

  # NEW: record what the job originated as (print|scan)
  before_validation :set_origin_default, on: :create
  validates :origin, inclusion: { in: %w[print scan] }

  # ✅ Server-side allowlist for model files
  validate :model_files_must_be_allowed_models

  # Track start/finish events when status changes
  before_save :track_information_request, if: :will_save_change_to_status_id?
  before_update :track_start_and_finish, if: :will_save_change_to_status_id?

  # Scopes for status filtering
  scope :with_status, ->(code) {
    joins(:status).where(statuses: { code: code })
  }
  scope :active,   -> { joins(:status).where.not(statuses: { code: %w[archived cancelled rejected abandoned] }) }
  scope :inactive, -> { joins(:status).where(statuses:     { code: %w[archived cancelled rejected abandoned] }) }
  scope :ongoing,  -> { with_status('ongoing') }

  # Flexible date-range scopes for stats
  scope :started_between,  ->(start_time, end_time) { where(started_at:  start_time..end_time) }
  scope :finished_between, ->(start_time, end_time) { where(finished_at: end_time ? (start_time..end_time) : start_time..start_time) }

  # --------------------
  # Automation guard �
  # --------------------
  # Returns true if this job is in a state where we should NOT run automations.
  # We currently suppress automations when the status is `ongoing`.
  def automations_suppressed?
    current_status_code == 'ongoing'
  rescue
    false
  end

  private

  # Set origin once at creation; persists through Scan→Print flips
  def set_origin_default
    self.origin = is_a?(ScanJob) ? 'scan' : (origin.presence || 'print')
  end

  def build_conversation!
    create_conversation! unless conversation
  end

  def archive_if_picked_up
    if pickup_date.present?
      archived = Status.find_by!(code: 'archived')
      update_column(:status_id, archived.id)
    end
  end

  def track_start_and_finish
    new_code = Status.find(status_id).code

    if new_code == 'in_progress' && started_by_id.nil?
      self.started_by = Current.staff_user
      self.started_at = Time.current
    end

    if new_code == 'ready_for_pickup' && finished_by_id.nil?
      self.finished_by = Current.staff_user
      self.finished_at = Time.current
    end
  end

  def track_information_request
    return unless Status.find(status_id).code == 'information_requested'

    self.information_requested_at = Time.current
    self.last_quote_reminder_sent_at = nil
  end

  # -------- Status-driven notifications --------

  def just_cancelled?
    saved_change_to_status_id? && current_status_code == 'cancelled'
  end

  def just_rejected?
    saved_change_to_status_id? && current_status_code == 'rejected'
  end

  def current_status_code
    # Avoid stale association cache by reading via id
    Status.find(status_id).code
  end

  def notify_cancellation
    build_conversation! unless conversation

    job_label = is_a?(PrintJob) ? 'print' : 'scan'

    msg = conversation.messages.create!(
      body: <<~EOS.strip,
        Hello,

        We’re writing to let you know your #{job_label} request ##{id} has been cancelled.

        If you have any questions or would like to resubmit, just reply to this message.
      EOS
      author:          Current.staff_user,
      staff_note_only: false
    )

    JobMailer.notify_patron(msg).deliver_later
  end

  def notify_rejection
    build_conversation! unless conversation

    job_label = is_a?(PrintJob) ? 'print' : 'scan'

    msg = conversation.messages.create!(
      body: <<~EOS.strip,
        Hello,

        We reviewed your #{job_label} request ##{id}, and unfortunately it has been rejected.
        This can happen for a few reasons (e.g., technical limitations, safety concerns, or policy).

        If you’d like help adjusting the model or have questions about next steps, reply here and we’ll be glad to assist.
      EOS
      author:          Current.staff_user,
      staff_note_only: false
    )

    JobMailer.notify_patron(msg).deliver_later
  end

  # ---- File validation (STL & 3MF only) ----
  def model_files_must_be_allowed_models
    return unless model_files.attached?

    allowed_exts = %w[.stl .3mf]
    zip_mimes    = %w[application/zip application/x-zip-compressed multipart/x-zip]

    bad = []

    model_files.each do |blob|
      fname = blob.filename.to_s
      ext   = File.extname(fname).downcase
      cty   = (blob.content_type || '').downcase

      # Allow by extension only (robust to octet-stream). ZIP-type MIME is OK only for .3mf.
      ext_ok     = allowed_exts.include?(ext)
      zip_mime   = zip_mimes.include?(cty)
      mime_ok    = !zip_mime || ext == '.3mf'
      valid_file = ext_ok && mime_ok

      bad << fname unless valid_file
    end

    if bad.any?
      errors.add(:model_files, "must be STL (.stl) or 3MF (.3mf) files. Invalid: #{bad.join(', ')}")
    end
  end
end
