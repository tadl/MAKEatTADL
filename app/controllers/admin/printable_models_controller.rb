require "csv"

class Admin::PrintableModelsController < Admin::BaseController
  COLLECTIONS = {
    "staff" => { label: "Staff library", category: "Staff" },
    "assistive" => { label: "Assistive", category: "Assistive" },
    "fidget" => { label: "Fidget", category: "Fidget" }
  }.freeze

  before_action :load_model, only: %i[show edit update destroy]
  before_action { @page_title = "Model library" }
  helper_method :library_collection_label, :library_collection_filters,
                :library_collection_options, :selected_library_category_id

  def index
    authorize! :read, PrintableModel
    @models = paginate_scope(filtered_scope.with_attached_preview_image.with_attached_model_file.includes(:category))
  end

  def show
    authorize! :read, @model
    history = Job.where(printable_model: @model)
    if @model.model_file.attached?
      source_ids = ActiveStorage::Attachment.where(record_type: "Job", name: "model_files", blob_id: @model.model_file.blob_id).select(:record_id)
      history = history.or(Job.where(id: source_ids))
    end
    @jobs = history.includes(:patron, :status).order(created_at: :desc, id: :desc).limit(25)
  end

  def new
    authorize! :create, PrintableModel
    @model = PrintableModel.new(category: collection_categories.fetch("staff"))
    load_source_file
    if @source_job
      @model.assign_attributes(weight_grams: source_weight_per_copy,
                               name: @source_file.filename.base.humanize,
                               notes: source_printing_notes)
    end
  end

  def create
    authorize! :create, PrintableModel
    @model = PrintableModel.new(category: collection_categories.fetch("staff"))
    @model.assign_attributes(model_params)
    load_source_file
    @model.model_file.attach(@source_file.blob) if @source_file && !@model.model_file.attached?
    if @source_job
      @model.notes = source_printing_notes unless params[:printable_model].key?(:notes)
      @model.weight_grams = source_weight_per_copy unless params[:printable_model].key?(:weight_grams)
    end
    @model.code = @model.name.to_s.parameterize if @model.code.blank?
    persist_model(:new)
  end

  def edit
    authorize! :update, @model
  end

  def update
    authorize! :update, @model
    @model.assign_attributes(model_params)
    persist_model(:edit)
  end

  def destroy
    authorize! :destroy, @model
    @model.destroy!
    redirect_to admin_printable_models_path, notice: "Model deleted."
  rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotDestroyed
    redirect_to admin_printable_model_path(@model), alert: "This model is linked to print history and cannot be deleted."
  end

  def bulk_destroy
    authorize! :destroy, PrintableModel
    records = PrintableModel.where(id: Array(params[:ids])).to_a
    PrintableModel.transaction { records.each(&:destroy!) }
    redirect_to admin_printable_models_path, notice: "#{records.size} models deleted."
  rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotDestroyed
    redirect_to admin_printable_models_path, alert: "A selected model is linked to print history. No models were deleted."
  end

  def export
    authorize! :export, PrintableModel
    rows = filtered_scope.includes(:category).map do |model|
      { id: model.id, name: model.name, code: model.code, collection: library_collection_label(model.category), weight_grams: model.weight_grams, notes: model.notes }
    end
    respond_to do |format|
      format.csv do
        csv = CSV.generate do |file|
          file << %w[id name code collection weight_grams notes]
          rows.each { |row| file << row.values.map { |value| value.is_a?(String) && value.match?(/\A[\s\uFEFF]*[=+\-@]/) ? "'#{value}" : value } }
        end
        send_data csv, filename: "models-#{Date.current}.csv", type: "text/csv"
      end
      format.json { render json: rows }
      format.xml { render xml: rows.to_xml(root: "models") }
    end
  end

  private

  def load_model
    @model = PrintableModel.find(params[:id])
  end

  def load_source_file
    return if params[:source_job_id].blank?
    @source_job = Job.find(params[:source_job_id])
    authorize! :files, @source_job
    @source_file = @source_job.model_files.find(params[:attachment_id])
  end

  def model_params
    attributes = params.expect(printable_model: %i[name code category_id position weight_grams notes model_file preview_image])
    @invalid_collection = false
    if params[:printable_model].key?(:category_id)
      selected_id = Integer(attributes[:category_id], exception: false)
      selected_category = collection_categories.values.compact.find { |category| category.id == selected_id }
      if selected_category
        attributes[:category_id] = selected_category.id
      else
        @invalid_collection = true
        attributes.delete(:category_id)
      end
    end
    @invalid_upload_fields = []
    %i[model_file preview_image].each do |field|
      upload = params[:printable_model][field]
      if upload.nil? || upload == ""
        attributes.delete(field)
      elsif !upload.is_a?(ActionDispatch::Http::UploadedFile)
        @invalid_upload_fields << field
        attributes.delete(field)
      end
    end
    attributes
  end

  def persist_model(template)
    @model.errors.add(:base, "Collection must be Staff library, Assistive, or Fidget.") if @invalid_collection
    Array(@invalid_upload_fields).each { |field| @model.errors.add(field, "must be an uploaded file") }
    if @model.model_file.attached? && !%w[.stl .3mf].include?(File.extname(@model.model_file.filename.to_s).downcase)
      @model.errors.add(:model_file, "must be an STL or 3MF file")
    end
    if @model.preview_image.attached? && !%w[image/jpeg image/png image/webp].include?(@model.preview_image.content_type)
      @model.errors.add(:preview_image, "must be a JPEG, PNG, or WebP image")
    end
    return render template, status: :unprocessable_content if @model.errors.any?

    if @model.save
      redirect_to admin_printable_model_path(@model), notice: "Model saved to the library."
    else
      render template, status: :unprocessable_content
    end
  end

  def filtered_scope
    scope = PrintableModel.all
    if params[:q].present?
      search = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
      scope = scope.where("printable_models.name ILIKE :q OR printable_models.code ILIKE :q OR printable_models.notes ILIKE :q", q: search)
    end
    case params[:collection].presence
    when "staff"
      scope = scope.joins(:category).where.not(categories: { name: %w[Assistive Fidget] })
    when "assistive", "fidget"
      scope = scope.joins(:category).where(categories: { name: COLLECTIONS.fetch(params[:collection])[:category] })
    when nil
      # All three collections, including legacy staff-only catalog entries.
    else
      scope = scope.none
    end
    sort = %w[name code weight_grams position].include?(params[:sort]) ? params[:sort] : "name"
    scope.reorder(sort => (params[:direction] == "desc" ? :desc : :asc)).order(:id)
  end

  def collection_categories
    @collection_categories ||= begin
      categories = Category.where(name: COLLECTIONS.values.map { |collection| collection[:category] })
        .reorder(:id).group_by(&:name)
      COLLECTIONS.transform_values { |collection| categories[collection[:category]]&.first }
    end
  end

  def library_collection_label(category)
    COLLECTIONS.values.find { |collection| collection[:category] == category.name }&.fetch(:label) || "Staff library"
  end

  def library_collection_filters
    COLLECTIONS.map { |key, collection| [collection[:label], key] }
  end

  def library_collection_options
    COLLECTIONS.filter_map do |key, collection|
      category = collection_categories.fetch(key)
      [collection[:label], category.id] if category
    end
  end

  def selected_library_category_id
    collection_key = COLLECTIONS.find { |_key, collection| collection[:category] == @model.category&.name }&.first || "staff"
    collection_categories.fetch(collection_key)&.id
  end

  def source_quantity
    @source_job.quantity.to_i.positive? ? @source_job.quantity.to_i : 1
  end

  def source_weight_per_copy
    weight = @source_job.actual_weight.presence || @source_job.slicer_weight
    weight && (weight / source_quantity).round
  end

  def source_printing_notes
    lines = []
    lines << "Printer: #{@source_job.assigned_printer.name}" if @source_job.assigned_printer
    lines << "Print process: #{@source_job.print_type.name}" if @source_job.print_type
    if @source_job.filament_color.present?
      color = FilamentColor.find_by(code: @source_job.filament_color)&.name || @source_job.filament_color
      lines << "Filament color: #{color}"
    end
    lines << "Quantity in source run: #{source_quantity}"
    if @source_job.is_a?(PrintJob) && @source_job.print_time_estimate_hm.present?
      lines << "Estimated duration for source run: #{@source_job.print_time_estimate_hm} (hours:minutes or minutes)"
    end
    { "Actual weight" => [@source_job.actual_weight, "g"],
      "Estimated weight" => [@source_job.slicer_weight, "g"],
      "Resin used" => [@source_job.resin_volume_ml, "mL"] }.each do |label, (amount, unit)|
      next if amount.blank?

      total = ActiveSupport::NumberHelper.number_to_rounded(amount, precision: 2, strip_insignificant_zeros: true)
      per_copy = ActiveSupport::NumberHelper.number_to_rounded(amount / source_quantity, precision: 2, strip_insignificant_zeros: true)
      lines << "#{label} for source run: #{total} #{unit} (#{per_copy} #{unit} per copy)"
    end
    if source_weight_per_copy
      source = @source_job.actual_weight.present? ? "actual" : "estimated"
      lines << "Default weight per copy: #{source_weight_per_copy} g (rounded from source #{source} weight)"
    end
    lines.join("\n")
  end
end
