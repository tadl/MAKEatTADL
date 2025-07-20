# db/migrate/20250708_add_details_to_staff_users.rb
class AddDetailsToStaffUsers < ActiveRecord::Migration[7.1]
  def change
    # only add these columns if they’re not already present
    add_column :staff_users, :name,       :string,  if_not_exists: true
    add_column :staff_users, :avatar_url, :string,  if_not_exists: true
    add_column :staff_users, :uid,        :string,  null: false, if_not_exists: true
    add_column :staff_users, :admin,      :boolean, null: false, default: false, if_not_exists: true
  end
end
