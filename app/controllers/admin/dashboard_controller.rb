module Admin
  class DashboardController < BaseController
    def show
      authorize! :read, :dashboard
      @page_title = "Overview"
      @dashboard = StaffDashboard.new(staff_user: current_staff_user)
      @scanning_available = PickupLocation.active.scanners.exists?
    end
  end
end
