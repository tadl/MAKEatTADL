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

  scope :with_status, ->(code) {
    joins(:status).where(statuses: { code: code })
  }

  scope :active,   -> { joins(:status).where.not(statuses: { code: %w[archived cancelled rejected abandoned] }) }
  scope :inactive, -> { joins(:status).where(statuses:     { code: %w[archived cancelled rejected abandoned] }) }

  scope :ongoing, -> { with_status('ongoing') }

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
end
