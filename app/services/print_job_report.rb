# app/services/print_job_report.rb
class PrintJobReport
  attr_reader :start_date, :end_date

  def initialize(start_date:, end_date:)
    @start_date = start_date.beginning_of_day
    @end_date   = end_date.end_of_day
    @completed = PrintJob.where(completion_date: @start_date..@end_date)
    @cancelled = PrintJob.joins(:status).where(statuses: { code: 'cancelled' }).where(updated_at: @start_date..@end_date)
    job_ids = @completed.ids + @cancelled.ids
    @jobs = PrintJob.where(id: job_ids)
  end

  def orders_count
    @completed.count
  end

  def cancelled_count
    @cancelled.count
  end

  def distinct_patrons
    @jobs.select(:patron_id).distinct.count
  end

  def fdm_count
    @completed.joins(:print_type).where(print_types: { code: 'fdm' }).count
  end

  def resin_count
    @completed.joins(:print_type).where(print_types: { code: 'resin' }).count
  end

  def resin_ml
    @completed.joins(:print_type).where(print_types: { code: 'resin' }).sum(:resin_volume_ml).to_i
  end

  def multiple_count
    @jobs.where(filament_color: 'multiple').count
  end

  def total_quantity
    @completed.sum(:quantity)
  end

  def unique_designs
    pm_count = @completed.where.not(printable_model_id: nil).distinct.count(:printable_model_id)
    jobs_without_pm = @completed.where(printable_model_id: nil)
    urls = jobs_without_pm.pluck(:url).reject(&:blank?)
    files = jobs_without_pm.flat_map { |j| j.model_files.attached? ? j.model_files.map { |f| f.filename.to_s } : [] }
    pm_count + (urls + files).uniq.size
  end

  def filament_grams
    @completed.joins(:print_type).where(print_types: { code: 'fdm' }).sum(:actual_weight).to_i
  end

  def filament_per_day
    PrintJob.where.not(completion_date: nil)
            .where(completion_date: @start_date..@end_date)
            .group("DATE(completion_date)").sum(:actual_weight)
  end

  def popular_filament
    @completed.group(:filament_color).order('count_id DESC').count(:id).first&.first
  end

  def prints_per_day
    PrintJob.where.not(completion_date: nil)
            .where(completion_date: @start_date..@end_date)
            .group("DATE(completion_date)").order("DATE(completion_date)").count
  end

  def filament_color_counts
    PrintJob.where.not(filament_color: [nil, ""])
            .where(completion_date: @start_date..@end_date)
            .group(:filament_color).count
  end

  def category_counts
    @jobs.joins(:category).group('categories.name').count
  end
end
