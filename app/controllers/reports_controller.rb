# app/controllers/reports_controller.rb

class ReportsController < ApplicationController
  before_action :authenticate_staff!

  def print
    year  = params[:year].to_i.nonzero?  || (Date.current - 1.month).year
    month = params[:month].to_i.nonzero? || (Date.current - 1.month).month
    @period = Date.new(year, month)

    completed = PrintJob.where(completion_date: @period.all_month)
    cancelled = PrintJob.joins(:status).where(statuses: { code: 'cancelled' }).where(updated_at: @period.all_month)

    job_ids = completed.ids + cancelled.ids
    jobs    = PrintJob.where(id: job_ids)

    @orders_count     = completed.count
    @cancelled_count  = cancelled.count
    @distinct_patrons = jobs.select(:patron_id).distinct.count

    fdm_scope   = completed.joins(:print_type).where(print_types: { code: 'fdm' })
    resin_scope = completed.joins(:print_type).where(print_types: { code: 'resin' })

    @fdm_count      = fdm_scope.count
    @resin_count    = resin_scope.count
    @resin_ml       = resin_scope.sum(:resin_volume_ml).to_i

    @multiple_count = jobs.where(filament_color: 'multiple').count

    @total_quantity = completed.sum(:quantity)

    pm_count       = completed.where.not(printable_model_id: nil).distinct.count(:printable_model_id)
    jobs_without_pm = completed.where(printable_model_id: nil)
    urls           = jobs_without_pm.pluck(:url).reject(&:blank?)
    files          = jobs_without_pm.select { |j| j.model_file.attached? }.map { |j| j.model_file.filename.to_s }
    @unique_designs = pm_count + (urls + files).uniq.size

    @filament_grams = fdm_scope.sum(:actual_weight).to_i

    @filament_per_day = PrintJob
      .where.not(completion_date: nil)
      .group("DATE(completion_date)")
      .sum(:actual_weight)

    # Most requested filament color
    @popular_filament = completed.group(:filament_color).order('count_id DESC').count(:id).first&.first

    # Print jobs per day for chart
    @prints_per_day = PrintJob
      .where.not(completion_date: nil)
      .group("DATE(completion_date)")
      .order("DATE(completion_date)")
      .count

    @filament_color_counts = PrintJob
      .where.not(filament_color: [nil, ""])
      .group(:filament_color)
      .count

    # Category breakdown
    @category_counts = jobs.joins(:category).group('categories.name').count

    respond_to do |format|
      format.html
      format.json
    end
  end

  private

  def authenticate_staff!
    return if current_staff_user
    session[:user_return_to] = request.fullpath
    redirect_to '/auth/google_oauth2'
  end
end
