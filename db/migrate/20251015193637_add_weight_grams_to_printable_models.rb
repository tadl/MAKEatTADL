class AddWeightGramsToPrintableModels < ActiveRecord::Migration[7.1]
  def change
    add_column :printable_models, :weight_grams, :integer
  end
end
