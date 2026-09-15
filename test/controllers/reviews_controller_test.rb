require "test_helper"

class ReviewsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:learner) }

  test "requires authentication" do
    sign_out users(:learner)
    get review_path

    assert_redirected_to new_user_session_path
  end

  # The whole point of the flow: studying never calls the LLM, so it works
  # with no credits and while a provider is down.
  test "a review session makes no LLM call" do
    get review_path

    assert_response :success
    assert_not_requested :post, llm_url
  end

  # Same rule the quiz follows: the prompt drops its readings once the schedule
  # trusts the card, while the answer keeps them.
  test "a mastered card is asked without its readings" do
    Flashcard.for_user(users(:learner)).update_all(due_at: 1.day.from_now)
    flashcards(:neko_card).update!(question: "猫[ねこ]は?", answer: "猫[ねこ] = cat",
                                   due_at: 1.hour.ago, interval_days: 30, lapse_count: 0, review_count: 9)

    get review_path

    assert_match "猫は?", response.body
    assert_match(/<ruby>猫<rt>ねこ<\/rt><\/ruby>/, response.body)  # the answer still carries it
  end

  test "a card still being learned keeps its readings in the question" do
    Flashcard.for_user(users(:learner)).update_all(due_at: 1.day.from_now)
    flashcards(:neko_card).update!(question: "猫[ねこ]は?", answer: "cat",
                                   due_at: 1.hour.ago, interval_days: 1, lapse_count: 0, review_count: 1)

    get review_path

    assert_no_match(/猫は\?/, response.body)
    assert_match(/<ruby>猫<rt>ねこ<\/rt><\/ruby>/, response.body)
  end

  # The heading named the scope and never said what the page was, so a global
  # review was titled "All decks".
  test "the heading says what the page is" do
    get review_path

    assert_select "h2", text: /Review/
  end

  test "a deck review names the deck alongside it" do
    deck = decks(:starter)
    deck.flashcards.create!(question: "Q", answer: "A", due_at: 1.hour.ago)

    get deck_review_path(deck)

    assert_select "h2", text: /Review.*#{deck.name}/
  end

  # Rendered twice-escaped, an apostrophe in a card reached the screen as
  # &#39; -- worst with readings switched off, which is exactly when a learner
  # is reading the card most carefully.
  test "an apostrophe in a card is not double escaped" do
    Flashcard.for_user(users(:learner)).update_all(due_at: 1.day.from_now)
    flashcards(:neko_card).update!(question: "What does it mean? It's tricky.", due_at: 1.hour.ago)

    get review_path

    assert_no_match(/&amp;#39;/, response.body)
    assert_match(/It&#39;s tricky/, response.body)
  end

  test "shows a due card" do
    get review_path

    assert_response :success
    assert_select "#review-card"
    assert_match flashcards(:neko_card).question, response.body
  end

  test "the answer is not revealed with the question" do
    get review_path

    # Present in the markup but hidden -- revealing early defeats the recall.
    assert_select "[data-reveal-target=answer][hidden]"
  end

  test "grading a card schedules it and makes no LLM call" do
    card = flashcards(:neko_card)

    patch review_card_path(card), params: { grade: "good" }, as: :turbo_stream

    assert_response :success
    card.reload
    assert_equal 1, card.review_count
    assert card.due_at.present?
    assert_not_requested :post, llm_url
  end

  test "a forgotten card stays in the queue" do
    card = flashcards(:neko_card)

    patch review_card_path(card), params: { grade: "again" }, as: :turbo_stream

    assert_includes Flashcard.for_user(users(:learner)).due, card.reload
  end

  test "an unknown grade is refused" do
    patch review_card_path(flashcards(:neko_card)), params: { grade: "brilliant" }, as: :turbo_stream

    assert_response :unprocessable_entity
  end

  test "refuses another user's card" do
    theirs = conversations(:other_users_lesson).flashcards.create!(question: "Q", answer: "A")

    patch review_card_path(theirs), params: { grade: "good" }, as: :turbo_stream

    assert_response :not_found
  end

  test "a deck session only offers that deck's cards" do
    deck = decks(:starter)
    mine = deck.flashcards.create!(question: "in deck", answer: "A")
    conversations(:lesson).flashcards.create!(question: "not in deck", answer: "A")

    get deck_review_path(deck)

    assert_response :success
    assert_match mine.question, response.body
    assert_no_match(/not in deck/, response.body)
  end

  # --- furigana -------------------------------------------------------------

  test "renders readings as ruby when they are on" do
    flashcards(:neko_card).update!(question: "猫[ねこ]が好[す]きですか？")

    get review_path

    assert_match "<ruby>猫<rt>ねこ</rt></ruby>", response.body
  end

  test "strips readings when the learner has turned them off" do
    users(:learner).update!(show_furigana: false)
    flashcards(:neko_card).update!(question: "猫[ねこ]が好[す]きですか？")

    get review_path

    assert_no_match(/<ruby>/, response.body)
    assert_match "猫が好きですか？", response.body
  end

  test "toggling the preference flips it and comes back" do
    assert users(:learner).show_furigana

    patch toggle_furigana_path, headers: { "HTTP_REFERER" => review_path }

    assert_redirected_to review_path
    assert_not users(:learner).reload.show_furigana
  end

  test "says so when nothing is due" do
    Flashcard.for_user(users(:learner)).find_each { |c| c.update!(due_at: 3.days.from_now, review_count: 1) }

    get review_path

    assert_response :success
    assert_match(/nothing due/i, response.body)
  end

  private

  # Follows LlmChat, so switching provider cannot silently leave these stubs
  # pointing at an endpoint nothing calls.
  def llm_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end
end
