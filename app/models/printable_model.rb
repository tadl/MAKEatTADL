# app/models/printable_model.rb
class PrintableModel < ApplicationRecord
  audited
  belongs_to :category

  has_one_attached :model_file     # e.g. .stl/.obj
  has_one_attached :preview_image  # your PNG thumbnail

  validates :name, :code, :category_id, presence: true
  validates :code, uniqueness: true

  default_scope { order(:position) }
end
