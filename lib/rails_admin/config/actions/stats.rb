module RailsAdmin
  module Config
    module Actions
      class Stats < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :root? do
          true
        end

        register_instance_option :authorization_key do
          :dashboard
        end

        register_instance_option :breadcrumb_parent do
          nil
        end

        register_instance_option :link_icon do
          'fas fa-chart-bar'
        end

        register_instance_option :controller do
          proc do
            render @action.template_name
          end
        end
      end
    end
  end
end
