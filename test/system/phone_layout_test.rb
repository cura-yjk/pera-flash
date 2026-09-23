require "application_system_test_case"

# The layout at phone width.
#
# The stylesheet had no media queries at all and was built from fixed pixel
# widths -- a 700px chat input, a 700px sign-in field, a 640px illustration
# with a negative margin -- so every screen scrolled sideways on a phone. None
# of that is visible to a test that reads HTML: it only shows up once something
# lays the page out at a real width.
class PhoneLayoutTest < ApplicationSystemTestCase
  setup { resize_to(*PHONE) }
  teardown { resize_to(*DESKTOP) }

  test "the sign-in page fits" do
    visit new_user_session_path

    assert_no_horizontal_scroll "sign in"
  end

  test "the landing page fits" do
    visit root_path

    assert_no_horizontal_scroll "landing"
  end

  test "the signed-in pages fit" do
    user = users(:learner)
    deck = decks(:starter)
    4.times { |i| deck.flashcards.create!(question: "Question #{i}?", answer: "答[こた]え #{i}", due_at: 1.hour.ago) }
    sign_in_as(user)

    {
      "dashboard" => dashboard_path,
      "decks" => decks_path,
      "flashcards" => flashcards_path,
      "chat history" => conversations_path,
      "review" => review_path,
      "quiz" => deck_quiz_path(deck),
      "chat" => conversation_path(conversations(:lesson))
    }.each do |name, path|
      visit path
      assert_no_horizontal_scroll name
    end
  end

  # Pera's grammar tables are the widest thing in the app. They scroll inside
  # the message; the page must not scroll with them.
  test "a wide table in a reply does not widen the page" do
    user = users(:learner)
    sign_in_as(user)
    conversations(:lesson).messages.create!(
      role: "assistant",
      content: "| Japanese | Reading | Meaning | Note |\n|---|---|---|---|\n" \
               "| 食[た]べ物[もの] | たべもの | food, something to eat | a compound |\n"
    )

    visit conversation_path(conversations(:lesson))

    assert_selector "table"
    assert_no_horizontal_scroll "a chat with a table"
  end

  # The two panels on the signed-in home page wrap so they can stack on a
  # phone -- but a flex item asking for the full width of a wrapping container
  # takes a row to itself at every size, so they stacked on a desktop too.
  test "the home page panels sit side by side when there is room" do
    sign_in_as(users(:learner))

    resize_to(*DESKTOP)
    visit root_path

    assert_equal "side by side", panel_arrangement
  end

  test "the home page panels stack on a phone" do
    sign_in_as(users(:learner))

    resize_to(*PHONE)
    visit root_path

    assert_equal "stacked", panel_arrangement
  end

  # The account menu is the only way to reach decks, chat history, flashcards,
  # the furigana toggle and logging out, and nothing else in the suite opens it
  # at phone width.
  #
  # Taking the navbar's collapse away left the menu subject to a Bootstrap rule
  # written for one: below the expand breakpoint .navbar-nav .dropdown-menu is
  # position: static, which is right inside a collapse panel -- opening it
  # should push the panel open. In the bar itself it put a ~340px block in the
  # flow of the row, so the avatar wrapped onto a second line and the menu
  # shoved the page down beneath it.
  test "opening the account menu does not rearrange the navbar" do
    sign_in_as(users(:learner))
    visit dashboard_path
    settled = avatar_top

    open_account_menu

    assert_equal settled, avatar_top,
                 "the avatar moved when the menu opened, so the bar rewrapped"
    assert_no_horizontal_scroll "the dashboard with the account menu open"
  end

  private

  # Through a DOM click if the pointer one does not land: the bar is
  # fixed-top, and a driver click at those coordinates is the flakiest part of
  # this file -- see click_and_confirm, which does the same.
  def open_account_menu
    toggle = find(".nav-link.dropdown-toggle")
    toggle.click
    return if has_selector?(".dropdown-menu.show", wait: 2)

    toggle.evaluate_script("this.click()")
    assert_selector ".dropdown-menu.show", wait: 5
  end

  def avatar_top
    page.evaluate_script(
      "Math.round(document.querySelector('.nav-link.dropdown-toggle')" \
      ".getBoundingClientRect().top)"
    )
  end

  def panel_arrangement
    page.evaluate_script(<<~JS)
      (function () {
        const left = document.querySelector(".left-side");
        const right = document.querySelector(".right-side");
        if (!left || !right) return "missing";

        const l = left.getBoundingClientRect(), r = right.getBoundingClientRect();
        return Math.abs(l.top - r.top) < 5 ? "side by side" : "stacked";
      })()
    JS
  end

  def assert_no_horizontal_scroll(page_name)
    assert_not scrolls_horizontally?,
               "#{page_name} scrolls sideways at #{PHONE.first}px: " \
               "#{page.evaluate_script('document.documentElement.scrollWidth')}px wide"
  end
end
