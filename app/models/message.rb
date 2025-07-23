class Message < ApplicationRecord
  audited
  belongs_to :conversation
  belongs_to :author, polymorphic: true   # StaffUser or Patron (if you choose)

  after_create :mark_requested_if_patron_reply

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

  private

  def mark_requested_if_patron_reply
    return unless author_type == 'Patron'

    job = conversation.job
    if job.status.code == 'information_requested'
      new_status = Status.find_by!(code: 'requested')
      job.update!(status: new_status)
    end
  end
end
