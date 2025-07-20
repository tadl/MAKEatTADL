#db/migrate/20250708200445_create_staff_users.rb
class CreateStaffUsers < ActiveRecord::Migration[7.1]
  def change
    # Only create the table if it doesn’t already exist
    create_table :staff_users, if_not_exists: true do |t|
      t.string   :email,               null: false, default: ""
      t.string   :encrypted_password,  null: false, default: ""
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at

      # fields you added later
      t.string   :name
      t.string   :avatar_url
      t.string   :uid,                 null: false
      t.boolean  :admin,               null: false, default: false

      t.timestamps
    end

    # Only add these indexes if the table was created (or if they don’t yet exist)
    add_index :staff_users, :email,                unique: true, if_not_exists: true
    add_index :staff_users, :reset_password_token, unique: true, if_not_exists: true
    add_index :staff_users, :uid,                  unique: true, if_not_exists: true
  end
end
