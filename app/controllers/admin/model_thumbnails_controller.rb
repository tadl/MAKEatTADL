module Admin
  class ModelThumbnailsController < BaseController
    def show
      model = PrintableModel.with_attached_model_file.find(params[:id])
      authorize! :read, model
      svg = model.model_file.attached? ? ModelThumbnail.new(model.model_file.blob).svg : ModelThumbnail.placeholder
      response.headers["X-Content-Type-Options"] = "nosniff"
      response.headers["Content-Security-Policy"] = "default-src 'none'; sandbox"
      render body: svg, content_type: "image/svg+xml", layout: false
    end
  end
end
