module Admin::ResourcesHelper
  def admin_resource_label(field)
    { rgb: "Hex color", public: "Publicly viewable", fdm_printer: "FDM printing", resin_printer: "Resin printing", scanner: "Scanning", print_type_code: "Print type", pickup_location_id: "Pickup location", admin: "Administrator", job_id: "Job", conversation_id: "Conversation", jobs_count: "Jobs" }.fetch(field.to_sym) { field.to_s.humanize }
  end

  def admin_resource_value(record, field)
    return @status_counts.fetch(record.id, 0) if field == :jobs_count && @status_counts
    value = record.public_send(field)
    return admin_value(filtered_audit_changes(value)) if field == :audited_changes
    return value.name if value.respond_to?(:name) && !value.is_a?(String)
    admin_value(value)
  end

  def admin_resource_field(form, field)
    klass = { class: "admin-input" }
    case field
    when :pickup_location_id
      form.collection_select(field, PickupLocation.reorder(Arel.sql("LOWER(name) ASC")), :id, :name, { include_blank: true }, klass)
    when :print_type_code
      form.collection_select(field, PrintType.reorder(Arel.sql("LOWER(name) ASC")), :code, :name, { include_blank: true }, klass)
    when :author_type
      form.select(field, %w[StaffUser Patron], {}, klass)
    else
      type = @record.class.type_for_attribute(field.to_s).type
      case type
      when :boolean
        form.check_box(field, class: "h-4 w-4 rounded border-slate-300")
      when :integer
        form.number_field(field, klass)
      when :datetime
        form.datetime_local_field(field, klass)
      when :text
        form.text_area(field, klass.merge(rows: 5))
      else
        form.text_field(field, klass)
      end
    end
  end
end
