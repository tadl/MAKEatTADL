# lib/rails_admin/config/actions/help.rb
module RailsAdmin
  module Config
    module Actions
      class Help < RailsAdmin::Config::Actions::Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :visible? do
          bindings[:abstract_model].model == ::Job
        end

        register_instance_option :link_icon do
          'fa fa-book'
        end

        register_instance_option :controller do
          proc do
            render @action.template_name
          end
        end

        register_instance_option :http_methods do
          [:get]
        end

        register_instance_option :collection? do
          true
        end

        register_instance_option :breadcrumb_parent do
          [:index, RailsAdmin::AbstractModel.new('Job')]
        end

        register_instance_option :template_name do
          :help
        end
      end
    end
  end
end
