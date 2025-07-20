# db/migrate/20250714010415_add_status_ref_to_jobs.rb
class AddStatusRefToJobs < ActiveRecord::Migration[7.1]
  def change
    # purely add the FK column—no Job.statuses or data updates here
    add_reference :jobs, :status,
      foreign_key: true,
      null:       false,
      index:      true,
      if_not_exists: true
  end
end
