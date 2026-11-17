module Admin
  class StatisticsController < BaseController
    MAX_RANGE_DAYS = 3_660

    def index
      authorize! :read, :dashboard
      @page_title = "Statistics"
      @locations = PickupLocation.reorder(Arel.sql("LOWER(name) ASC"), :id).to_a
      @presets = date_presets
      @start_date = selected_date(:start, 29.days.ago.to_date)
      @end_date = selected_date(:end, Date.current)
      @selected_location = @locations.find { |location| location.code == params[:location] }
      validate_filters

      if @filter_error
        render :index, status: :unprocessable_content
      else
        prepare_report
      end
    end

    private

    def selected_date(key, fallback)
      value = params[key]
      return fallback if value.blank?

      unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        raise Date::Error
      end

      Date.iso8601(value)
    rescue Date::Error
      @filter_error = "Enter valid start and end dates in YYYY-MM-DD format."
      fallback
    end

    def validate_filters
      @filter_error ||= "Choose a location from the list." if params[:location].present? && !@selected_location
      @filter_error ||= "The end date must be on or after the start date." if @end_date < @start_date
      if (@end_date - @start_date).to_i >= MAX_RANGE_DAYS
        @filter_error ||= "Choose a date range of #{MAX_RANGE_DAYS} days or fewer."
      end
    end

    def prepare_report
      @report = PrintJobReport.new(
        start_date: @start_date, end_date: @end_date,
        pickup_location: @selected_location&.code
      )
      @category_counts = @report.category_counts
      @completed_jobs = @category_counts.values.sum
      @fdm_jobs = @report.fdm_count
      @resin_jobs = @report.resin_count
      @total_quantity = @report.total_quantity
      @filament_grams = @report.filament_grams
      @resin_ml = @report.resin_ml
      @scan_completions = @report.scan_completed_count
      @filament_counts = @report.filament_color_counts
      @popular_color, @popular_color_count = @filament_counts.max_by { |_code, count| count } || [nil, 0]

      @submission_metrics = {
        "Print orders submitted" => @report.orders_count,
        "Cancelled orders" => @report.cancelled_count,
        "Rejected orders" => @report.rejected_count,
        "Distinct patrons" => @report.distinct_patrons
      }
      @completion_metrics = {
        "Print jobs completed" => @completed_jobs,
        "FDM jobs" => @fdm_jobs,
        "Resin jobs" => @resin_jobs,
        "Multicolor jobs" => @report.multiple_count,
        "Scan jobs completed" => @scan_completions,
        "Total prints" => @total_quantity,
        "Unique designs" => @report.unique_designs
      }

      prints = @report.prints_per_day
      filament = @report.filament_per_day
      @daily_rows = (@start_date..@end_date).map do |day|
        { date: day, prints: prints.fetch(day, 0), filament: filament.fetch(day, 0) }
      end

      colors_by_code = FilamentColor.where(code: @filament_counts.keys).pluck(:code, :rgb).to_h
      palette = %w[#4e79a7 #f28e2b #e15759 #76b7b2 #59a14f #edc949 #af7aa1 #ff9da7 #9c755f #bab0ab]
      @chart_data = {
        labels: @daily_rows.map { |row| row[:date].iso8601 },
        prints: @daily_rows.map { |row| row[:prints] },
        filament: @daily_rows.map { |row| row[:filament].to_f },
        colorLabels: @filament_counts.keys.map(&:titleize),
        colorValues: @filament_counts.values,
        colors: @filament_counts.keys.each_with_index.map do |code, index|
          color = colors_by_code[code].to_s
          color.match?(/\A#[0-9a-f]{6}\z/i) ? color : palette[index % palette.length]
        end
      }
    end

    def date_presets
      today = Date.current
      previous_month = today.prev_month
      {
        "Yesterday" => [today.yesterday, today.yesterday],
        "Last 7 Days" => [today - 6.days, today],
        "Last 30 Days" => [today - 29.days, today],
        "Current Month" => [today.beginning_of_month, today],
        "Previous Month" => [previous_month.beginning_of_month, previous_month.end_of_month],
        "Current Year" => [today.beginning_of_year, today],
        "Previous Year" => [today.last_year.beginning_of_year, today.last_year.end_of_year]
      }
    end
  end
end
