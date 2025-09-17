# lib/rails_admin/config/actions/files.rb
module RailsAdmin
  module Config
    module Actions
      class Files < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        # ✅ Allow only STL and 3MF
        ALLOWED_EXTS = %w[.stl .3mf].freeze

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

            # Keep only real uploaded files with bytes
            raw_files = uploaded_files.select do |f|
              f.respond_to?(:original_filename) &&
                f.respond_to?(:tempfile) &&
                f.tempfile &&
                f.tempfile.respond_to?(:size) &&
                f.tempfile.size.to_i > 0
            end

            if request.post?
              # Partition by extension allowlist
              allowed, rejected = raw_files.partition do |f|
                ext = File.extname(f.original_filename.to_s).downcase
                ALLOWED_EXTS.include?(ext)
              end

              Rails.logger.debug do
                "RailsAdmin Files: attaching #{allowed.size} ALLOWED and "\
                "#{rejected.size} REJECTED to Job##{@job.id}"
              end

              begin
                if allowed.any?
                  @job.model_files.attach(allowed)
                  @job.reload
                  flash[:success] = "#{allowed.size} file#{'s' unless allowed.size == 1} attached."
                end

                if rejected.any?
                  names = rejected.map { |f| f.original_filename }.join(', ')
                  msg   = "Only .stl or .3mf files are allowed. Blocked: #{names}"
                  # If we also attached some, make this a warning; otherwise it's an error
                  if allowed.any?
                    flash[:warning] = msg
                  else
                    flash[:error] = msg
                  end
                end

                if allowed.empty? && rejected.empty?
                  debug_preview = uploaded_files.map { |x| x.is_a?(String) ? x.inspect : x.class.name }.inspect
                  flash[:error] = "No valid files to attach. (Received: #{debug_preview})"
                end
              rescue => e
                Rails.logger.error("RailsAdmin Files attach error: #{e.class}: #{e.message}")
                flash[:error] = "Attachment failed: #{e.message}"
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
