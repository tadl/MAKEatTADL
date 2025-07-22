class PrintType < ApplicationRecord
  audited
  has_many :jobs,     foreign_key: :print_type_code, primary_key: :code, inverse_of: :print_type
  has_many :printers, foreign_key: :print_type_code, primary_key: :code
  validates :name, :code, presence: true, uniqueness: true
  default_scope { order(:position) }
end

