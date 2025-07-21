# config/initializers/omniauth.rb

# allow both GET and POST
OmniAuth.config.allowed_request_methods = [:post, :get]

if Rails.env.production?
  # build the callback URL from X-Forwarded headers
  OmniAuth.config.full_host = lambda do |env|
    scheme = env['HTTP_X_FORWARDED_PROTO'] || env['rack.url_scheme']
    host   = env['HTTP_X_FORWARDED_HOST'] || env['HTTP_HOST']
    "#{scheme}://#{host}"
  end
end

if ENV['GOOGLE_CLIENT_ID'].present? && ENV['GOOGLE_CLIENT_SECRET'].present?
  Rails.application.config.middleware.use OmniAuth::Builder do
    provider :google_oauth2,
      ENV['GOOGLE_CLIENT_ID'],
      ENV['GOOGLE_CLIENT_SECRET'],
      {
        hd:     ENV['GOOGLE_DOMAIN'],   # optional
        scope:  'email,profile',
        prompt: 'select_account'
        # you can also hard-code the callback_url if you prefer:
        # callback_url: "#{ENV['APP_PROTOCOL']}://#{ENV['APP_HOST']}/auth/google_oauth2/callback"
      }
  end
else
  Rails.logger.warn 'OmniAuth Google credentials not set; skipping Google OAuth2 middleware.'
end
