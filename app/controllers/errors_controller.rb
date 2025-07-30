class ErrorsController < ApplicationController
  def not_found
    respond_to do |format|
      format.html { render status: :not_found }
      format.xml  { render status: :not_found }
      format.json { render status: :not_found }
      format.all  { render plain: "404 Not Found", status: :not_found }
    end
  end

  def internal_server_error
    respond_to do |format|
      format.html { render status: :internal_server_error }
      format.xml  { render status: :internal_server_error }
      format.json { render status: :internal_server_error }
      format.all  { render plain: "500 Internal Server Error", status: :internal_server_error }
    end
  end

  def forbidden
    respond_to do |format|
      format.html { render status: :forbidden }
      format.xml  { render status: :forbidden }
      format.json { render status: :forbidden }
      format.all  { render plain: "403 Forbidden", status: :forbidden }
    end
  end
end
