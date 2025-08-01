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

        register_instance_option :controller do
          proc do
            @job = @object

            model_key = @job.class.model_name.param_key
            uploaded_files = params.dig(model_key, :model_files) || []

            # Only attach if at least one file is a real upload object (not an empty string)
            files_to_attach = uploaded_files.select { |f| f.is_a?(ActionDispatch::Http::UploadedFile) && f.size > 0 }

            if request.post?
              if files_to_attach.any?
                begin
                  @job.model_files.attach(files_to_attach)
                  flash[:success] = "#{files_to_attach.size} file(s) attached."
                rescue => e
                  flash[:error] = "Attachment failed: #{e.message}"
                end
              else
                flash[:error] = "No valid files to attach! (Debug: #{uploaded_files.inspect})"
              end
              redirect_to rails_admin.files_path(model_name: 'job', id: @job.id)
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
              redirect_to rails_admin.files_path(model_name: 'job', id: @job.id)
              next
            end
          end
        end

        register_instance_option :link_icon do
          'fa fa-file' # fontawesome icon, change if you want
        end

        register_instance_option :http_methods do
          [:get, :post, :delete]
        end

        register_instance_option :pjax? do
          false
        end
      end
    end
  end
end
