module Admin
  class BaseController < ApplicationController
    include CanCan::ControllerAdditions

    layout "admin"

    before_action :prevent_admin_caching
    before_action :authenticate_staff_user!
    before_action :authorize_admin_access!

    helper_method :current_ability, :can?, :cannot?

    rescue_from CanCan::AccessDenied, with: :forbidden
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActionController::ParameterMissing, ActionController::BadRequest do
      head :bad_request
    end

    def current_ability
      @current_ability ||= Ability.new(current_staff_user)
    end

    private

    def prevent_admin_caching
      response.headers["Cache-Control"] = "no-store"
    end

    def authenticate_staff_user!
      return if current_staff_user

      session[:user_return_to] = request.fullpath if request.get? || request.head?
      redirect_to admin_login_path
    end

    def authorize_admin_access!
      authorize! :access, :admin
    end

    def paginate_scope(scope)
      @total_count = scope.except(:limit, :offset, :order).count
      @total_pages = [(@total_count / 20.0).ceil, 1].max
      @page = [[params[:page].to_i, 1].max, @total_pages].min
      scope.limit(20).offset((@page - 1) * 20)
    end
  end
end
