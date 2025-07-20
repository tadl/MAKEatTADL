# db/migrate/20250714202138_add_category_ref_to_jobs.rb
class AddCategoryRefToJobs < ActiveRecord::Migration[7.1]
  def change
    # Simply add the FK column—no data manipulation here
    add_reference :jobs, :category,
      foreign_key: true,
      null:       false,
      index:      true,
      if_not_exists: true
  end
end
