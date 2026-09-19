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

  # HEADED=1 opens a real window instead, so you can watch a test drive the
  # app. Useful for the thing an assertion cannot check: whether the page
  # looked right while it happened.
  #
  #   HEADED=1 bin/rails test:system test/system/studying_test.rb
  #
  # SLOWMO=0.4 pauses after each Capybara action, since a headless-speed run is
  # hard to follow with the naked eye.
  driven_by :selenium, using: ENV["HEADED"].present? ? :chrome : :headless_chrome, screen_size: DESKTOP

  # Pauses after each action when SLOWMO is set. Capybara has no such setting,
  # so this wraps the session's own click and fill methods.
  if ENV["SLOWMO"].present?
    setup do
      delay = ENV["SLOWMO"].to_f
      session = Capybara.current_session
      %i[click_button click_link fill_in visit].each do |action|
        session.singleton_class.prepend(Module.new do
          define_method(action) do |*args, **kwargs, &block|
            super(*args, **kwargs, &block).tap { sleep delay }
          end
        end)
      end
    end
  end

  # Signs in through the form rather than through Warden's test helpers: the
  # session a real browser holds is the thing being exercised here.
  def sign_in_as(user, password: "password123")
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: password

    # Through the same helper as every other click: signing in is where a lost
    # click costs the most, because every later assertion then fails for a
    # reason that has nothing to do with what is being tested.
    click_and_confirm("Log in", expect: /Welcome back|Recent Decks|おかえり/i)

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

  # Clicks, then waits for the page to show it landed. Falls back to a
  # DOM-level click if the driver's click produced nothing.
  #
  # A driver click sometimes has no effect at all: no event reaches the button,
  # no overlay sits at the click point, no scroll is in progress, no console
  # error, Turbo loaded, and the identical click works moments later. I chased
  # it through element geometry, elementFromPoint, ActionChains, native clicks,
  # the service worker, animations and smooth scrolling without pinning it
  # down; it happens here often and on CI occasionally.
  #
  # A DOM click still goes through the app -- Turbo submits, the server
  # answers, the page re-renders -- it just does not depend on the driver
  # landing a pointer on a coordinate. Capybara has already established the
  # element is visible by finding it.
  def click_and_confirm(label, expect:, wait: 10)
    button = find_button(label, match: :first)
    button.click
    return if page.has_text?(expect, wait: 3)

    button.evaluate_script("this.click()")
    assert_text expect, wait: wait
  end

  # True when the page can be scrolled sideways -- which, on a phone, means
  # something is wider than the screen.
  def scrolls_horizontally?
    page.evaluate_script("document.documentElement.scrollWidth > document.documentElement.clientWidth + 1")
  end
end
