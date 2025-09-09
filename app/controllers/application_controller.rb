# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action { Current.staff_user = current_staff_user }
  before_action :authenticate_staff_user!, if: -> { respond_to?(:rails_admin_controller?) && rails_admin_controller? }

  helper_method :current_staff_user
  def current_staff_user
    @current_staff_user ||= StaffUser.find_by(id: session[:staff_user_id])
  end

  helper_method :current_patron
  def current_patron
    return @current_patron if defined?(@current_patron)
    if cookies.encrypted[:patron_id]
      p = Patron.find_by(id: cookies.encrypted[:patron_id])
      @current_patron = p if p&.token_valid?
    end
  end

  def verify_recaptcha_with_logging!(model:, action:, min_score: 0.5)
    ok = verify_recaptcha(model: model, action: action, minimum_score: min_score)
    reply = request.env['recaptcha.reply'] || {}
    Rails.logger.info(
      "[reCAPTCHA] ok=#{ok} score=#{reply['score'].inspect} action=#{reply['action'].inspect} " \
      "host=#{reply['hostname'].inspect} errors=#{Array(reply['error-codes']).join(', ').presence || 'none'} " \
      "ip=#{request.remote_ip}"
    )
    ok
  end

  unless Rails.env.development?
    rescue_from ActionController::RoutingError, with: :not_found
    rescue_from ActiveRecord::RecordNotFound,  with: :not_found
    rescue_from CanCan::AccessDenied,          with: :forbidden if defined?(CanCan)
    rescue_from StandardError,                 with: :internal_server_error
  end

  def not_found(exception = nil)
    respond_to do |format|
      format.html { render "errors/not_found", status: :not_found }
      format.all  { render plain: "404 Not Found", status: :not_found }
    end
  end

  def forbidden(exception = nil)
    respond_to do |format|
      format.html { render "errors/forbidden", status: :forbidden }
      format.all  { render plain: "403 Forbidden", status: :forbidden }
    end
  end

  def internal_server_error(exception = nil)
    logger.error(exception.message) if exception
    respond_to do |format|
      format.html { render "errors/internal_server_error", status: :internal_server_error }
      format.all  { render plain: "500 Internal Server Error", status: :internal_server_error }
    end
  end

  private

  def authenticate_staff_user!
    unless current_staff_user
      redirect_to '/admin/login' and return
    end
  end

end
