require "test_helper"

class LocaleTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:learner) }

  test "the dashboard renders in every language the app offers" do
    I18n.available_locales.each do |locale|
      users(:learner).update!(locale: locale)

      get dashboard_path

      assert_response :success, "#{locale} failed to render"
      assert_no_match(/translation missing/, response.body, "#{locale} has a missing translation")
      assert_match I18n.t("users.dashboard.recent_decks", locale: locale), response.body
    end
  end

  test "a saved choice wins over the browser's languages" do
    users(:learner).update!(locale: "de")

    get dashboard_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "ja,en;q=0.9" }

    assert_match "Willkommen zurück", response.body
  end

  # Someone whose browser is in Korean should get Korean without being asked.
  test "the browser's language is used before anyone chooses" do
    users(:learner).update!(locale: nil)

    get dashboard_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "ko-KR,ko;q=0.9,en;q=0.8" }

    assert_match I18n.t("users.dashboard.recent_decks", locale: :ko), response.body
  end

  test "a Taiwanese browser gets Traditional, not Simplified" do
    users(:learner).update!(locale: nil)

    get dashboard_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "zh-TW,zh;q=0.9" }

    assert_match I18n.t("users.dashboard.recent_decks", locale: :"zh-TW"), response.body
  end

  # A browser asking for plain "zh" has not said which script. Simplified has
  # more readers, and is the first Chinese locale the app declares.
  test "plain Chinese resolves to Simplified" do
    users(:learner).update!(locale: nil)

    get dashboard_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "zh" }

    assert_match I18n.t("users.dashboard.recent_decks", locale: :"zh-CN"), response.body
  end

  # A regional variant the app does not have still matches its language.
  test "an unlisted regional variant falls back to the language" do
    users(:learner).update!(locale: nil)

    get dashboard_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "de-AT,de;q=0.9" }

    assert_match I18n.t("users.dashboard.recent_decks", locale: :de), response.body
  end

  test "an unknown language falls back to English" do
    users(:learner).update!(locale: nil)

    get dashboard_path, headers: { "HTTP_ACCEPT_LANGUAGE" => "sv-SE,sv;q=0.9" }

    assert_match "Recent Decks", response.body
  end

  test "choosing a language saves it" do
    patch language_path, params: { locale: "ja" }

    assert_equal "ja", users(:learner).reload.locale
  end

  # The list is an allowlist: anything else would set I18n.locale to a value
  # with no translations behind it.
  test "a locale the app does not have is refused" do
    users(:learner).update!(locale: "de")

    patch language_path, params: { locale: "../../etc/passwd" }

    assert_equal "de", users(:learner).reload.locale
  end

  # I18n.locale is global to the thread, so a request that sets it must not
  # leave it set for whatever runs next.
  test "the locale does not leak into the next request" do
    users(:learner).update!(locale: "ja")
    get dashboard_path

    assert_equal :en, I18n.locale
  end
end
