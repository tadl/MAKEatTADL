# app/services/print_job_report.rb
class PrintJobReport
  attr_reader :start_date, :end_date

  # Expect Date/Time; we normalize to a closed day-range
  def initialize(start_date:, end_date:)
    @start_date = start_date.beginning_of_day
    @end_date   = end_date.end_of_day

    # Base scopes used consistently throughout
    @submitted   = PrintJob.where(created_at: @start_date..@end_date)
    @completed   = PrintJob.where.not(completion_date: nil)
                           .where(completion_date: @start_date..@end_date)
    @non_cancelled_completed = @completed.joins(:status).where.not(statuses: { code: 'cancelled' })
  end

  # ---------------------------
  # "Orders" = submissions flow
  # ---------------------------

  # Orders submitted in the window
  def orders_count
    @submitted.count
  end

  # Of the above orders, how many are (currently) cancelled
  # (keeps it a subset of orders_count; avoids updated_at mismatch)
  def cancelled_count
    @submitted.joins(:status).where(statuses: { code: 'cancelled' }).count
  end

  # Distinct patrons who submitted during the window
  def distinct_patrons
    @submitted.select(:patron_id).distinct.count
  end

  # ---------------------------
  # Output/completions metrics
  # ---------------------------

  # Completed FDM jobs (non-cancelled) in window
  def fdm_count
    @non_cancelled_completed.joins(:print_type).where(print_types: { code: 'fdm' }).count
  end

  # Completed resin jobs (non-cancelled) in window
  def resin_count
    @non_cancelled_completed.joins(:print_type).where(print_types: { code: 'resin' }).count
  end

  # If you use filament_color == 'multiple' to mean multi-color, keep it here
  def multiple_count
    @non_cancelled_completed.where(filament_color: 'multiple').count
  end

  # Sum of quantities for completed, non-cancelled jobs (default to 1 if nil)
  def total_quantity
    @non_cancelled_completed.sum(Arel.sql("COALESCE(quantity, 1)"))
  end

  # Filament used in grams, prefer actual_weight else slicer_weight, non-cancelled
  def filament_grams
    @non_cancelled_completed
      .joins(:print_type).where(print_types: { code: 'fdm' })
      .sum(Arel.sql("COALESCE(actual_weight, slicer_weight, 0)")).to_i
  end

  # Resin used (mL) for completed, non-cancelled resin jobs
  def resin_ml
    @non_cancelled_completed
      .joins(:print_type).where(print_types: { code: 'resin' })
      .sum(Arel.sql("COALESCE(resin_volume_ml, 0)")).to_i
  end

  # Distinct designs among completed, non-cancelled jobs:
  # - printable_model_id if present
  # - else: distinct ActiveStorage blob checksums for attached files
  # - plus: distinct normalized URLs
  def unique_designs
    pm_count = @non_cancelled_completed.where.not(printable_model_id: nil)
                                       .distinct.count(:printable_model_id)

    # Only jobs w/o a PrintableModel
    file_jobs = @non_cancelled_completed.where(printable_model_id: nil)

    # Distinct blob checksums for model_files
    checksums = file_jobs
      .joins("LEFT JOIN active_storage_attachments asa ON asa.record_type = 'Job' AND asa.record_id = jobs.id AND asa.name = 'model_files'")
      .joins("LEFT JOIN active_storage_blobs asb ON asb.id = asa.blob_id")
      .where.not(asb: { checksum: nil })
      .distinct
      .pluck('asb.checksum')

    # Distinct normalized URLs for jobs with a URL
    urls = file_jobs.where.not(url: [nil, ''])
                    .pluck(:url)
                    .map { |u| normalize_url(u) }
                    .uniq

    pm_count + (checksums + urls).uniq.size
  end

  # ---------------------------
  # Per-day series (completions)
  # ---------------------------

  # Prints per day = sum of COALESCE(quantity,1) on completed, non-cancelled
  def prints_per_day
    @non_cancelled_completed
      .group("DATE(completion_date)")
      .pluck(Arel.sql("DATE(completion_date)"), Arel.sql("SUM(COALESCE(quantity,1))"))
      .to_h
  end

  # Filament per day (g), prefer actual_weight else slicer_weight, completed non-cancelled
  def filament_per_day
    @non_cancelled_completed
      .group("DATE(completion_date)")
      .pluck(Arel.sql("DATE(completion_date)"), Arel.sql("SUM(COALESCE(actual_weight, slicer_weight, 0))"))
      .to_h
  end

  # ---------------------------
  # Breakdowns (completions)
  # ---------------------------

  def filament_color_counts
    @non_cancelled_completed
      .where.not(filament_color: [nil, ""])
      .group(:filament_color).count
  end

  def popular_filament
    filament_color_counts.max_by { |_, c| c }&.first
  end

  def category_counts
    @non_cancelled_completed.joins(:category).group('categories.name').count
  end

  private

  # A gentle URL normalizer so the same design link doesn’t count multiple times
  def normalize_url(url)
    begin
      u = URI.parse(url.to_s.strip)
      return url.to_s.strip.downcase if u.nil?

      # Lowercase host, strip trailing slash, ignore query/fragment (often irrelevant for the design)
      host = (u.host || '').downcase
      path = (u.path || '').chomp('/')
      scheme = (u.scheme || 'https').downcase
      "#{scheme}://#{host}#{path}"
    rescue
      url.to_s.strip.downcase
    end
  end
end
