ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module TestSupport
  module EnvHelper
    def with_env(overrides)
      original = overrides.to_h { |key, _value| [key, ENV[key]] }

      overrides.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end

      yield
    ensure
      original.each do |key, value|
        value.nil? ? ENV.delete(key) : ENV[key] = value
      end
    end
  end

  module DataHelper
    def ensure_status(code, name: code.to_s.humanize, position: nil)
      Status.find_or_create_by!(code: code) do |status|
        status.name = name
        status.position = position || Status.count
      end
    end

    def ensure_category(name, position: nil)
      Category.find_or_create_by!(name: name) do |category|
        category.position = position || Category.count
      end
    end

    def ensure_print_type(code, name: code.to_s.upcase, position: nil)
      PrintType.find_or_create_by!(code: code) do |print_type|
        print_type.name = name
        print_type.position = position || PrintType.count
      end
    end

    def ensure_pickup_location(code: "wood", name: "Woodmere")
      PickupLocation.find_or_create_by!(code: code) do |location|
        location.name = name
        location.position = PickupLocation.count
        location.active = true
        location.scanner = true
        location.fdm_printer = true
        location.resin_printer = true
      end
    end

    def ensure_base_lookups!
      ensure_status("pending", name: "Pending", position: 0)
      ensure_status("information_requested", name: "Information Requested", position: 1)
      ensure_status("response_received", name: "Response Received", position: 2)
      ensure_status("approved", name: "Approved", position: 3)
      ensure_status("in_progress", name: "In Progress", position: 4)
      ensure_status("ready_for_pickup", name: "Ready for Pickup", position: 5)
      ensure_status("archived", name: "Archived", position: 6)
      ensure_status("ongoing", name: "Ongoing", position: 7)
      ensure_status("cancelled", name: "Cancelled", position: 8)
      ensure_status("rejected", name: "Rejected", position: 9)
      ensure_status("abandoned", name: "Abandoned", position: 10)

      ensure_category("Patron", position: 1)
      ensure_category("Staff", position: 2)
      ensure_category("Assistive", position: 3)
      ensure_category("Fidget", position: 4)

      ensure_print_type("fdm", name: "FDM", position: 1)
      ensure_print_type("resin", name: "Resin", position: 2)
      ensure_pickup_location
    end

    def create_patron(email: unique_email("patron"), name: "Test Patron")
      Patron.create!(email: email, name: name)
    end

    def create_staff_user(email: unique_email("staff"), name: "Test Staff", admin: false)
      StaffUser.create!(
        email: email,
        name: name,
        uid: SecureRandom.hex(8),
        admin: admin
      )
    end

    def create_print_job(patron: create_patron, status_code: "pending", category_name: "Patron", attrs: {})
      ensure_base_lookups!

      PrintJob.create!(
        {
          patron: patron,
          status: Status.find_by!(code: status_code),
          category: Category.find_by!(name: category_name),
          pickup_location: ensure_pickup_location.code,
          url: "https://example.com/model"
        }.merge(attrs)
      )
    end

    def create_scan_job(patron: create_patron, status_code: "pending", attrs: {})
      ensure_base_lookups!

      ScanJob.create!(
        {
          patron: patron,
          status: Status.find_by!(code: status_code),
          category: Category.find_by!(name: "Patron"),
          pickup_location: ensure_pickup_location.code,
          spray_ok: true,
          notes: "Scan this object"
        }.merge(attrs)
      )
    end

    def unique_email(prefix)
      "#{prefix}-#{SecureRandom.hex(4)}@example.org"
    end

    def model_upload(filename: "test-model.stl", content_type: "model/stl")
      fixture_file_upload(filename, content_type)
    end
  end
end

class ActiveSupport::TestCase
  parallelize(workers: 1)

  include ActiveJob::TestHelper
  include ActionDispatch::TestProcess::FixtureFile
  include TestSupport::EnvHelper
  include TestSupport::DataHelper

  setup do
    Rails.cache.clear
    clear_enqueued_jobs
    clear_performed_jobs
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    Rails.cache.clear
  end
end

class ActionDispatch::IntegrationTest
  include ActionDispatch::TestProcess::FixtureFile
  include ActiveJob::TestHelper
  include TestSupport::EnvHelper
  include TestSupport::DataHelper

  setup do
    Rails.cache.clear
    clear_enqueued_jobs
    clear_performed_jobs
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    Rails.cache.clear
  end
end

Rails.application.routes.default_url_options[:host] = "example.test"
ActionMailer::Base.default_url_options = { host: "example.test" }
