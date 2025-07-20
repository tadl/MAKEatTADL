# config/initializers/omniauth.rb

# Always allow both GET and POST for callbacks
OmniAuth.config.allowed_request_methods = [:post, :get]

# Only mount the Google OAuth2 middleware if credentials are present
if ENV['GOOGLE_CLIENT_ID'].present? && ENV['GOOGLE_CLIENT_SECRET'].present?
  Rails.application.config.middleware.use OmniAuth::Builder do
    provider :google_oauth2,
      ENV['GOOGLE_CLIENT_ID'],
      ENV['GOOGLE_CLIENT_SECRET'],
      {
        hd:     ENV['GOOGLE_DOMAIN'],   # optional, can be nil
        scope:  'email,profile',
        prompt: 'select_account'
      }
  end
else
  Rails.logger.warn 'OmniAuth Google credentials not set; skipping Google OAuth2 middleware.'
end
