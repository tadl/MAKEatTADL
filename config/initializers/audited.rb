# config/initializers/audited.rb

# Tell Audited how to find the “current user” for its `user` association
Audited.current_user_method = :current_staff_user

# Skip any attributes that can’t be safely YAML-dumped
Audited.config do |config|
  config.ignored_attributes += ['token_sent_at']
end
