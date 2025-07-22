class Notification < ApplicationRecord
  belongs_to :staff_user
  belongs_to :message

  scope :unread, -> { where(read_at: nil) }

  def mark_read!
    update!(read_at: Time.current)
  end
end
