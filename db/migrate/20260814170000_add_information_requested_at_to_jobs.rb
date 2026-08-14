class AddInformationRequestedAtToJobs < ActiveRecord::Migration[7.1]
  def up
    add_column :jobs, :information_requested_at, :datetime
    add_column :jobs, :last_quote_reminder_sent_at, :datetime
    add_index :jobs, :information_requested_at

    # Existing rows do not have a trustworthy status-entry timestamp. Give jobs
    # currently awaiting a response a fresh window rather than inferring from
    # job creation or old conversation messages.
    execute <<~SQL.squish
      UPDATE jobs
      SET information_requested_at = CURRENT_TIMESTAMP
      WHERE status_id IN (
        SELECT id FROM statuses WHERE code = 'information_requested'
      )
    SQL
  end

  def down
    remove_index :jobs, :information_requested_at
    remove_column :jobs, :last_quote_reminder_sent_at
    remove_column :jobs, :information_requested_at
  end
end
