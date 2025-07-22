class Category < ApplicationRecord
  audited only: :name
  has_many :printable_models, dependent: :destroy
end
