module Admin
  class HelpController < BaseController
    def show
      authorize! :read, :dashboard
      @page_title = "Workflow guide"
      @statuses = Status.reorder(:position, :id)
    end
  end
end
