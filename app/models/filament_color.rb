class FilamentColor < ApplicationRecord
  audited
  validates :name, :code, presence: true
  validates :code, uniqueness: true
  default_scope { order(position: :asc) }
  scope :active, -> { where(active: true) }
end
