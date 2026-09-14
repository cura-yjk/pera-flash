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
    assert_not_requested :post, /api\.openai\.com/
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
    assert_not_requested :post, /api\.openai\.com/
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

  test "says so when nothing is due" do
    Flashcard.for_user(users(:learner)).find_each { |c| c.update!(due_at: 3.days.from_now, review_count: 1) }

    get review_path

    assert_response :success
    assert_match(/nothing due/i, response.body)
  end
end
