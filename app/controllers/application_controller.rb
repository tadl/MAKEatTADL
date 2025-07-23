# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  before_action { Current.staff_user = current_staff_user }
  before_action  :log_forwarded_for

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

  private

  def log_forwarded_for
    Rails.logger.info("[Client IPs] X-Forwarded-For: #{request.headers['X-Forwarded-For'].to_s.inspect} | RemoteAddr: #{request.remote_ip}")
  end
end
