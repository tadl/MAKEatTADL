# app/models/status.rb
class Status < ApplicationRecord
  audited
  has_many :jobs
  validates :name, :code, presence: true, uniqueness: true
  default_scope { order(:position) }

  def jobs_count
    jobs.count
  end
end
