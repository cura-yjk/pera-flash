require "test_helper"

# Browser-level tests. They exist because the bugs this app has actually
# shipped were all invisible to the rest of the suite: a quiz that graded every
# tap while the page never moved (an integration test read the response body
# and saw the next question, which Turbo was discarding), and an apostrophe
# escaped twice on its way to the screen.
#
# Kept to the flows that broke, plus a phone-width check -- the layout was
# built from fixed pixel widths and there is no other way to catch that.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  DESKTOP = [ 1400, 1000 ].freeze
  PHONE = [ 390, 844 ].freeze

  # CI runners ship Chrome on the PATH. A developer machine often does not, but
  # Selenium Manager will have cached a Chrome for Testing build -- point at
  # that rather than making everyone install a browser system-wide.
  cached = Dir[File.expand_path("~/.cache/selenium/chrome/*/*/chrome")].max
  Selenium::WebDriver::Chrome.path = cached if cached && !system("which google-chrome chromium >/dev/null 2>&1")

  driven_by :selenium, using: :headless_chrome, screen_size: DESKTOP

  # Signs in through the form rather than through Warden's test helpers: the
  # session a real browser holds is the thing being exercised here.
  def sign_in_as(user, password: "password123")
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: password
    click_on "Log in"

    assert_current_path dashboard_path, wait: 5
  end

  # Resizes the live browser rather than calling driven_by again in a subclass.
  # A second driven_by re-registers the same :selenium driver for the whole
  # run, so a phone-sized class silently shrank every other class's window --
  # which is how a click on the review page started landing on the heading
  # instead of the button next to it.
  def resize_to(width, height)
    page.driver.browser.manage.window.resize_to(width, height)
  end

  # True when the page can be scrolled sideways -- which, on a phone, means
  # something is wider than the screen.
  def scrolls_horizontally?
    page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth + 1")
  end
end
