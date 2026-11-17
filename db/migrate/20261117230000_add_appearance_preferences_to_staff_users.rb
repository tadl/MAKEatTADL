class AddAppearancePreferencesToStaffUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :staff_users, :theme, :string, default: "system", null: false
    add_column :staff_users, :ui_density, :string, default: "normal", null: false

    add_check_constraint :staff_users, "theme IN ('system', 'light', 'dark')", name: "staff_users_theme_check"
    add_check_constraint :staff_users, "ui_density IN ('normal', 'condensed')", name: "staff_users_ui_density_check"
  end
end
