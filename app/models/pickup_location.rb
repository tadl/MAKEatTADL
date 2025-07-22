# app/models/pickup_location.rb
class PickupLocation < ApplicationRecord
  audited
  scope :active,      -> { where(active: true) }
  scope :scanners,    -> { where(scanner: true).order(:position) }
  scope :fdm_printers,   -> { active.where(fdm_printer: true) }
  scope :resin_printers, -> { active.where(resin_printer: true) }

  has_many :printers

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true
end
