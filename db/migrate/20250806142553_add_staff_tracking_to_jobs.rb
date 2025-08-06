class AddStaffTrackingToJobs < ActiveRecord::Migration[6.1]
  def change
    add_reference :jobs, :started_by,  foreign_key: { to_table: :staff_users }, index: true
    add_reference :jobs, :finished_by, foreign_key: { to_table: :staff_users }, index: true
    add_column     :jobs, :started_at,  :datetime
    add_column     :jobs, :finished_at, :datetime
  end
end
