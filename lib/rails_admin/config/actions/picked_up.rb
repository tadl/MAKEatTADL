# lib/rails_admin/config/actions/picked_up.rb
require 'rails_admin/config/actions'
require 'rails_admin/config/actions/base'

module RailsAdmin
  module Config
    module Actions
      class PickedUp < Base
        RailsAdmin::Config::Actions.register(self)

        # IMPORTANT: RailsAdmin 3.x requires `member?`, NOT `member`
        register_instance_option :member? do
          true
        end

        register_instance_option :only do
          [::Job]
        end

        register_instance_option :visible? do
          authorized? && bindings[:object]&.status&.code == 'ready_for_pickup'
        end

        register_instance_option :http_methods do
          [:post]
        end

        # These 3 options ensure proper route generation
        register_instance_option :route_fragment do
          'picked_up'
        end

        register_instance_option :route_name do
          :picked_up
        end

        register_instance_option :route_action do
          :picked_up
        end

        register_instance_option :controller do
          proc do
            @job = @abstract_model.model.find(params[:id])

            ready = Status.find_by(code: 'ready_for_pickup')
            unless ready && @job.status_id == ready.id
              flash[:alert] = "Job ##{@job.id} is not in 'Ready for pickup'."
              return redirect_to rails_admin.dashboard_path
            end

            prev_current = Current.staff_user
            Current.staff_user = current_staff_user

            begin
              @job.update!(pickup_date: Date.current)
              flash[:success] = "Job ##{@job.id} marked as picked up and archived."
            rescue => e
              flash[:error] = "Failed to mark picked up: #{e.message}"
            ensure
              Current.staff_user = prev_current
            end

            redirect_to rails_admin.dashboard_path
          end
        end

      end
    end
  end
end
