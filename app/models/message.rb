class Message < ApplicationRecord
  audited
  belongs_to :conversation
  belongs_to :author, polymorphic: true   # StaffUser or Patron (if you choose)

  has_many_attached :images

  validates :body, presence: true

  scope :unread, -> {
    where(read_at: nil).
    where(author_type: 'Patron')
  }

  def update_read_at!
    update!(read_at: Time.current)
  end

  alias_method :mark_read!, :update_read_at!
end
