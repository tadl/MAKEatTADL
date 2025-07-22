# db/migrate/20250722_add_notifications.rb
class AddNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :notifications do |t|
      t.references :staff_user, null: false, foreign_key: true, index: true
      t.references :message,    null: false, foreign_key: true, index: true
      t.datetime   :read_at
      t.timestamps
    end
  end
end
