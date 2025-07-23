# config/initializers/remote_addr_override.rb
# Make audited (and anything else calling remote_addr) pick up the true client IP.
module ActionDispatch
  class Request
    # override the default, which just returns REMOTE_ADDR
    def remote_addr
      remote_ip
    end
  end
end
