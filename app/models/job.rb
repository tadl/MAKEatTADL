# app/models/job.rb
class Job < ApplicationRecord
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

  has_one_attached :model_file

  has_one  :conversation, dependent: :destroy
  after_create :build_conversation!

  validates :status, presence: true

  scope :with_status, ->(code) {
    joins(:status).where(statuses: { code: code })
  }

  scope :active,   -> { joins(:status).where.not(statuses: { code: %w[archived cancelled] }) }
  scope :inactive, -> { joins(:status).where(statuses:     { code: %w[archived cancelled] }) }

  private

  def build_conversation!
    create_conversation! unless conversation
  end
end
