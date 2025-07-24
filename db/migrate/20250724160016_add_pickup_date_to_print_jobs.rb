# db/migrate/20250724120000_add_pickup_date_to_print_jobs.rb
class AddPickupDateToPrintJobs < ActiveRecord::Migration[7.1]
  def change
    add_column :jobs, :pickup_date, :date
  end
end
