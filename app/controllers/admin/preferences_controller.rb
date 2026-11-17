module Admin
  class PreferencesController < BaseController
    def update
      # Staff may change their own appearance without general StaffUser edit access.
      if current_staff_user.update(preference_params)
        respond_to do |format|
          format.json { render json: current_staff_user.slice(:theme, :ui_density) }
          format.html do
            redirect_back_or_to admin_root_path, allow_other_host: false,
              notice: "Appearance updated.", status: :see_other
          end
          format.any { head :not_acceptable }
        end
      else
        respond_to do |format|
          format.json { render json: { errors: current_staff_user.errors.full_messages }, status: :unprocessable_content }
          format.html { render plain: current_staff_user.errors.full_messages.join(". "), status: :unprocessable_content }
          format.any { head :not_acceptable }
        end
      end
    end

    private

    def preference_params
      params.expect(preferences: %i[theme ui_density])
    end
  end
end
