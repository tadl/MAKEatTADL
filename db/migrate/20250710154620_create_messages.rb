class CreateMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :author, polymorphic: true, null: false
      t.text :body

      t.timestamps
    end
  end
end
