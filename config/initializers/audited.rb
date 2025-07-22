# config/initializers/audited.rb
# point Audited at your StaffUser helper
Audited.current_user_method = :current_staff_user
