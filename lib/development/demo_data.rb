require "stringio"
require "ipaddr"
require "digest"
require "active_job/queue_adapters/test_adapter"

module Development
  class DemoData
    class Error < StandardError; end

    PREFIX = "make-demo:v1:"
    STATUS_COUNTS = {
      "pending" => 24, "information_requested" => 20, "response_received" => 18,
      "approved" => 34, "in_progress" => 28, "ready_for_pickup" => 32,
      "archived" => 105, "ongoing" => 12, "cancelled" => 10, "rejected" => 7, "abandoned" => 10
    }.freeze
    STATUS_NAMES = { "pending" => "Pending", "information_requested" => "Information Requested",
      "response_received" => "Response Received", "approved" => "Approved", "in_progress" => "In Progress",
      "ready_for_pickup" => "Ready for pickup", "archived" => "Archived", "ongoing" => "Ongoing",
      "cancelled" => "Cancelled", "rejected" => "Rejected", "abandoned" => "Abandoned" }.freeze
    MODEL_NAMES = ["Cable clip", "Desk organizer", "Book stand", "Handle adapter", "Grip aid", "Key turner",
      "Spinner", "Texture tile", "Interlocking rings", "Replacement cap", "Bracket", "Nameplate"].freeze

    def initialize(count: 300, model_file: nil, replace_library_files: false)
      @count = Integer(count.to_s, exception: false)
      @created_blobs = []
      @model_file = model_file.presence
      @replace_library_files = replace_library_files
    end

    def call
      validate_target!
      with_mail_disabled do
        ApplicationRecord.transaction do
          ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(hashtext('make-demo-v1'))")
          prepare_lookups
          prepare_staff
          Current.set(staff_user: @staff.first, synchronous_mail_delivery: false) do
            Audited.audit_class.as_user(@staff.first) do
              prepare_locations_and_printers
              prepare_models
              replace_library_files if @replace_library_files
              prepare_patrons
              prepare_jobs
            end
          end
        end
      end
      summary
    rescue StandardError
      # Database rollback cannot roll back newly uploaded files. These keys were
      # created by this invocation alone; existing attachments are never purged.
      @created_blobs.each { |blob| blob.service.delete(blob.key) unless ActiveStorage::Blob.exists?(blob.id) }
      raise
    end

    private

    def validate_target!
      raise Error, "COUNT must be an integer between 1 and 1000." unless @count && (1..1000).cover?(@count)
      raise Error, "Demo data is restricted to development and test." unless Rails.env.development? || Rails.env.test?

      configuration = ActiveRecord::Base.connection_db_config
      settings = configuration.configuration_hash
      allowed_database = "make_at_tadl_#{Rails.env}"
      unless configuration.adapter == "postgresql" && configuration.database == allowed_database &&
          local_host?(settings[:host]) && local_host?(settings[:hostaddr])
        raise Error, "Use the local #{allowed_database} PostgreSQL database for demo data."
      end
      database, address = ActiveRecord::Base.connection.select_rows("SELECT current_database(), inet_server_addr()::text").first
      unless database == allowed_database && (address.nil? || IPAddr.new(address).loopback?)
        raise Error, "The connected database is not the expected local development/test database."
      end
      unless ActiveStorage::Blob.service.is_a?(ActiveStorage::Service::DiskService)
        raise Error, "Demo assets require local disk storage."
      end
      if @model_file && (!File.file?(@model_file) || !File.readable?(@model_file) || File.extname(@model_file).downcase != ".stl" || !File.size(@model_file).between?(84, 20.megabytes))
        raise Error, "MODEL_FILE must be a readable STL file of at most 20 MB."
      end
      raise Error, "MODEL_FILE is required when replacing library files." if @replace_library_files && !@model_file
    end

    def local_host?(host)
      host.nil? || host == "" || host == "localhost" || host.to_s.start_with?("/") || IPAddr.new(host).loopback?
    rescue IPAddr::InvalidAddressError
      false
    end

    def with_mail_disabled
      mailers = [ActionMailer::Base, ApplicationMailer, JobMailer, PatronMailer, MentionMailer]
      delivery_settings = mailers.to_h { |mailer| [mailer, [mailer.perform_deliveries, mailer.delivery_method]] }
      adapters = mailers.map(&:delivery_job).uniq.to_h { |job| [job, job.queue_adapter] }
      mailers.each { |mailer| mailer.perform_deliveries = false; mailer.delivery_method = :test }
      adapters.each_key { |job| job.queue_adapter = ActiveJob::QueueAdapters::TestAdapter.new }
      yield
    ensure
      delivery_settings&.each { |mailer, (deliver, method)| mailer.perform_deliveries = deliver; mailer.delivery_method = method }
      adapters&.each { |job, adapter| job.queue_adapter = adapter }
    end

    def prepare_lookups
      @statuses = STATUS_COUNTS.keys.each_with_index.to_h do |code, position|
        [code, Status.find_or_create_by!(code: code) { |record| record.name = STATUS_NAMES.fetch(code); record.position = position }]
      end
      @categories = %w[Patron Staff Assistive Fidget].each_with_index.to_h do |name, position|
        [name, Category.order(:id).find_by(name: name) || Category.create!(name: name, position: position)]
      end
      @print_types = %w[fdm resin].each_with_index.to_h do |code, position|
        [code, PrintType.find_or_create_by!(code: code) { |record| record.name = code.upcase; record.position = position }]
      end
      @colors = [ ["demo_blue", "Demo Blue", "#49688e"], ["demo_teal", "Demo Teal", "#07846c"],
        ["demo_white", "Demo White", "#ffffff"], ["multiple", "Multiple", nil] ].map.with_index do |(code, name, rgb), position|
        FilamentColor.find_or_create_by!(code: code) { |record| record.assign_attributes(name: name, rgb: rgb, position: position, active: true) }
      end
    end

    def prepare_staff
      @reviewer_ids = StaffUser.where.not("uid LIKE ?", "make-demo-v1-staff-%").order(:id).limit(10).pluck(:id)
      @staff = %w[Alex Sam Morgan].map.with_index do |name, index|
        uid = "make-demo-v1-staff-#{index + 1}"
        email = "make-demo-staff-#{index + 1}@example.org"
        existing = StaffUser.find_by(uid: uid)
        raise Error, "A demo staff identifier is already used by another account." if existing && existing.email != email
        existing || StaffUser.create!(uid: uid, email: email, name: "Demo Maker #{name}", admin: false)
      end
    end

    def owned_record(klass, finder, attributes, key)
      record = klass.find_by(finder)
      if record
        unless record.audits.where(action: "create", comment: "#{PREFIX}#{key}").exists?
          raise Error, "A reserved demo identifier already belongs to a non-demo #{klass.name}."
        end
        return record
      end
      klass.create!(attributes.merge(finder).merge(audit_comment: "#{PREFIX}#{key}"))
    end

    def prepare_locations_and_printers
      settings = [ ["central", "Central Workshop", true, true, true], ["east", "East Branch", false, true, false],
        ["north", "North Branch", true, true, false], ["south", "South Workshop", false, true, true],
        ["west", "West Pickup", false, false, false] ]
      @locations = settings.map.with_index do |(code, name, scan, fdm, resin), position|
        owned_record(PickupLocation, { code: "demo_#{code}" },
          { name: "Demo #{name}", active: true, scanner: scan, fdm_printer: fdm, resin_printer: resin, position: position }, "location:#{code}")
      end
      @printers = @locations.flat_map do |location|
        %w[fdm resin].filter_map do |code|
          next unless location.public_send("#{code}_printer?")
          owned_record(Printer, { name: "#{location.name} #{code.upcase}" },
            { pickup_location: location, print_type: @print_types.fetch(code), printer_model: "Synthetic #{code.upcase} printer",
              bed_size: code == "fdm" ? "220 × 220 × 250 mm" : "130 × 80 × 160 mm", location: "Demo workbench", public: code == "fdm" }, "printer:#{location.code}:#{code}")
        end
      end
    end

    def prepare_models
      @models = MODEL_NAMES.map.with_index do |name, index|
        code = "make_demo_#{index + 1}"
        existing = PrintableModel.find_by(code: code)
        model = owned_record(PrintableModel, { code: code },
          { name: "Demo #{name}", category: @categories.fetch(%w[Staff Assistive Fidget][index / 4]), position: index,
            weight_grams: 8 + index * 3,
            notes: "Synthetic geometry for interface testing; not a functional product.\nTest setup: PLA, 0.20 mm layers, 15% infill, no supports. Adjust settings before a real print." }, "model:#{index + 1}")
        unless existing
          extension = index % 3 == 2 ? "3mf" : "stl"
          bytes = extension == "3mf" ? DemoAssets.three_mf(scale: index + 1) : DemoAssets.stl(scale: index + 1)
          model.model_file.attach(@model_file ? template_blob : upload(bytes, "demo-model-#{index + 1}.#{extension}", extension == "stl" ? "model/stl" : "model/3mf"))
          # Leave half without a photo so the generated-thumbnail path is testable.
          model.preview_image.attach(preview_blob(index)) if index.even? && !@model_file
        end
        model
      end
    end

    def template_blob
      @template_blob ||= begin
        bytes = File.binread(@model_file)
        key = "make-demo-v1-template-#{Digest::SHA256.hexdigest(bytes)}"
        ActiveStorage::Blob.find_by(key: key) || upload(bytes, File.basename(@model_file), "model/stl", key: key)
      end
    end

    def replace_library_files
      PrintableModel.with_attached_model_file.with_attached_preview_image.find_each do |model|
        next if model.model_file.attached? && model.model_file.blob_id == template_blob.id
        model.model_file.attach(template_blob)
        if model.preview_image.attached? && model.preview_image.blob.metadata["make_demo_asset"] && model.preview_image.filename.to_s.match?(/\Ademo-preview-[0-2]\.png\z/)
          model.preview_image.detach
        end
      end
    end

    def preview_blob(index)
      @previews ||= {}
      color = %w[#49688e #07846c #0b2f57][index % 3]
      @previews[color] ||= upload(DemoAssets.png(color: color), "demo-preview-#{index % 3}.png", "image/png")
    end

    def upload(bytes, filename, content_type, **options)
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: filename,
        content_type: content_type, identify: false, metadata: { identified: true, analyzed: true, make_demo_asset: true }, **options)
      @created_blobs << blob
      blob
    end

    def prepare_patrons
      @patrons = [(@count / 4.0).ceil, 12].max.times.map do |index|
        owned_record(Patron, { email: "make-demo-patron-#{format('%03d', index + 1)}@example.org" },
          { name: "Demo Patron #{format('%03d', index + 1)}" }, "patron:#{index + 1}")
      end
    end

    def prepare_jobs
      existing_ids = Audited::Audit.where(auditable_type: "Job", action: "create")
        .where("comment LIKE ?", "#{PREFIX}job:%").order(:id).pluck(:comment, :auditable_id).to_h
      existing = Job.where(id: existing_ids.values).pluck(:id)
      @job_ids = []
      @created_count = 0
      sequence = STATUS_COUNTS.keys + STATUS_COUNTS.flat_map { |code, count| [code] * (count - 1) }.shuffle(random: Random.new(20261117))
      @count.times do |index|
        marker = "#{PREFIX}job:#{index + 1}"
        id = existing_ids[marker]
        if id && existing.include?(id)
          @job_ids << id
          next
        end
        @job_ids << create_job(index, sequence[index % sequence.size], marker).id
        @created_count += 1
      end
    end

    def create_job(index, status_code, marker)
      scan = index % 5 == 0
      category_name = scan ? "Patron" : %w[Patron Patron Patron Patron Patron Staff Staff Fidget Fidget Assistive][(index / 3) % 10]
      category_name = "Staff" if status_code == "ongoing"
      resin = !scan && %w[Patron Staff].include?(category_name) && index % 4 == 0
      model = scan || resin ? nil : @models[index % @models.size]
      quantity = [1, 1, 2, 3, 5, 10][index % 6]
      dates = job_dates(index, status_code)
      terminal = %w[ready_for_pickup archived abandoned].include?(status_code)
      weight = (8 + index % 73) * quantity
      attributes = {
        patron: @patrons[index % @patrons.size], status: @statuses.fetch(status_code == "information_requested" ? "pending" : status_code),
        category: @categories.fetch(category_name), pickup_location: @locations[index % @locations.size].code,
        notes: "Demo job #{format('%03d', index + 1)}: synthetic #{scan ? 'scan' : 'print'} request for workflow testing.",
        created_at: dates.fetch(:created_at), updated_at: dates.fetch(:updated_at), quantity: quantity,
        spray_ok: scan && index.even?, audit_comment: marker
      }
      unless scan
        attributes.merge!(print_type: @print_types.fetch(resin ? "resin" : "fdm"), filament_color: @colors[index % @colors.size].code,
          printable_model: model, url: "https://example.org/demo-models/#{index + 1}", print_time_estimate: 30 + (index % 17) * 35,
          print_notify: index.even?, slicer_weight: status_code == "pending" || resin ? nil : weight,
          actual_weight: terminal && !resin ? weight + 2 : nil, resin_volume_ml: terminal && resin ? 12 + index % 60 : nil)
      end
      job = (scan ? ScanJob : PrintJob).new(attributes)
      if @model_file
        job.model_files.attach(template_blob)
      elsif model&.model_file&.attached?
        job.model_files.attach(model.model_file.blob)
      end
      job.save!
      job.model_files.attach(@models[(index + 1) % @models.size].model_file.blob) if index % 9 == 0
      job.scan_image.attach(preview_blob(index)) if scan
      create_messages(job, index, dates.fetch(:created_at))
      final = dates.merge(status_id: @statuses.fetch(status_code).id)
      if !scan && %w[in_progress ready_for_pickup archived abandoned ongoing].include?(status_code)
        candidates = @printers.select { |printer| printer.print_type_code == (resin ? "resin" : "fdm") }
        final[:assigned_printer_id] = candidates[index % candidates.size].id
      end
      final[:started_by_id] = @staff[index % @staff.size].id if dates[:started_at]
      final[:finished_by_id] = @staff[(index + 1) % @staff.size].id if dates[:finished_at]
      # Historical demo snapshots are not live workflow transitions. Running
      # transition callbacks here would alter the intended state and send mail.
      job.update_columns(final)
      job
    end

    def job_dates(index, status)
      now = Time.current.change(usec: 0)
      terminal = %w[archived abandoned cancelled rejected].include?(status)
      age = terminal ? 12 + (index * 17) % 520 : 2 + index % 19
      age = [age, 40].max if status == "abandoned"
      created = now - age.days
      dates = { created_at: created, updated_at: created + 1.day }
      if %w[in_progress ready_for_pickup archived abandoned].include?(status)
        dates[:started_at] = created + 6.hours
      end
      if %w[ready_for_pickup archived abandoned].include?(status)
        complete = status == "ready_for_pickup" ? [0, 2, 6, 7, 14, 29, 30, 31][index % 8].days.ago.to_date : (created + 2.days).to_date
        created = [created, complete.beginning_of_day - 2.days].min
        dates.merge!(created_at: created, started_at: created + 6.hours, completion_date: complete,
          finished_at: [complete.middle_of_day, now].min, updated_at: [complete.middle_of_day, now].min)
        dates[:pickup_date] = complete + 2.days if status == "archived"
        dates[:last_pickup_reminder_sent_at] = complete.middle_of_day + 7.days if index.even? && complete <= 14.days.ago.to_date
      end
      if status == "information_requested"
        anchor = [1, 6, 7, 13, 14, 15][index % 6].days.ago
        dates[:created_at] = [created, anchor - 1.day].min
        dates[:information_requested_at] = index % 13 == 0 ? nil : anchor
        dates[:last_quote_reminder_sent_at] = 7.days.ago if index.even? && anchor < 8.days.ago
      end
      dates[:updated_at] = [dates[:updated_at], dates[:started_at], dates[:finished_at], dates[:pickup_date]&.middle_of_day,
        dates[:information_requested_at], dates[:last_quote_reminder_sent_at], dates[:last_pickup_reminder_sent_at]].compact.max
      dates
    end

    def create_messages(job, index, received_at)
      job.conversation.messages.create!(author: job.patron,
        body: "Synthetic request: can you help prepare this model? Demo record #{index + 1}.",
        created_at: received_at, updated_at: received_at, read_at: index % 4 == 0 ? nil : received_at + 1.hour)
      job.conversation.messages.create!(author: @staff[index % @staff.size], body: "Demo reply: the model has been reviewed and the next steps are noted here.",
        created_at: received_at + 2.hours, updated_at: received_at + 2.hours)
      note = job.conversation.messages.create!(author: @staff[(index + 1) % @staff.size], staff_note_only: true,
        body: "Demo printing notes: check orientation and supports; verify dimensions before slicing.",
        created_at: received_at + 3.hours, updated_at: received_at + 3.hours)
      note.images.attach(preview_blob(index)) if index % 12 == 0
      return unless index % 15 == 0
      (@reviewer_ids + [@staff[index % @staff.size].id]).uniq.each do |id|
        Notification.create!(staff_user_id: id, message: note)
      end
    end

    def summary
      jobs = Job.where(id: @job_ids)
      { created_jobs: @created_count, existing_jobs: @count - @created_count, requested_demo_jobs: jobs.count,
        statuses: jobs.joins(:status).group("statuses.code").count, types: jobs.group(:type).count,
        pickup_locations: jobs.group(:pickup_location).count }
    end
  end
end
