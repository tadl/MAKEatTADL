class AddOriginToJobs < ActiveRecord::Migration[7.1]
  def up
    add_column :jobs, :origin, :string, default: "print", null: false
    add_index  :jobs, :origin

    # Mark as 'scan' if either:
    #  - spray_ok is TRUE (scan form captured this), OR
    #  - a 'scan_image' ActiveStorage attachment exists for that job id
    execute <<~SQL
      UPDATE jobs
         SET origin = 'scan'
       WHERE spray_ok = TRUE
          OR id IN (
               SELECT asa.record_id
                 FROM active_storage_attachments asa
                WHERE asa.name = 'scan_image'
             );
    SQL

    # Optional: guard against invalid values
    execute "ALTER TABLE jobs ADD CONSTRAINT jobs_origin_check CHECK (origin IN ('print','scan'));"
  end

  def down
    execute "ALTER TABLE jobs DROP CONSTRAINT IF EXISTS jobs_origin_check;"
    remove_index  :jobs, :origin if index_exists?(:jobs, :origin)
    remove_column :jobs, :origin
  end
end
