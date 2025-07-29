class AddLastPickupReminderSentAtToJobs < ActiveRecord::Migration[7.1]
  def change
    add_column :jobs, :last_pickup_reminder_sent_at, :datetime
  end
end
