class StaffDashboard
  attr_reader :statuses, :job_counts, :ready_jobs, :pickup_location_names,
              :unread_counts, :mention_counts, :message_jobs

  def initialize(staff_user:)
    @statuses = Status.order(:position).to_a
    @job_counts = Job.group(:status_id).count
    @pickup_location_names = PickupLocation.pluck(:code, :name).to_h

    ready_status = statuses.find { |status| status.code == "ready_for_pickup" }
    @ready_jobs = if ready_status
      Job.where(status: ready_status).includes(:patron)
        .order(Arel.sql("COALESCE(completion_date, created_at) ASC"), :id).to_a
    else
      []
    end

    @unread_counts = Message.unread.joins(:conversation).group("conversations.job_id").count
    @mention_counts = Notification.unread.where(staff_user: staff_user)
      .joins(message: :conversation).group("conversations.job_id").count
    @message_jobs = Job.where(id: unread_counts.keys | mention_counts.keys)
      .includes(:patron).index_by(&:id)
  end
end
