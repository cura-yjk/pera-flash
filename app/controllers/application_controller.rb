class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    # Permit :name on user registration (sign-up)
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name])

    # Permit :name when updating account details
    devise_parameter_sanitizer.permit(:account_update, keys: [:name])
  end

  private

  def after_sign_in_path_for(_resource)
    dashboard_path
  end
end
