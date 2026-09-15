class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?
  around_action :use_chosen_locale

  protected

  # A saved choice wins, then the browser's own languages, then English.
  #
  # around_action rather than before_action: I18n.locale is global to the
  # thread, so leaving it set would hand the next request whatever the last one
  # happened to use.
  def use_chosen_locale(&)
    I18n.with_locale(chosen_locale, &)
  end

  def chosen_locale
    current_user&.locale.presence || browser_locale || I18n.default_locale
  end

  # Accept-Language, matched against what the app actually has. Matching the
  # language alone ("zh" out of "zh-TW") means a Taiwanese browser gets
  # Chinese rather than English, which is closer to right than nothing.
  def browser_locale
    accepted = request.env["HTTP_ACCEPT_LANGUAGE"].to_s.scan(/[a-zA-Z]{2}(?:-[a-zA-Z]{2})?/)

    accepted.find { |tag| I18n.available_locales.map(&:to_s).include?(tag) } ||
      accepted.map { |tag| tag.split("-").first.downcase }
              .find { |lang| available_languages.key?(lang) }
              .then { |lang| available_languages[lang] }
  end

  # Language code to the locale this app has for it. First declared wins, so a
  # browser asking for plain "zh" gets Simplified rather than whichever variant
  # happens to sort last.
  def available_languages
    I18n.available_locales.reverse.to_h { |locale| [locale.to_s.split("-").first.downcase, locale.to_s] }
  end

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
