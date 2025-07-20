class AddAdminToStaffUsers < ActiveRecord::Migration[7.1]
  def change
    # only add the column if it doesn’t already exist
    add_column :staff_users,
               :admin,
               :boolean,
               default: false,
               null:   false,
               if_not_exists: true
  end
end
