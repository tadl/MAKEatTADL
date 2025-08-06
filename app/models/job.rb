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

  has_one  :conversation, dependent: :destroy
  after_create :build_conversation!
  after_update :archive_if_picked_up, if: :saved_change_to_pickup_date?

  validates :status, presence: true

  # Track start/finish events when status changes
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
  scope :finished_between, ->(start_time, end_time) { where(finished_at: start_time..end_time) }

  private

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
      self.started_by  = Current.staff_user
      self.started_at  = Time.current
    end

    if new_code == 'ready_for_pickup' && finished_by_id.nil?
      self.finished_by = Current.staff_user
      self.finished_at = Time.current
    end
  end
end
