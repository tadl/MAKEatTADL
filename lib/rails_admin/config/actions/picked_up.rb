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

            prev_current = Current.staff_user
            Current.staff_user = current_staff_user

            begin
              picked_up = @job.with_lock do
                next false unless @job.status&.code == 'ready_for_pickup' && @job.pickup_date.blank?

                @job.update!(pickup_date: Date.current)
              end
              if picked_up
                flash[:success] = "Job ##{@job.id} marked as picked up and archived."
              else
                flash[:alert] = "Job ##{@job.id} is not ready for pickup or has already been picked up."
              end
            rescue ActiveRecord::RecordInvalid => error
              flash[:error] = "Job ##{@job.id} could not be marked picked up. Correct these details in Edit job, then retry: #{error.record.errors.full_messages.to_sentence}"
            ensure
              Current.staff_user = prev_current
            end

            redirect_to rails_admin.dashboard_path, status: :see_other
          end
        end

      end
    end
  end
end
