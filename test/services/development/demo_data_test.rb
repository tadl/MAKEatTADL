require "test_helper"
require "tempfile"
require Rails.root.join("lib/development/demo_assets")
require Rails.root.join("lib/development/demo_data")

class DevelopmentDemoDataTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup { travel_to Time.zone.local(2026, 11, 17, 16, 0, 0) }
  teardown { travel_back }

  test "invalid counts reject before accessing the database or writing records" do
    [0, -1, 1001, "many", "2.5", "", nil].each do |count|
      assert_no_changes -> { record_counts } do
        with_stub(ActiveRecord::Base, :connection, -> { flunk "Invalid COUNT opened a connection" }) do
          assert_raises(Development::DemoData::Error) { generate(count: count) }
        end
      end
    end
  end

  test "production remote hosts hostaddr and unexpected databases reject before connection" do
    with_stub(ActiveRecord::Base, :connection, -> { flunk "Production opened a connection" }) do
      with_stub(Rails, :env, ActiveSupport::StringInquirer.new("production")) do
        assert_raises(Development::DemoData::Error) { generate(count: 1) }
      end
    end

    [
      { host: "203.0.113.20" },
      { host: "db.example.org" },
      { host: "localhost", hostaddr: "203.0.113.21" },
      { database: "make_at_tadl_production" },
      { adapter: "sqlite3" }
    ].each do |overrides|
      configuration = database_configuration(overrides)
      with_stub(ActiveRecord::Base, :connection_db_config, configuration) do
        with_stub(ActiveRecord::Base, :connection, -> { flunk "Rejected target opened a connection" }) do
          assert_raises(Development::DemoData::Error) { generate(count: 1) }
        end
      end
    end
  end

  test "the connected database address and local disk storage are verified before writes" do
    [["make_at_tadl_production", nil], ["make_at_tadl_test", "203.0.113.22"]].each do |row|
      connection = Object.new
      connection.define_singleton_method(:select_rows) { |_sql| [row] }
      with_stub(ActiveRecord::Base, :connection_db_config, database_configuration) do
        with_stub(ActiveRecord::Base, :connection, connection) do
          assert_raises(Development::DemoData::Error) { generate(count: 1) }
        end
      end
    end

    assert_no_changes -> { record_counts } do
      with_stub(ActiveStorage::Blob, :service, Object.new) do
        error = assert_raises(Development::DemoData::Error) { generate(count: 1) }
        assert_match(/local disk storage/, error.message)
      end
    end
  end

  test "the default dataset has 300 valid varied jobs and valid shared fixture assets" do
    result = Development::DemoData.new.call
    assert_equal 300, result[:created_jobs]
    assert_equal 300, result[:requested_demo_jobs]
    assert_equal 11, result[:statuses].size
    assert_equal({ "PrintJob" => 240, "ScanJob" => 60 }, result[:types])
    assert_equal 5, result[:pickup_locations].size
    assert_equal 12, demo_models.count
    assert_equal 75, Patron.where("email LIKE ?", "make-demo-patron-%@example.org").count

    locations = PickupLocation.active.pluck(:code)
    categories = Category.pluck(:id, :name).to_h
    owned_jobs.includes(:status, :category, :assigned_printer).with_attached_model_files.find_each do |job|
      assert job.valid?, job.errors.full_messages.join(", ")
      assert_equal job.class.name, job.type
      assert_equal(job.is_a?(ScanJob) ? "scan" : "print", job.origin)
      assert_includes locations, job.pickup_location
      assert categories.key?(job.category_id)
      assert_operator job.created_at, :<=, job.updated_at
      assert_operator job.updated_at, :<=, Time.current
      assert_equal "Staff", categories.fetch(job.category_id) if job.status.code == "ongoing"

      if job.started_at
        assert_operator job.started_at, :>=, job.created_at
        assert_operator job.started_at, :<=, job.updated_at
        assert job.started_by_id
      end
      if job.finished_at
        assert_operator job.finished_at, :>=, job.started_at
        assert_operator job.finished_at, :<=, job.updated_at
        assert job.finished_by_id
      end
      if job.completion_date
        assert_operator job.completion_date, :<=, Date.current
        assert_operator job.completion_date, :>=, job.created_at.to_date
      end
      if job.pickup_date
        assert_operator job.pickup_date, :>=, job.completion_date
        assert_operator job.pickup_date, :<=, Date.current
      end
      if job.information_requested_at
        assert_operator job.information_requested_at, :>=, job.created_at
        assert_operator job.information_requested_at, :<=, job.updated_at
      end
      if job.last_quote_reminder_sent_at
        assert_operator job.last_quote_reminder_sent_at, :>=, job.information_requested_at
        assert_operator job.last_quote_reminder_sent_at, :<=, job.updated_at
      end
      if job.last_pickup_reminder_sent_at
        assert_operator job.last_pickup_reminder_sent_at.to_date, :>=, job.completion_date
        assert_operator job.last_pickup_reminder_sent_at, :<=, Time.current
      end
      if job.status.code == "abandoned"
        assert_operator job.completion_date, :<=, 30.days.ago.to_date
      end
      if job.is_a?(PrintJob) && job.assigned_printer
        assert_equal job.print_type_code, job.assigned_printer.print_type_code
      end
    end

    models = demo_models.with_attached_model_file.with_attached_preview_image.to_a
    assert_equal 6, models.count { |model| model.preview_image.attached? }
    assert_equal 4, models.count { |model| model.model_file.filename.extension == "3mf" }
    models.each do |model|
      assert model.model_file.attached?
      bytes = model.model_file.download
      if model.model_file.filename.extension == "stl"
        assert_match(/\Asolid /, bytes)
        assert_equal 12, bytes.scan(/facet normal/).size
      else
        assert_equal "PK\x03\x04".b, bytes.byteslice(0, 4)
        assert_includes bytes, "[Content_Types].xml"
        assert_includes bytes, "3D/3dmodel.model"
      end
      next unless model.preview_image.attached?

      image = model.preview_image.download
      assert_equal "\x89PNG\r\n\x1a\n".b, image.byteslice(0, 8)
      assert_equal [320, 200], image.byteslice(16, 8).unpack("NN")
    end
    assert_operator ActiveStorage::Blob.count, :<, 25, "Job files and preview images should reuse their fixture blobs"
  end

  test "reruns preserve edited jobs model notes timestamps and files using create audit ownership" do
    generate(count: 22)
    job = owned_jobs.where(type: "PrintJob").order(:id).first
    model = demo_models.order(:id).first
    job.update!(url: "https://example.org/manually-edited-model", notes: "Manually reviewed job notes.")
    job.model_files.attach(io: StringIO.new(Development::DemoAssets.stl(scale: 0.5)), filename: "manual-job-file.stl", content_type: "model/stl")
    job.update_columns(status_id: Status.find_by!(code: "ongoing").id, created_at: 6.months.ago,
      updated_at: 2.hours.ago, information_requested_at: nil)
    model.update!(notes: "Keep these manually edited settings.", weight_grams: 99)
    model.model_file.attach(io: StringIO.new(Development::DemoAssets.stl(scale: 0.75)), filename: "manual-library-file.stl", content_type: "model/stl")
    model.preview_image.attach(io: StringIO.new(Development::DemoAssets.png(color: "#b45309")), filename: "manual-photo.png", content_type: "image/png")
    before = editable_snapshot(job, model)
    counts = record_counts
    clear_enqueued_jobs

    travel 5.days do
      result = generate(count: 22)
      assert_equal 0, result[:created_jobs]
      assert_equal 22, result[:existing_jobs]
    end

    assert_equal before, editable_snapshot(job, model)
    assert_equal counts, record_counts
    assert_equal 22, owned_jobs.count
    assert job.audits.where(action: "create").where("comment LIKE ?", "#{Development::DemoData::PREFIX}job:%").exists?
  end

  test "larger counts add missing jobs and smaller counts never delete existing demo records" do
    first = generate(count: 22)
    assert_equal 22, first[:created_jobs]
    original_ids = owned_jobs.order(:id).pluck(:id)
    larger = generate(count: 33)
    assert_equal 11, larger[:created_jobs]
    assert_equal 22, larger[:existing_jobs]
    assert_equal 33, owned_jobs.count
    assert_empty original_ids - owned_jobs.pluck(:id)

    counts = record_counts
    smaller = generate(count: 11)
    assert_equal 0, smaller[:created_jobs]
    assert_equal 11, smaller[:existing_jobs]
    assert_equal 11, smaller[:requested_demo_jobs]
    assert_equal counts, record_counts
  end

  test "ordinary existing records and shared lookup identities are preserved" do
    ensure_base_lookups!
    patron = create_patron(name: "Existing Example", email: "existing@example.org")
    job = create_print_job(patron: patron, attrs: { notes: "Keep existing job.", created_at: 1.month.ago, updated_at: 2.days.ago })
    model = PrintableModel.create!(name: "Existing model", code: "existing-model", category: ensure_category("Staff"), notes: "Keep existing settings.")
    pending = Status.find_by!(code: "pending")
    pending.update!(name: "Awaiting local review", position: 81)
    type = PrintType.find_by!(code: "fdm")
    type.update!(name: "Local FDM", position: 82)
    category = Category.find_by!(name: "Patron")
    category.update!(position: 83)
    color = FilamentColor.create!(name: "Existing multicolor", code: "multiple", active: false, rgb: "#123456")
    before = [patron, job, model, pending, type, category, color].map(&:attributes)

    generate(count: 22)

    assert_equal before, [patron, job, model, pending, type, category, color].map { |record| record.reload.attributes }
    assert_equal pending.id, Status.find_by!(code: "pending").id
    assert_equal type.id, PrintType.find_by!(code: "fdm").id
  end

  test "a reserved identifier without demo create audit ownership is not claimed" do
    model = PrintableModel.create!(name: "Existing reserved model", code: "make_demo_1", category: ensure_category("Staff"), notes: "Keep this record.")
    before = model.attributes
    assert_raises(Development::DemoData::Error) do
      ApplicationRecord.transaction(requires_new: true) { generate(count: 22) }
    end
    assert_equal before, model.reload.attributes
    assert_equal 0, owned_jobs.count
  end

  test "mail and enqueue attempts are absent and temporary delivery settings are restored" do
    with_delivery_snapshot do |settings, adapters|
      queues = []
      original_constructor = ActiveJob::QueueAdapters::TestAdapter.method(:new)
      constructor = ->(*arguments, **keywords) { original_constructor.call(*arguments, **keywords).tap { |adapter| queues << adapter } }
      events = []
      subscriber = ->(name, *_arguments) { events << name }
      ActiveSupport::Notifications.subscribed(subscriber, /(?:process|deliver)\.action_mailer|enqueue(?:_at)?\.active_job/) do
        with_stub(ActiveJob::QueueAdapters::TestAdapter, :new, constructor) do
          assert_no_emails { assert_no_enqueued_jobs { generate(count: 22) } }
        end
      end
      assert_empty events
      queues.each { |adapter| assert_empty adapter.enqueued_jobs; assert_empty adapter.performed_jobs }
      assert_delivery_snapshot(settings, adapters)
    end
  end

  test "mail adapters and current staff are restored when generation fails" do
    existing_staff = create_staff_user
    generator = Development::DemoData.new(count: 22)
    with_delivery_snapshot do |settings, adapters|
      Current.set(staff_user: existing_staff, synchronous_mail_delivery: true) do
        with_stub(generator, :prepare_jobs, -> { raise "Synthetic generation failure" }) do
          error = assert_raises(RuntimeError) do
            ApplicationRecord.transaction(requires_new: true) { generator.call }
          end
          assert_equal "Synthetic generation failure", error.message
        end
        assert_equal existing_staff, Current.staff_user
        assert_equal true, Current.synchronous_mail_delivery
      end
      assert_delivery_snapshot(settings, adapters)
    end
  end

  test "a custom template is shared by new library entries and every new demo job" do
    with_template do |path, bytes|
      result = generate(count: 22, model_file: path)
      assert_equal 22, result[:created_jobs]
      models = demo_models.with_attached_model_file.with_attached_preview_image.to_a
      blob_ids = models.map { |model| model.model_file.blob_id }
      assert_equal 1, blob_ids.uniq.size
      assert_equal bytes, models.first.model_file.download
      assert models.none? { |model| model.preview_image.attached? }
      owned_jobs.with_attached_model_files.each do |job|
        assert job.model_files.attached?, "Custom-template jobs should all have a model file"
        assert_equal [blob_ids.first], job.model_files.map(&:blob_id).uniq
      end
      counts = record_counts
      repeated = generate(count: 22, model_file: path)
      assert_equal 0, repeated[:created_jobs]
      assert_equal counts, record_counts
    end
  end

  test "explicit library replacement preserves existing jobs metadata and manually uploaded photos" do
    generate(count: 22)
    patron = create_patron(name: "Existing Example", email: "existing-template@example.org")
    model = PrintableModel.create!(name: "Existing library entry", code: "existing-template",
      category: ensure_category("Staff"), notes: "Keep the library notes.", weight_grams: 57)
    model.model_file.attach(io: StringIO.new(Development::DemoAssets.stl(scale: 0.5)),
      filename: "existing-file.stl", content_type: "model/stl")
    model.preview_image.attach(io: StringIO.new(Development::DemoAssets.png(color: "#b45309")),
      filename: "demo-preview-custom.png", content_type: "image/png")
    existing_job = create_print_job(patron: patron, attrs: { printable_model: model, notes: "Keep the existing job.",
      created_at: 1.month.ago, updated_at: 1.day.ago })
    existing_job.model_files.attach(model.model_file.blob)
    demo_job = owned_jobs.where(type: "PrintJob").order(:id).first
    demo_job.update!(notes: "Keep the edited demo job.", url: "https://example.org/edited-template-job")
    demo_job.update_columns(status_id: Status.find_by!(code: "ongoing").id, updated_at: 4.hours.ago)
    jobs_before = [existing_job, demo_job].map { |job| [job.reload.attributes, job.model_files.pluck(:id, :blob_id)] }
    model_before = model.attributes.slice("name", "code", "category_id", "notes", "weight_grams", "position")
    photo_id = model.preview_image.blob_id
    patron_before = patron.attributes

    with_template do |path, bytes|
      result = generate(count: 22, model_file: path, replace_library_files: true)
      assert_equal 0, result[:created_jobs]
      models = PrintableModel.with_attached_model_file.to_a
      assert_equal 1, models.map { |entry| entry.model_file.blob_id }.uniq.size
      assert_equal bytes, model.reload.model_file.download
    end

    assert_equal jobs_before, [existing_job, demo_job].map { |job| [job.reload.attributes, job.model_files.pluck(:id, :blob_id)] }
    assert_equal model_before, model.reload.attributes.slice(*model_before.keys)
    assert_equal photo_id, model.preview_image.blob_id
    assert_equal patron_before, patron.reload.attributes
    assert demo_models.with_attached_preview_image.none? { |entry| entry.preview_image.attached? }
  end

  test "invalid custom files and replacement without a file reject before creating data" do
    assert_no_changes -> { record_counts } do
      assert_raises(Development::DemoData::Error) { generate(count: 22, replace_library_files: true) }
      Tempfile.create(["demo-template", ".txt"]) do |file|
        file.write(Development::DemoAssets.stl)
        file.flush
        assert_raises(Development::DemoData::Error) { generate(count: 22, model_file: file.path) }
      end
      Tempfile.create(["demo-template", ".stl"]) do |file|
        file.write("too small")
        file.flush
        assert_raises(Development::DemoData::Error) { generate(count: 22, model_file: file.path) }
      end
    end
  end

  private

  def with_stub(object, name, replacement)
    singleton = object.singleton_class
    directly_defined = singleton.public_instance_methods(false).include?(name) ||
      singleton.protected_instance_methods(false).include?(name) || singleton.private_instance_methods(false).include?(name)
    original = object.method(name)
    visibility = if singleton.private_method_defined?(name)
      :private
    elsif singleton.protected_method_defined?(name)
      :protected
    else
      :public
    end
    singleton.define_method(name) do |*arguments, **keywords, &block|
      replacement.respond_to?(:call) ? replacement.call(*arguments, **keywords, &block) : replacement
    end
    yield
  ensure
    if directly_defined
      singleton.define_method(name, original)
      singleton.send(visibility, name)
    else
      singleton.remove_method(name)
    end
  end

  def generate(count:, **options)
    Development::DemoData.new(count: count, **options).call
  end

  def with_template
    bytes = Development::DemoAssets.stl(scale: 1.5)
    Tempfile.create(["demo-template", ".stl"]) do |file|
      file.binmode
      file.write(bytes)
      file.flush
      yield file.path, bytes
    end
  end

  def owned_jobs
    ids = Audited::Audit.where(auditable_type: "Job", action: "create")
      .where("comment LIKE ?", "#{Development::DemoData::PREFIX}job:%").select(:auditable_id)
    Job.where(id: ids)
  end

  def demo_models
    PrintableModel.where("code LIKE ?", "make_demo_%")
  end

  def record_counts
    [Job, Patron, StaffUser, PrintableModel, Printer, PickupLocation, Conversation,
      Message, Notification, ActiveStorage::Blob, ActiveStorage::Attachment].to_h { |model| [model.name, model.count] }
  end

  def editable_snapshot(job, model)
    [job.reload.attributes, job.model_files.order(:id).pluck(:id, :blob_id), model.reload.attributes,
      model.model_file.attachment.attributes, model.preview_image.attachment.attributes]
  end

  def database_configuration(overrides = {})
    ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary",
      { adapter: "postgresql", database: "make_at_tadl_test", host: nil }.merge(overrides))
  end

  def with_delivery_snapshot
    mailers = [ActionMailer::Base, ApplicationMailer, JobMailer, PatronMailer, MentionMailer]
    settings = mailers.to_h { |mailer| [mailer, [mailer.perform_deliveries, mailer.delivery_method]] }
    adapters = mailers.map(&:delivery_job).uniq.to_h { |job| [job, job.queue_adapter] }
    yield settings, adapters
  ensure
    settings&.each { |mailer, (deliver, method)| mailer.perform_deliveries = deliver; mailer.delivery_method = method }
    adapters&.each { |job, adapter| job.queue_adapter = adapter }
  end

  def assert_delivery_snapshot(settings, adapters)
    settings.each { |mailer, expected| assert_equal expected, [mailer.perform_deliveries, mailer.delivery_method] }
    adapters.each { |job, adapter| assert_same adapter, job.queue_adapter }
  end
end
