# db/migrate/20240917120000_add_print_notify_to_jobs.rb
class AddPrintNotifyToJobs < ActiveRecord::Migration[7.1]
  def change
    add_column :jobs, :print_notify, :boolean, null: false, default: false
    add_index  :jobs, :print_notify
  end
end
