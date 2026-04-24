# app/services/print_job_report.rb
class PrintJobReport
  attr_reader :start_date, :end_date

  NORMALIZED_QUANTITY_SQL = "COALESCE(NULLIF(quantity, 0), 1)".freeze
  NON_COMPLETED_STATUS_CODES = %w[cancelled rejected].freeze

  # Expect Date/Time; we normalize to a closed day-range
  def initialize(start_date:, end_date:)
    @start_date = start_date.beginning_of_day
    @end_date   = end_date.end_of_day

    # Base scopes used consistently throughout
    @submitted   = PrintJob.where(origin: "print", created_at: @start_date..@end_date)

    @completed   = PrintJob.where.not(completion_date: nil)
                           .where(completion_date: @start_date..@end_date)

    @non_cancelled_completed = @completed
      .joins(:status)
      .where.not(statuses: { code: NON_COMPLETED_STATUS_CODES })

    @non_cancelled_completed_with_files = @non_cancelled_completed.with_attached_model_files
  end

  # ---------------------------
  # "Orders" = submissions flow
  # ---------------------------

  # Orders submitted in the window
  def orders_count
    @submitted.count
  end

  # Of the above orders, how many are (currently) cancelled
  def cancelled_count
    @submitted.joins(:status).where(statuses: { code: 'cancelled' }).count
  end

  def rejected_count
    @submitted.joins(:status).where(statuses: { code: 'rejected' }).count
  end

  # Distinct patrons who submitted during the window
  def distinct_patrons
    @submitted.select(:patron_id).distinct.count
  end

  # ---------------------------
  # Output/completions metrics
  # ---------------------------

  def fdm_count
    @non_cancelled_completed.joins(:print_type).where(print_types: { code: 'fdm' }).count
  end

  def resin_count
    @non_cancelled_completed.joins(:print_type).where(print_types: { code: 'resin' }).count
  end

  def multiple_count
    @non_cancelled_completed.where(filament_color: 'multiple').count
  end

  def scan_completed_count
    Job
      .joins(:status)
      .where(origin: "scan")
      .where.not(completion_date: nil)
      .where(completion_date: @start_date..@end_date)
      .where.not(statuses: { code: NON_COMPLETED_STATUS_CODES })
      .count
  end

  # Sum quantities for completed, non-cancelled jobs; treat nil OR 0 as 1
  def total_quantity
    @non_cancelled_completed.sum(Arel.sql(NORMALIZED_QUANTITY_SQL))
  end

  # Filament used in grams. This matches the current pricing model and stored job totals.
  def filament_grams
    @non_cancelled_completed
      .joins(:print_type).where(print_types: { code: 'fdm' })
      .sum(Arel.sql("COALESCE(actual_weight, slicer_weight, 0)")).to_i
  end

  # Resin used (mL). This matches the current pricing model and stored job totals.
  def resin_ml
    @non_cancelled_completed
      .joins(:print_type).where(print_types: { code: 'resin' })
      .sum(Arel.sql("COALESCE(resin_volume_ml, 0)")).to_i
  end

  # ---------------------------
  # Designs (per job)
  # ---------------------------

  # Per-job design identity (never more than completed orders)
  def unique_designs
    keys = @non_cancelled_completed_with_files.map { |job| design_key_for(job) }
    keys.uniq.size
  end

  # ---------------------------
  # Per-day series (completions)
  # ---------------------------

  # Sum COALESCE(NULLIF(quantity,0),1) per day for completed non-cancelled
  def prints_per_day
    @non_cancelled_completed
      .group("DATE(completion_date)")
      .pluck(
        Arel.sql("DATE(completion_date)"),
        Arel.sql("SUM(#{NORMALIZED_QUANTITY_SQL})")
      )
      .to_h
  end

  def filament_per_day
    @non_cancelled_completed
      .joins(:print_type).where(print_types: { code: 'fdm' })
      .group("DATE(completion_date)")
      .pluck(
        Arel.sql("DATE(completion_date)"),
        Arel.sql("SUM(COALESCE(actual_weight, slicer_weight, 0))")
      )
      .to_h
  end

  # ---------------------------
  # Breakdowns (completions)
  # ---------------------------

  # ✅ Popularity by *prints* (not jobs). Quantity 0/blank counts as 1.
  def filament_color_counts
    @non_cancelled_completed
      .where.not(filament_color: [nil, ""])
      .group(:filament_color)
      .sum(Arel.sql(NORMALIZED_QUANTITY_SQL))
  end

  def popular_filament
    filament_color_counts.max_by { |_, c| c }&.first
  end

  def category_counts
    @non_cancelled_completed.joins(:category).group('categories.name').count
  end

  private

  # One design key per job
  def design_key_for(job)
    if job.printable_model_id.present?
      "pm:#{job.printable_model_id}"
    elsif job.url.present?
      "url:#{normalize_url(job.url)}"
    elsif job.model_files.attached?
      sums = job.model_files.map { |att| att.blob&.checksum }.compact.sort
      sums.any? ? "files:#{sums.join('|')}" : "job:#{job.id}"
    else
      "job:#{job.id}"
    end
  end

  # Gentle URL normalizer so the same design link doesn’t count multiple times
  def normalize_url(url)
    begin
      u = URI.parse(url.to_s.strip)
      host   = (u.host || '').downcase
      path   = (u.path || '').chomp('/')
      scheme = (u.scheme || 'https').downcase
      "#{scheme}://#{host}#{path}"
    rescue
      url.to_s.strip.downcase
    end
  end
end
