# app/models/printer.rb
class Printer < ApplicationRecord
  audited
  validates :name, presence: true, uniqueness: true
  has_many :print_jobs, foreign_key: :assigned_printer_id
  belongs_to :pickup_location
  belongs_to :print_type, primary_key: :code, foreign_key: :print_type_code, optional: true
end
