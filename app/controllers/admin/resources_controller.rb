require "csv"

class Admin::ResourcesController < Admin::BaseController
  # Only these administrative tables are addressable. URL input never becomes a class name.
  RESOURCES = {
    "printers" => { model: Printer, label: "Printers", fields: %i[name pickup_location_id print_type_code printer_model bed_size location public], columns: %i[name pickup_location print_type printer_model bed_size public] },
    "filament_colors" => { model: FilamentColor, label: "Filament colors", fields: %i[name code active rgb], columns: %i[name code active rgb] },
    "pickup_locations" => { model: PickupLocation, label: "Pickup locations", fields: %i[name code active scanner fdm_printer resin_printer], columns: %i[name code active scanner fdm_printer resin_printer] },
    "print_types" => { model: PrintType, label: "Print types", fields: %i[name code position], columns: %i[name code position] },
    "statuses" => { model: Status, label: "Statuses", fields: %i[name code position], columns: %i[name code position jobs_count] },
    "categories" => { model: Category, label: "Categories", fields: %i[name position], columns: %i[name position] },
    "staff_users" => { model: StaffUser, label: "Staff users", fields: %i[admin], columns: %i[name email admin], create: false },
    "conversations" => { model: Conversation, label: "Conversations", fields: %i[job_id], columns: %i[id job_id created_at], create: false },
    "messages" => { model: Message, label: "Messages", fields: %i[conversation_id author_type author_id body staff_note_only read_at], columns: %i[id conversation_id author_type author_id body staff_note_only created_at], create: false },
    "audits" => { model: Audited::Audit, label: "Activity log", fields: [], columns: %i[created_at user_type user_id auditable_type auditable_id action audited_changes], readonly: true, create: false }
  }.freeze

  before_action :load_resource
  before_action :load_record, only: %i[show edit update destroy]
  helper_method :resource_definition, :resource_key

  def index
    authorize! :read, resource_model
    @records = paginate_scope(filtered_scope)
    @status_counts = Job.group(:status_id).count if resource_key == "statuses"
  end

  def show
    authorize! :read, @record
  end

  def new
    authorize_creation!
    @record = resource_model.new
  end

  def create
    authorize_creation!
    @record = resource_model.new(resource_params)
    persist_record(:new)
  end

  def edit
    authorize_modification! :update
  end

  def update
    authorize_modification! :update
    @record.assign_attributes(resource_params)
    persist_record(:edit)
  end

  def destroy
    authorize_modification! :destroy
    @record.destroy!
    redirect_to admin_resources_path(resource: resource_key), notice: "Record deleted."
  rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotDestroyed
    redirect_to admin_resource_path(resource: resource_key, id: @record.id), alert: "This record is still in use and could not be deleted."
  end

  def bulk_destroy
    authorize! :destroy, resource_model
    raise CanCan::AccessDenied if resource_definition[:readonly]
    records = resource_model.where(id: selected_ids).to_a
    resource_model.transaction { records.each(&:destroy!) }
    redirect_to admin_resources_path(resource: resource_key), notice: "#{records.size} records deleted."
  rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotDestroyed
    redirect_to admin_resources_path(resource: resource_key), alert: "One or more records are still in use. No records were deleted."
  end

  def export
    authorize! :export, resource_model
    columns = ([:id] + resource_definition[:columns]).uniq
    rows = filtered_scope.map { |record| columns.index_with { |field| export_value(record, field) } }
    respond_to do |format|
      format.csv do
        csv = CSV.generate { |file| file << columns; rows.each { |row| file << row.values.map { |value| csv_value(value) } } }
        send_data csv, filename: "#{resource_key}-#{Date.current}.csv", type: "text/csv"
      end
      format.json { render json: rows }
      format.xml { render xml: rows.to_xml(root: resource_key.tr("_", "-")) }
    end
  end

  private

  def load_resource
    @resource_key = params[:resource].to_s
    @resource_definition = RESOURCES[@resource_key]
    raise ActiveRecord::RecordNotFound unless @resource_definition
    @page_title = resource_definition[:label]
  end

  attr_reader :resource_definition, :resource_key

  def resource_model
    resource_definition[:model]
  end

  def load_record
    @record = resource_model.find(params[:id])
  end

  def authorize_creation!
    authorize! :create, resource_model
    raise CanCan::AccessDenied if resource_definition[:create] == false || resource_definition[:readonly]
  end

  def authorize_modification!(action)
    authorize! action, @record
    raise CanCan::AccessDenied if resource_definition[:readonly]
  end

  def resource_params
    fields = resource_definition[:fields].dup
    fields << { printer_ids: [] } if resource_key == "pickup_locations"
    params.expect(record: fields)
  end

  def persist_record(template)
    if resource_key == "messages" && !%w[Patron StaffUser].include?(@record.author_type)
      @record.errors.add(:author_type, "must be Patron or StaffUser")
      return render template, status: :unprocessable_content
    end
    if @record.save
      redirect_to admin_resource_path(resource: resource_key, id: @record.id), notice: "Changes saved."
    else
      render template, status: :unprocessable_content
    end
  end

  def filtered_scope
    scope = resource_model.all
    if resource_key == "printers"
      scope = scope.includes(:pickup_location, :print_type)
    end
    search_fields = %w[name email code body action auditable_type].intersection(resource_model.column_names)
    if params[:q].present? && search_fields.any?
      search = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
      conditions = search_fields.map { |field| "#{resource_model.quoted_table_name}.#{resource_model.connection.quote_column_name(field)} ILIKE :query" }
      scope = scope.where(conditions.join(" OR "), query: search)
    end
    if resource_key == "filament_colors" && params[:scope] == "active"
      scope = scope.where(active: true)
    end
    sort_column = params[:sort].to_s.presence || (resource_model.column_names.include?("name") ? "name" : "id")
    sort_column = "id" unless (resource_definition[:columns].map(&:to_s) & resource_model.column_names).include?(sort_column)
    direction = params[:direction] == "desc" ? :desc : :asc
    scope.reorder(sort_column => direction).order(id: direction)
  end

  def selected_ids
    Array(params[:ids]).filter_map { |value| Integer(value, exception: false) }.uniq
  end

  def export_value(record, field)
    value = field == :audited_changes ? filtered_audit_changes(record.audited_changes) : record.public_send(field)
    value = value.name if value.is_a?(ApplicationRecord) && value.respond_to?(:name)
    value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value
  end

  def filtered_audit_changes(changes)
    ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters + [/token/, /secret/, /password/]).filter(changes || {})
  end
  helper_method :filtered_audit_changes

  def csv_value(value)
    value.is_a?(String) && value.match?(/\A[\s\uFEFF]*[=+\-@]/) ? "'#{value}" : value
  end
end
