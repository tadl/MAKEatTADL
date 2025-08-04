class PatronMailer < ApplicationMailer
  def access_link(patron)
    @patron = patron
    @url = dashboard_url(token: patron.access_token)

    mail to: @patron.email, subject: "Your Login Link for MAKE@TADL"
  end
end
