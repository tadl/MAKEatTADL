require "ipaddr"

module BrowserFixtureDatabaseGuard
  class Error < StandardError; end

  def self.verify!(environment: Rails.env.to_s, configuration: ActiveRecord::Base.connection_db_config,
    connection: -> { ActiveRecord::Base.connection }, models: nil)
    raise Error, "Browser fixtures require the test environment." unless environment.to_s == "test"

    settings = configuration.configuration_hash
    unless configuration.adapter == "postgresql" && configuration.database.to_s.match?(/(?:\A|_)test\z/) &&
        local_host?(settings[:host]) && local_host?(settings[:hostaddr])
      raise Error, "Browser fixtures require a local PostgreSQL test database."
    end

    database, address = connection.call.select_rows("SELECT current_database(), inet_server_addr()::text").first
    unless database == configuration.database && (address.nil? || loopback_address?(address))
      raise Error, "The connected database is not the expected local test database."
    end

    models ||= [Patron, StaffUser, Job, Conversation, Message, Notification, PrintableModel, Printer, Audited::Audit]
    models.each do |model|
      if model.exists?
        raise Error, "Refusing to export existing #{model.name} records. Use an empty test database."
      end
    end
    true
  end

  def self.local_host?(host)
    host.nil? || host == "" || host == "localhost" || host.to_s.start_with?("/") || loopback_address?(host)
  end
  private_class_method :local_host?

  def self.loopback_address?(address)
    IPAddr.new(address.to_s).loopback?
  rescue IPAddr::InvalidAddressError
    false
  end
  private_class_method :loopback_address?
end
