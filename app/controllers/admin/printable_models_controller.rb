require "csv"

class Admin::PrintableModelsController < Admin::BaseController
  before_action :load_model, only: %i[show edit update destroy]
  before_action { @page_title = "Model library" }

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
    @model = PrintableModel.new
    load_source_file
    if @source_job
      quantity = @source_job.quantity.to_i.positive? ? @source_job.quantity : 1
      weight = @source_job.actual_weight.presence || @source_job.slicer_weight
      @model.assign_attributes(category: @source_job.category,
                               weight_grams: weight && (weight / quantity).round,
                               name: @source_file.filename.base.humanize)
    end
  end

  def create
    authorize! :create, PrintableModel
    @model = PrintableModel.new(model_params)
    load_source_file
    @model.model_file.attach(@source_file.blob) if @source_file && !@model.model_file.attached?
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
      { id: model.id, name: model.name, code: model.code, category: model.category.name, weight_grams: model.weight_grams, notes: model.notes }
    end
    respond_to do |format|
      format.csv do
        csv = CSV.generate do |file|
          file << %w[id name code category weight_grams notes]
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
      scope = scope.where("name ILIKE :q OR code ILIKE :q OR notes ILIKE :q", q: search)
    end
    scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?
    sort = %w[name code weight_grams position].include?(params[:sort]) ? params[:sort] : "name"
    scope.reorder(sort => (params[:direction] == "desc" ? :desc : :asc)).order(:id)
  end
end
