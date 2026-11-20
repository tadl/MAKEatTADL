module Admin
  class BaseController < ApplicationController
    include CanCan::ControllerAdditions

    PAGE_SIZES = [25, 50, 100].freeze

    layout "admin"

    before_action :prevent_admin_caching
    before_action :authenticate_staff_user!
    before_action :authorize_admin_access!

    helper_method :current_ability, :can?, :cannot?

    rescue_from CanCan::AccessDenied, with: :forbidden
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActionController::InvalidAuthenticityToken do
      message = "Your session changed or expired. Reload the page and try again. Nothing was saved."
      respond_to do |format|
        format.html { redirect_to admin_root_path, alert: message, status: :see_other }
        format.json { render json: { errors: [message] }, status: :unprocessable_content }
        format.any { head :unprocessable_content }
      end
    end
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
      @per_page = PAGE_SIZES.find { |size| params[:per_page] == size.to_s } || PAGE_SIZES.first
      @total_count = scope.except(:limit, :offset, :order).count
      @total_pages = [(@total_count + @per_page - 1) / @per_page, 1].max
      requested_page = Integer(params[:page], exception: false) || 1
      @page = [[requested_page, 1].max, @total_pages].min
      scope.limit(@per_page).offset((@page - 1) * @per_page)
    end
  end
end
