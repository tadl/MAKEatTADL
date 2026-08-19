# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :staff_user, :synchronous_mail_delivery
end
