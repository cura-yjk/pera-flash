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

  private

  def assert_no_horizontal_scroll(page_name)
    assert_not scrolls_horizontally?,
               "#{page_name} scrolls sideways at #{PHONE.first}px: " \
               "#{page.evaluate_script('document.documentElement.scrollWidth')}px wide"
  end
end
