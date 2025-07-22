class RemoveDescriptionFromJobs < ActiveRecord::Migration[7.1]
  def change
    remove_column :jobs, :description, :text
  end
end
