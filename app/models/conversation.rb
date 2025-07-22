# app/models/conversation.rb
class Conversation < ApplicationRecord
  audited
  belongs_to :job
  has_many   :messages, -> { order(:created_at) }, dependent: :destroy

  before_create :generate_conversation_token

  private

  def generate_conversation_token
    begin
      self.conversation_token = SecureRandom.urlsafe_base64(8)
    end while Conversation.exists?(conversation_token: conversation_token)
  end
end
