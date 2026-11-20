class RailsAdminParentController < ApplicationController
  rescue_from ActionController::InvalidAuthenticityToken, with: :recover_staff_csrf

  private

  def recover_staff_csrf
    message = "Your session changed or expired. Reload the page and try again. Nothing was saved."
    response.headers["Cache-Control"] = "no-store"
    respond_to do |format|
      format.html do
        redirect_to current_staff_user ? rails_admin.dashboard_path : "/admin/login",
          alert: message, status: :see_other
      end
      format.json { render json: { errors: [message] }, status: :unprocessable_content }
      format.any { head :unprocessable_content }
    end
  end
end
