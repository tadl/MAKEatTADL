require "csv"

module Admin
  class JobsController < BaseController
    MESSAGE_IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp image/heic image/heif image/heic-sequence image/heif-sequence].freeze

    before_action :load_job, except: %i[index new create export bulk_destroy]

    def index
      authorize! :read, Job
      @jobs = paginate_scope(filtered_jobs.includes(:patron, :status, :category, :assigned_printer))
      load_filter_options
    end

    def show
      authorize! :read, @job
      @messages = @job.conversation&.messages&.includes(:author)&.last(3) || []
    end

    def new
      authorize! :create, Job
      @job = job_class.new(status: Status.find_by(code: "pending"), category: Category.find_by(name: "Patron"))
      apply_catalog_model
      load_form_options
    end

    def create
      authorize! :create, Job
      @job = job_class.new
      @job.assign_attributes(job_params(creating: true))
      apply_catalog_model(attach: true)
      if valid_job_references? && @job.save
        redirect_to admin_job_path(@job), notice: "Job ##{@job.id} created."
      else
        load_form_options
        render :new, status: :unprocessable_content
      end
    end

    def edit
      authorize! :update, @job
      load_form_options
    end

    def update
      authorize! :update, @job
      @job.assign_attributes(job_params)
      if valid_job_references? && @job.save
        redirect_to admin_job_path(@job), notice: "Job ##{@job.id} updated."
      else
        load_form_options
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize! :destroy, @job
      @job.destroy!
      redirect_to admin_jobs_path, notice: "Job ##{@job.id} deleted.", status: :see_other
    end

    def bulk_destroy
      authorize! :destroy, Job
      ids = Array(params[:ids]).filter_map { |id| Integer(id, exception: false) }.uniq
      if ids.empty?
        return redirect_to admin_jobs_path, alert: "Select at least one job to delete.", status: :see_other
      end

      count = 0
      Job.transaction do
        Job.where(id: ids).find_each do |job|
          authorize! :destroy, job
          job.destroy!
          count += 1
        end
      end
      redirect_to admin_jobs_path, notice: "#{count} #{'job'.pluralize(count)} deleted.", status: :see_other
    end

    def export
      authorize! :export, Job
      records = filtered_jobs.includes(:patron, :status, :category, :assigned_printer).map do |job|
        { id: job.id, type: job.type, patron: job.patron.name, email: job.patron.email,
          status: job.status.name, category: job.category.name, pickup_location: job.pickup_location,
          printer: job.assigned_printer&.name, received_at: job.created_at.iso8601,
          completion_date: job.completion_date, pickup_date: job.pickup_date, quantity: job.quantity,
          estimated_weight: job.slicer_weight, actual_weight: job.actual_weight,
          resin_volume_ml: job.resin_volume_ml, estimated_cost: job.slicer_cost, actual_cost: job.actual_cost,
          notes: job.notes }
      end
      format = params[:format].presence || "csv"
      filename = "make-jobs-#{Date.current.iso8601}.#{format}"
      if format == "json"
        return send_data records.to_json, filename: filename, type: "application/json"
      elsif format == "xml"
        return send_data records.to_xml(root: "jobs"), filename: filename, type: "application/xml"
      elsif format != "csv"
        return head :not_acceptable
      end
      data = CSV.generate do |csv|
        csv << ["Job", "Type", "Patron", "Email", "Status", "Category", "Pickup location", "Printer",
                "Received", "Completed", "Picked up", "Quantity", "Estimated weight (g)", "Actual weight (g)",
                "Resin (mL)", "Estimated cost", "Actual cost", "Notes"]
        records.each do |record|
          csv << record.values.map { |value| csv_value(value) }
        end
      end
      send_data data, filename: filename, type: "text/csv; charset=utf-8"
    end

    def conversation
      authorize! :conversation, @job
      prepare_conversation
      @conversation.messages.unread.find_each(&:mark_read!)
      Notification.unread.where(staff_user: current_staff_user, message: @conversation.messages).find_each(&:mark_read!)
      @message = @conversation.messages.new
    end

    def create_message
      authorize! :conversation, @job
      prepare_conversation
      message_params = params.expect(conversation: [:message_body, :staff_note_only, images: []])
      body = message_params[:message_body].to_s
      private_note = message_params[:staff_note_only] == "1" || body.match?(/@\w+/)
      @message = @conversation.messages.new(body: body, author: current_staff_user, staff_note_only: private_note)
      raw_images = params[:conversation][:images]
      images = raw_images.is_a?(Array) ? raw_images.reject(&:blank?) : (raw_images.blank? ? [] : [raw_images])
      unless images.all? { |image| valid_message_image?(image) }
        @message.errors.add(:images, "must be nonempty JPEG, PNG, GIF, WebP, or HEIC uploads")
        return render :conversation, status: :unprocessable_content
      end
      @message.images.attach(images) if images.any?

      if @message.save
        usernames = body.scan(/@(\w+)/).flatten.uniq
        domain = ENV["GOOGLE_DOMAIN"].to_s.strip
        if domain.present?
          usernames.each do |username|
            staff = StaffUser.find_by(email: "#{username}@#{domain}")
            next unless staff

            Notification.create!(staff_user: staff, message: @message)
            MentionMailer.user_mentioned(staff, @message).deliver_later
          end
        end
        JobMailer.notify_patron(@message).deliver_later unless private_note
        redirect_to conversation_admin_job_path(@job), notice: private_note ? "Staff note added." : "Message sent.", status: :see_other
      else
        render :conversation, status: :unprocessable_content
      end
    end

    def files
      authorize! :files, @job
    end

    def attach_files
      authorize! :files, @job
      key = %i[job print_job scan_job].find { |name| params[name].present? }
      payload = params[key] if key
      incoming = payload.is_a?(ActionController::Parameters) ? Array(payload.permit(model_files: [])[:model_files]).reject(&:blank?) : []
      files = incoming.select { |file| file.is_a?(ActionDispatch::Http::UploadedFile) && file.tempfile&.size.to_i.positive? }
      allowed, rejected = files.partition do |file|
        extension = File.extname(file.original_filename.to_s).downcase
        zip = %w[application/zip application/x-zip-compressed multipart/x-zip].include?(file.content_type.to_s.downcase)
        %w[.stl .3mf].include?(extension) && (!zip || extension == ".3mf")
      end

      if allowed.any?
        @job.model_files.attach(allowed)
        if @job.errors.any?
          flash[:error] = @job.errors.full_messages.to_sentence
        else
          flash[:success] = "#{allowed.size} #{'file'.pluralize(allowed.size)} attached."
        end
      end
      if rejected.any?
        flash[:alert] = "Only STL or 3MF model files are allowed. Rejected: #{rejected.map(&:original_filename).join(', ')}"
      elsif files.length != incoming.length
        flash[:alert] = "Choose valid, nonempty STL or 3MF uploads."
      elsif incoming.empty?
        flash[:alert] = "Choose at least one STL or 3MF file."
      end
      redirect_to files_admin_job_path(@job), status: :see_other
    end

    def destroy_file
      authorize! :files, @job
      @job.model_files.find(params[:file_id]).purge
      redirect_to files_admin_job_path(@job), notice: "File deleted.", status: :see_other
    end

    def picked_up
      authorize! :picked_up, @job
      unless @job.status.code == "ready_for_pickup"
        return redirect_to admin_job_path(@job), alert: "This job is not ready for pickup.", status: :see_other
      end

      @job.update!(pickup_date: Date.current)
      redirect_to admin_job_path(@job), notice: "Job ##{@job.id} marked as picked up and archived.", status: :see_other
    end

    private

    def load_job
      @job = Job.includes(:patron, :status, :category, :assigned_printer, :print_type, :started_by, :finished_by)
        .with_attached_model_files.find(params[:id])
    end

    def job_class
      payload = params[:job]
      if !payload.nil? && !payload.is_a?(ActionController::Parameters)
        raise ActionController::BadRequest, "Expected job parameters to be an object"
      end
      type = payload&.[](:type).presence || params[:type].presence || "PrintJob"
      { "PrintJob" => PrintJob, "ScanJob" => ScanJob }.fetch(type) { raise ActionController::BadRequest, "Invalid job type" }
    end

    def job_params(creating: false)
      permitted = %i[status_id category_id pickup_location notes]
      if @job.is_a?(PrintJob)
        permitted += %i[assigned_printer_id print_type_code url filament_color quantity print_notify
                        print_time_estimate_hm slicer_weight actual_weight resin_volume_ml completion_date pickup_date]
      else
        permitted += %i[scan_image spray_ok]
      end
      permitted += %i[patron_id printable_model_id] if creating
      permitted << { model_files: [] } if creating
      params.expect(job: permitted)
    end

    def filtered_jobs
      scope = case params[:scope]
      when "inactive" then Job.inactive
      when "ongoing" then Job.ongoing
      when "all" then Job.all
      else Job.active
      end
      scope = scope.where(status_id: params[:status_id]) if params[:status_id].present?
      scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?
      scope = scope.where(type: params[:type]) if %w[PrintJob ScanJob].include?(params[:type])
      scope = scope.where(pickup_location: params[:pickup_location]) if params[:pickup_location].present?
      if params[:q].present?
        term = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
        scope = scope.joins(:patron).where("patrons.name ILIKE :term OR patrons.email ILIKE :term OR jobs.url ILIKE :term OR CAST(jobs.id AS TEXT) ILIKE :term", term: term)
      end
      from = Date.iso8601(params[:from]) rescue nil
      to = Date.iso8601(params[:to]) rescue nil
      scope = scope.where(created_at: from.beginning_of_day..) if from
      scope = scope.where(created_at: ..to.end_of_day) if to
      sort = { "id" => "jobs.id", "received" => "jobs.created_at", "patron" => "patrons.name",
               "status" => "statuses.name", "category" => "categories.name", "type" => "jobs.type",
               "pickup_location" => "jobs.pickup_location" }.fetch(params[:sort], "jobs.created_at")
      scope = scope.left_joins(:patron, :status, :category)
      direction = params[:direction] == "asc" ? "ASC" : "DESC"
      scope.order(Arel.sql("#{sort} #{direction}"), id: :desc)
    end

    def load_filter_options
      @statuses = Status.reorder(:name)
      @categories = Category.reorder(:name)
      @locations = PickupLocation.reorder(:name)
      @location_names = @locations.pluck(:code, :name).to_h
    end

    def load_form_options
      load_filter_options
      @printers = Printer.reorder(:name)
      @print_types = PrintType.reorder(:name)
      @colors = FilamentColor.active.reorder(:name)
      @patrons = Patron.order(:name, :email) if @job.new_record?
      @active_locations = PickupLocation.active.reorder(:name)
    end

    def prepare_conversation
      @conversation = @job.conversation || @job.create_conversation!
      @messages = @conversation.messages.includes(:author).with_attached_images
    end

    def apply_catalog_model(attach: false)
      return unless @job.is_a?(PrintJob)
      model_id = params.dig(:job, :printable_model_id).presence || params[:printable_model_id].presence
      return if model_id.blank?

      @selected_model = PrintableModel.find(model_id)
      @job.printable_model = @selected_model
      @job.quantity = 1 if @job.quantity.blank?
      @job.slicer_weight = @selected_model.weight_grams if @job.slicer_weight.blank?
      @job.print_type = PrintType.find_by!(code: "fdm") if @job.print_type.blank?
      @job.model_files.attach(@selected_model.model_file.blob) if attach && @selected_model.model_file.attached?
    end

    def valid_job_references?
      references = { patron_id: :patron, status_id: :status, category_id: :category,
                     assigned_printer_id: :assigned_printer, print_type_code: :print_type,
                     printable_model_id: :printable_model }
      references.each do |foreign_key, association|
        if @job.public_send(foreign_key).present? && @job.public_send(association).nil?
          @job.errors.add(association, "does not exist")
        end
      end
      @job.errors.empty?
    end

    def valid_message_image?(image)
      image.is_a?(ActionDispatch::Http::UploadedFile) && image.tempfile&.size.to_i.positive? &&
        MESSAGE_IMAGE_TYPES.include?(image.content_type.to_s.downcase)
    end

    def csv_value(value)
      value.is_a?(String) && value.match?(/\A(?:[\s\uFEFF]*[=+\-@]|[\t\r\n])/) ? "'#{value}" : value
    end
  end
end
