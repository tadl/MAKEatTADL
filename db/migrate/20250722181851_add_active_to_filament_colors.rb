class AddActiveToFilamentColors < ActiveRecord::Migration[7.1]
  def change
    add_column :filament_colors, :active, :boolean, default: true, null: false
  end
end
