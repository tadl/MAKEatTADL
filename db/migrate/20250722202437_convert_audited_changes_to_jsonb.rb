# db/migrate/20250723_convert_audited_changes_to_jsonb.rb
class ConvertAuditedChangesToJsonb < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!  # work in batches if you have a lot of audits

  class Audit < ApplicationRecord
    self.table_name = 'audits'
  end

  def up
    # 1) Add a new jsonb column with a default empty object
    add_column :audits, :audited_changes_jsonb, :jsonb, null: false, default: {}

    Audit.reset_column_information

    say_with_time "Backfilling audited_changes_jsonb from audited_changes (YAML → JSON)" do
      Audit.find_each(batch_size: 1_000) do |audit|
        begin
          # load YAML, fall back to empty hash on error
          data = YAML.safe_load(audit.audited_changes) || {}
        rescue
          data = {}
        end

        # write raw JSONB directly, skipping validations/callbacks
        audit.update_column(:audited_changes_jsonb, data)
      end
    end

    # 2) Drop the old text column and rename the new one into place
    remove_column :audits, :audited_changes
    rename_column :audits, :audited_changes_jsonb, :audited_changes
  end

  def down
    # reverse: bring back text column, dump JSON → YAML
    add_column :audits, :audited_changes_yaml, :text

    Audit.reset_column_information

    say_with_time "Backfilling audited_changes_yaml from audited_changes (JSON → YAML)" do
      Audit.find_each(batch_size: 1_000) do |audit|
        yaml = audit.audited_changes.to_yaml
        audit.update_column(:audited_changes_yaml, yaml)
      end
    end

    remove_column :audits, :audited_changes
    rename_column :audits, :audited_changes_yaml, :audited_changes
  end
end
