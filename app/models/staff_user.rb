# app/models/staff_user.rb
class StaffUser < ApplicationRecord
  class UnauthorizedDomainError < StandardError; end

  # Required fields
  validates :uid,   presence: true, uniqueness: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }

  def self.authorized_google_account!(auth)
    email = auth&.info&.email.to_s.strip.downcase
    domain = ENV["GOOGLE_DOMAIN"].to_s.strip.downcase
    hosted_domain = auth.dig("extra", "id_info", "hd").to_s.strip.downcase
    email_verified = auth.dig("extra", "id_info", "email_verified")

    raise UnauthorizedDomainError, "missing email" if email.blank?
    raise UnauthorizedDomainError, "unverified email" if email_verified == false
    return true if domain.blank?

    email_domain = email.split("@", 2).last.to_s
    return true if email_domain == domain && (hosted_domain.blank? || hosted_domain == domain)

    raise UnauthorizedDomainError, "unauthorized domain"
  end

  # Build or update a user from OmniAuth data
  def self.from_omniauth(auth)
    authorized_google_account!(auth)

    user = find_or_initialize_by(uid: auth.uid)
    user.email      = auth.info.email
    user.name       = auth.info.name
    user.avatar_url = auth.info.image
    user.save! if user.changed?
    user
  end

  def admin?
    self.admin
  end
end
