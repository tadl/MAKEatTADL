require "csv"

module Admin
  class PatronsController < BaseController
    before_action :load_patron, only: %i[show edit update destroy merge]

    def index
      authorize! :read, Patron
      @page_title = "Patrons"
      @query = params[:q].to_s.strip.first(200)
      @patrons = paginate_scope(filtered_patrons.order(Arel.sql("LOWER(patrons.email) ASC"), :id))
      @job_counts = Job.where(patron_id: @patrons.map(&:id)).group(:patron_id).count
    end

    def show
      authorize! :read, @patron
      @page_title = @patron.name.presence || @patron.email
      @jobs = paginate_scope(@patron.jobs.includes(:status, :category).order(created_at: :desc, id: :desc))
    end

    def new
      authorize! :create, Patron
      @patron = Patron.new
      @page_title = "New patron"
    end

    def create
      authorize! :create, Patron
      @patron = Patron.new(patron_params)
      @page_title = "New patron"

      if @patron.save
        redirect_to admin_patron_path(@patron), notice: "Patron created."
      else
        render :new, status: :unprocessable_content
      end
    rescue ActiveRecord::RecordNotUnique
      @patron.errors.add(:email, "has already been taken")
      render :new, status: :unprocessable_content
    end

    def edit
      authorize! :update, @patron
      @page_title = "Edit patron"
    end

    def update
      authorize! :update, @patron
      @page_title = "Edit patron"

      if @patron.update(patron_params)
        redirect_to admin_patron_path(@patron), notice: "Patron updated."
      else
        render :edit, status: :unprocessable_content
      end
    rescue ActiveRecord::RecordNotUnique
      @patron.errors.add(:email, "has already been taken")
      render :edit, status: :unprocessable_content
    end

    def destroy
      authorize! :destroy, @patron
      @patron.destroy!
      redirect_to admin_patrons_path, notice: "Patron deleted."
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
      redirect_to admin_patron_path(@patron), alert: "This patron could not be deleted. Check their associated records."
    end

    def bulk_destroy
      authorize! :destroy, Patron
      ids = Array(params[:ids]).map(&:to_s).select { |id| id.match?(/\A[1-9]\d*\z/) }.uniq
      if ids.empty? || ids.length > 100
        redirect_to admin_patrons_path, alert: "Select between 1 and 100 patrons to delete."
        return
      end

      deleted = 0
      Patron.transaction do
        Patron.where(id: ids).find_each do |patron|
          authorize! :destroy, patron
          patron.destroy!
          deleted += 1
        end
      end
      redirect_to admin_patrons_path, notice: "#{deleted} #{'patron'.pluralize(deleted)} deleted."
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
      redirect_to admin_patrons_path, alert: "The selected patrons could not be deleted. No patrons were deleted."
    end

    def export
      authorize! :export, Patron
      @query = params[:q].to_s.strip.first(200)
      filename = "patrons-#{Date.current.iso8601}"
      case request.format.symbol
      when :html, :csv
        csv = CSV.generate do |rows|
          rows << ["ID", "Name", "Email", "Created"]
          filtered_patrons.find_each do |patron|
            rows << [patron.id, csv_text(patron.name), csv_text(patron.email), patron.created_at.iso8601]
          end
        end
        send_data csv, filename: "#{filename}.csv", type: "text/csv"
      when :json
        send_data export_records.to_json, filename: "#{filename}.json", type: "application/json"
      when :xml
        send_data export_records.to_xml(root: "patrons", skip_types: true), filename: "#{filename}.xml", type: "application/xml"
      else
        head :not_acceptable
      end
    end

    def merge
      authorize! :merge_patron, @patron
      @page_title = "Merge patron"
      @query = params[:q].to_s.strip.first(200)
      @merge_candidates = filtered_patrons.where.not(id: @patron.id)
        .order(Arel.sql("LOWER(patrons.email) ASC"), :id).limit(100)

      return unless request.post?

      winner = Patron.find_by(id: params[:target_patron_id])
      unless winner
        @patron.errors.add(:base, "Choose the patron record to keep.")
        render :merge, status: :unprocessable_content
        return
      end

      result = PatronMergeService.call(winner: winner, loser: @patron)
      redirect_to admin_patron_path(result.winner),
        notice: "Patrons merged. Moved #{result.jobs_moved} #{'job'.pluralize(result.jobs_moved)} and #{result.messages_moved} #{'message'.pluralize(result.messages_moved)}."
    rescue PatronMergeService::MergeError => error
      @patron.errors.add(:base, error.message)
      render :merge, status: :unprocessable_content
    end

    private

    def load_patron
      @patron = Patron.find(params[:id])
    end

    def patron_params
      # Authentication tokens and job ownership are not contact fields.
      params.expect(patron: %i[name email])
    end

    def filtered_patrons
      scope = Patron.all
      if @query.present?
        query = "%#{Patron.sanitize_sql_like(@query)}%"
        scope = scope.where("patrons.name ILIKE :query OR patrons.email ILIKE :query", query: query)
      end
      scope
    end

    def csv_text(value)
      text = value.to_s
      text.match?(/\A[\s\uFEFF]*[=+\-@]/) ? "'#{text}" : text
    end

    def export_records
      filtered_patrons.find_each.map do |patron|
        patron.attributes.slice("id", "name", "email", "created_at")
      end
    end
  end
end
