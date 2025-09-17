# db/migrate/20240917120100_add_public_to_printers.rb
class AddPublicToPrinters < ActiveRecord::Migration[7.1]
  def change
    add_column :printers, :public, :boolean, null: false, default: true
  end
end
