class BackfillScanOrigins < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      UPDATE jobs
         SET origin = 'scan'
       WHERE type = 'ScanJob'
          OR spray_ok = TRUE
          OR id IN (
               SELECT asa.record_id
                 FROM active_storage_attachments asa
                WHERE asa.name = 'scan_image'
             );
    SQL
  end

  def down
    # Data-only correction; do not infer which records were intentionally print-origin.
  end
end
