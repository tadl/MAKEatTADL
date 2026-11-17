require "minitest/autorun"
require "open3"
require "rbconfig"
require_relative "../browser/support/fixture_database_guard"

class BrowserFixtureDatabaseGuardTest < Minitest::Test
  Configuration = Struct.new(:adapter, :database, :configuration_hash, keyword_init: true)
  Model = Struct.new(:name, :rows, keyword_init: true) do
    def exists?
      rows.positive?
    end
  end

  def test_metadata_rejects_unsafe_targets_before_opening_a_connection
    cases = [
      { environment: "production" },
      { adapter: "sqlite3" },
      { database: "make_at_tadl_production" },
      { settings: { host: "db.example.org" } },
      { settings: { host: "203.0.113.15" } },
      { settings: { host: "localhost", hostaddr: "203.0.113.16" } }
    ]
    cases.each do |overrides|
      assert_raises(BrowserFixtureDatabaseGuard::Error) do
        verify(**overrides, connection: -> { flunk "Unsafe fixture target opened a connection" })
      end
    end
  end

  def test_local_socket_and_loopback_targets_accept_empty_operational_tables
    [nil, "", "localhost", "127.0.0.1", "::1", "/var/run/postgresql"].each do |host|
      assert verify(settings: { host: host }, models: [Model.new(name: "Job", rows: 0)])
    end
    assert verify(settings: { host: "localhost", hostaddr: "127.0.0.1" }, address: "127.0.0.1")
    assert verify(settings: { host: "::1" }, address: "::1")
  end

  def test_actual_database_and_server_address_must_match_the_safe_configuration
    [
      { connected_database: "make_at_tadl_production" },
      { address: "203.0.113.17" },
      { address: "not-an-address" }
    ].each do |overrides|
      assert_raises(BrowserFixtureDatabaseGuard::Error) { verify(**overrides) }
    end
  end

  def test_existing_operational_or_audit_records_are_never_exported
    %w[Patron StaffUser Job Conversation Message Notification PrintableModel Printer Audited::Audit].each do |name|
      error = assert_raises(BrowserFixtureDatabaseGuard::Error) do
        verify(models: [Model.new(name: name, rows: 1)])
      end
      assert_includes error.message, "Refusing to export existing #{name} records"
    end
  end

  def test_both_renderer_entry_points_reject_production_before_application_boot
    %w[render_admin_pages.rb render_stats_pages.rb].each do |filename|
      path = File.expand_path("../browser/#{filename}", __dir__)
      _stdout, stderr, status = Open3.capture3({ "RAILS_ENV" => "production" }, RbConfig.ruby, path)
      refute status.success?
      assert_match(/must run in the test environment/, stderr)
      refute_match(/config\/environment|ActiveRecord|ActiveSupport/, stderr)
    end
  end

  private

  def verify(environment: "test", adapter: "postgresql", database: "make_at_tadl_test", settings: {},
    connected_database: database, address: nil, connection: nil, models: [])
    connection ||= lambda do
      Object.new.tap do |object|
        object.define_singleton_method(:select_rows) { |_query| [[connected_database, address]] }
      end
    end
    BrowserFixtureDatabaseGuard.verify!(environment: environment,
      configuration: Configuration.new(adapter: adapter, database: database, configuration_hash: settings),
      connection: connection, models: models)
  end
end
