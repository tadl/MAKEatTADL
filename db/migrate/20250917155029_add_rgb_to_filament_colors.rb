# db/migrate/202509xx_add_rgb_to_filament_colors.rb
class AddRgbToFilamentColors < ActiveRecord::Migration[7.1]
  def change
    add_column :filament_colors, :rgb, :string
  end
end
