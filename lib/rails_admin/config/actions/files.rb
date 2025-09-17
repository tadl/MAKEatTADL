# lib/rails_admin/config/actions/files.rb
module RailsAdmin
  module Config
    module Actions
      class Files < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :member do
          true
        end

        register_instance_option :visible? do
          bindings[:abstract_model].model == ::Job && authorized?
        end

        register_instance_option :http_methods do
          [:get, :post, :delete]
        end

        register_instance_option :pjax? do
          false
        end

        register_instance_option :link_icon do
          'fa fa-file'
        end

        register_instance_option :controller do
          proc do
            @job = @object

            # Collect files from either print_job[...] or job[...], reject blanks like ""
            model_key      = @job.model_name.param_key.to_sym
            candidate_sets = [
              Array(params.dig(model_key, :model_files)),
              Array(params.dig(:job,     :model_files))
            ]
            uploaded_files = candidate_sets.flatten.compact

            files_to_attach = uploaded_files.select do |f|
              # Be robust: accept any upload object that quacks like an upload and has bytes
              f.respond_to?(:original_filename) &&
                f.respond_to?(:tempfile) &&
                f.tempfile &&
                f.tempfile.respond_to?(:size) &&
                f.tempfile.size.to_i > 0
            end

            if request.post?
              Rails.logger.debug do
                names = files_to_attach.map { |f| f.original_filename }.inspect
                "RailsAdmin Files: attaching #{files_to_attach.size} file(s) to Job##{@job.id}: #{names}"
              end

              if files_to_attach.any?
                begin
                  @job.model_files.attach(files_to_attach)
                  # Ensure in-memory instance reflects the new attachments (not strictly required)
                  @job.reload
                  flash[:success] = "#{files_to_attach.size} file#{'s' unless files_to_attach.size == 1} attached."
                rescue => e
                  Rails.logger.error("RailsAdmin Files attach error: #{e.class}: #{e.message}")
                  flash[:error] = "Attachment failed: #{e.message}"
                end
              else
                # Helpful debug shows what we actually received
                debug_preview = uploaded_files.map { |x| x.is_a?(String) ? x.inspect : x.class.name }.inspect
                flash[:error] = "No valid files to attach. (Received: #{debug_preview})"
              end

              redirect_to rails_admin.files_path(model_name: @abstract_model.to_param, id: @job.id)
              next
            end

            if request.delete? && params[:file_id]
              attachment = @job.model_files.find_by(id: params[:file_id])
              if attachment
                attachment.purge
                flash[:success] = "File deleted."
              else
                flash[:error] = "File not found."
              end
              redirect_to rails_admin.files_path(model_name: @abstract_model.to_param, id: @job.id)
              next
            end
          end
        end
      end
    end
  end
end
