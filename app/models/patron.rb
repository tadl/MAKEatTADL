# app/models/patron.rb
class Patron < ApplicationRecord
  audited
  has_many :jobs, dependent: :destroy

  before_create :generate_access_token

  # Public: regenerates the access token and timestamp
  def regenerate_access_token!
    generate_access_token
    save!
  end

  # Public: check token freshness
  def token_valid?
    token_sent_at.present? && token_sent_at >= 7.days.ago
  end

  # Public: expire (clear) the token
  def expire_token!
    update!(access_token: nil, token_sent_at: nil)
  end

  private

  # Generates a new token and sets timestamp
  def generate_access_token
    self.access_token  = SecureRandom.urlsafe_base64(24)
    self.token_sent_at = Time.current
  end
end
