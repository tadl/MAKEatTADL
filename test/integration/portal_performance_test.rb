require "test_helper"

class PortalPerformanceTest < ActionDispatch::IntegrationTest
  setup do
    @patron = create_patron
    ensure_base_lookups!
    post consume_dashboard_token_path, params: { token: @patron.access_token }
    assert_redirected_to dashboard_path
  end

  test "dashboard queries stay bounded as jobs have different statuses printers and locations" do
    add_dashboard_job(0)
    get dashboard_path
    small_queries = capture_selects { get dashboard_path }

    9.times { |index| add_dashboard_job(index + 1) }
    other_job = create_print_job
    large_queries = capture_selects { get dashboard_path }

    assert_response :success
    assert_select "tbody tr", count: 10
    assert_select "a[href='#{job_path(other_job)}']", count: 0
    assert_select "td", text: "Location 9"
    assert_select "td", text: "Printer 9"
    assert_select ".badge", text: "Status 9"
    assert_operator small_queries.size, :>, 0
    assert_operator large_queries.size, :<=, small_queries.size
  end

  test "conversation queries stay bounded and staff notes remain private" do
    job = create_print_job(patron: @patron)
    job.conversation.messages.create!(author: @patron, body: "First public reply")
    get job_path(job)
    small_queries = capture_selects { get job_path(job) }

    9.times do |index|
      job.conversation.messages.create!(author: create_patron, body: "Public reply #{index}")
    end
    job.conversation.messages.create!(author: create_staff_user,
      body: "Private staff discussion", staff_note_only: true)
    large_queries = capture_selects { get job_path(job) }

    assert_response :success
    assert_select ".message", count: 10
    assert_includes response.body, "Public reply 8"
    assert_not_includes response.body, "Private staff discussion"
    assert_operator small_queries.size, :>, 0
    assert_operator large_queries.size, :<=, small_queries.size
  end

  test "conversation renders image URLs without processing thumbnails in the page request" do
    job = create_print_job(patron: @patron)
    message = job.conversation.messages.create!(author: @patron, body: "Photo attachment")
    png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6N8AAAAASUVORK5CYII=")
    message.images.attach(io: StringIO.new(png), filename: "test.png", content_type: "image/png")
    transformations = []

    ActiveSupport::Notifications.subscribed(
      ->(*event) { transformations << event.last }, "transform.active_storage"
    ) do
      assert_no_difference "ActiveStorage::VariantRecord.count" do
        get job_path(job)
      end
    end

    assert_response :success
    assert_empty transformations
    assert_select ".message-images img[src*='/representations/redirect/']", count: 1
  end

  private

  def add_dashboard_job(index)
    location = ensure_pickup_location(code: "location_#{index}", name: "Location #{index}")
    status = ensure_status("status_#{index}", name: "Status #{index}")
    printer = Printer.create!(name: "Printer #{index}", printer_model: "Printer #{index}",
      pickup_location: location)
    job = create_print_job(patron: @patron, status_code: status.code,
      attrs: { pickup_location: location.code })
    # Assign without advancing the synthetic status through printer callbacks.
    job.update_column(:assigned_printer_id, printer.id)
  end
end
