# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  def choose_login
  end

  # Staff login via OmniAuth
  def create
    auth  = request.env['omniauth.auth']
    staff = StaffUser.from_omniauth(auth)
    session[:staff_user_id] = staff.id

    return_to = session.delete(:user_return_to)
    redirect_to (return_to || rails_admin.dashboard_path)
  rescue StaffUser::UnauthorizedDomainError => e
    Rails.logger.warn("Rejected staff login: #{e.message}")
    reset_session
    redirect_to '/admin/login', alert: "That account is not authorized for staff access."
  end

  # DELETE /logout
  def destroy
    # remember what was logged in
    staff_was_logged_in  = current_staff_user.present?
    patron_was_logged_in = cookies.encrypted[:patron_id].present?

    # clear staff session
    session.delete(:staff_user_id)

    # expire patron token & clear its cookie
    if patron_was_logged_in
      if (patron = Patron.find_by(id: cookies.encrypted[:patron_id]))
        patron.expire_token!
      end
      cookies.delete(:patron_id)
    end

    # wipe everything else
    reset_session

    # build notice
    notices = []
    notices << "Staff user signed out."   if staff_was_logged_in
    notices << "You’ve been logged out."  if patron_was_logged_in
    notices = ["Signed out."] if notices.empty?

    redirect_to root_path, notice: notices.join(" ")
  end

  private

  # (Optional) Example OAuth revoke helper—call it above if needed
  def revoke_oauth_token(token)
    client = OAuth2::Client.new(
      Rails.application.credentials.dig(:oauth, :client_id),
      Rails.application.credentials.dig(:oauth, :client_secret),
      site: 'https://oauth2.googleapis.com'
    )
    client.request(:post, '/revoke', params: { token: token })
  rescue => e
    Rails.logger.warn("Token revoke failed: #{e.message}")
  end
end
