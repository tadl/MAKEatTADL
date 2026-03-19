require "rails_admin/config/actions"
require "rails_admin/config/actions/base"

module RailsAdmin
  module Config
    module Actions
      class MergePatron < Base
        RailsAdmin::Config::Actions.register(self)

        register_instance_option :member? do
          true
        end

        register_instance_option :only do
          [::Patron]
        end

        register_instance_option :visible? do
          authorized? && bindings[:controller]&.current_staff_user&.admin?
        end

        register_instance_option :http_methods do
          [:get, :post]
        end

        register_instance_option :route_fragment do
          "merge_patron"
        end

        register_instance_option :route_name do
          :merge_patron
        end

        register_instance_option :route_action do
          :merge_patron
        end

        register_instance_option :link_icon do
          "fa fa-code-fork"
        end

        register_instance_option :pjax? do
          false
        end

        register_instance_option :controller do
          proc do
            raise CanCan::AccessDenied unless current_staff_user&.admin?

            @patron = @object
            @merge_candidates = Patron
              .where.not(id: @patron.id)
              .left_joins(:jobs)
              .group("patrons.id")
              .order(Arel.sql("LOWER(patrons.email) ASC"))
              .select("patrons.*, COUNT(jobs.id) AS jobs_count")

            if request.post?
              winner = Patron.find_by(id: params[:target_patron_id])

              unless winner
                flash.now[:error] = "Choose the patron record that should remain after the merge."
                return render @action.template_name, status: :unprocessable_entity
              end

              result = PatronMergeService.call(winner: winner, loser: @patron)
              flash[:success] = "Merged Patron ##{@patron.id} into Patron ##{result.winner.id}. Moved #{result.jobs_moved} job(s) and #{result.messages_moved} patron message(s)."
              redirect_to rails_admin.show_path(model_name: "patron", id: result.winner.id)
            end
          rescue PatronMergeService::MergeError => e
            flash.now[:error] = e.message
            render @action.template_name, status: :unprocessable_entity
          end
        end
      end
    end
  end
end
