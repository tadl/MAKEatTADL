# db/migrate/20250714203631_fix_category_on_jobs.rb
class FixCategoryOnJobs < ActiveRecord::Migration[7.1]
  def change
    # Once every job already has a category_id, enforce NOT NULL
    change_column_null :jobs, :category_id, false
  end
end
