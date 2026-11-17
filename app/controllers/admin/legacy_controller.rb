class Admin::LegacyController < Admin::BaseController
  def show
    model = params[:model_name]
    legacy_action = params[:legacy_action].presence
    id = params[:id]
    if id == "new"
      legacy_action = "new"
      id = nil
    end
    if id == "help" && model == "job"
      authorize! :help, Job
      return redirect_to admin_help_path, status: :moved_permanently
    end
    if id == "export"
      return redirect_to legacy_export_path(model), status: :moved_permanently
    end
    destination = case model
    when "job"
      authorize! :read, Job
      if id
        case legacy_action
        when "conversation" then conversation_admin_job_path(id)
        when "files" then files_admin_job_path(id)
        when "edit" then edit_admin_job_path(id)
        else admin_job_path(id)
        end
      elsif legacy_action == "new"
        new_admin_job_path
      else
        admin_jobs_path(scope: params[:scope], q: params[:query], status_id: legacy_status_id)
      end
    when "patron"
      authorize! :read, Patron
      if id
        case legacy_action
        when "edit" then edit_admin_patron_path(id)
        when "merge_patron" then merge_admin_patron_path(id)
        else admin_patron_path(id)
        end
      else
        legacy_action == "new" ? new_admin_patron_path : admin_patrons_path
      end
    when "printable_model"
      authorize! :read, PrintableModel
      id ? (legacy_action == "edit" ? edit_admin_printable_model_path(id) : admin_printable_model_path(id)) : admin_printable_models_path
    else
      key = model == "audited~audit" ? "audits" : model.pluralize
      definition = Admin::ResourcesController::RESOURCES.fetch(key) { raise ActiveRecord::RecordNotFound }
      authorize! :read, definition[:model]
      id ? admin_resource_path(resource: key, id: id) : admin_resources_path(resource: key)
    end
    redirect_to destination, status: :moved_permanently
  end

  private

  def legacy_export_path(model)
    case model
    when "job"
      authorize! :export, Job
      export_admin_jobs_path(format: :csv, scope: params[:scope], q: params[:query], status_id: legacy_status_id)
    when "patron"
      authorize! :export, Patron
      export_admin_patrons_path(format: :csv, q: params[:query])
    when "printable_model"
      authorize! :export, PrintableModel
      export_admin_printable_models_path(format: :csv, q: params[:query])
    else
      key = model == "audited~audit" ? "audits" : model.pluralize
      definition = Admin::ResourcesController::RESOURCES.fetch(key) { raise ActiveRecord::RecordNotFound }
      authorize! :export, definition[:model]
      export_admin_resources_path(resource: key, format: :csv, q: params[:query])
    end
  end

  def legacy_status_id
    filters = params[:f]
    return unless filters.is_a?(ActionController::Parameters)
    status = filters[:status]
    return unless status.is_a?(ActionController::Parameters)
    rule = status["0"]
    return unless rule.is_a?(ActionController::Parameters)
    value = rule[:v]
    value if value.is_a?(String) && value.match?(/\A\d+\z/)
  end
end
