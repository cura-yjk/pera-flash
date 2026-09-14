require "test_helper"

class QuizzesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:learner)
    @deck = decks(:starter)
    @cards = 6.times.map { |i| @deck.flashcards.create!(question: "Q#{i}", answer: "A#{i}") }
  end

  test "requires authentication" do
    sign_out users(:learner)
    get quiz_path

    assert_redirected_to new_user_session_path
  end

  # The point of building quizzes on existing cards: they cost nothing.
  test "a quiz makes no LLM call" do
    get quiz_path

    assert_response :success
    assert_not_requested :post, /api\.openai\.com/
  end

  test "asks a question with several options" do
    get deck_quiz_path(@deck)

    assert_response :success
    assert_match(/Question 1 of/, response.body)
    assert_operator response.body.scan(/name="choice"/).size, :>=, 2
  end

  # Wrong answers feeding the schedule is what makes this one system with
  # review rather than two features sharing a table.
  test "a wrong answer sends the card back into today's queue" do
    card = only_due_card(review_count: 3, interval_days: 10, ease: 2.5)

    get deck_quiz_path(@deck)
    post deck_quiz_answer_path(@deck), params: { choice: "definitely not the answer" }

    card.reload
    assert_in_delta 0.0, card.interval_days, 0.001
    assert_equal 1, card.lapse_count
    assert_operator card.ease, :<, 2.5
  end

  test "a correct answer schedules the card forward" do
    card = only_due_card(review_count: 0, interval_days: 0)

    get deck_quiz_path(@deck)
    post deck_quiz_answer_path(@deck), params: { choice: card.answer }

    card.reload
    assert_operator card.interval_days, :>, 0
    assert_equal 0, card.lapse_count
  end

  # Regression: #answer has no template of its own, so without an explicit
  # render Rails replies 204 and the quiz stops dead after one question.
  test "answering returns the next question" do
    get deck_quiz_path(@deck)

    post deck_quiz_answer_path(@deck), params: { choice: "wrong" }

    assert_response :success
    assert_match(/Question 2 of/, response.body)
  end

  test "walking the whole quiz ends on a score" do
    get deck_quiz_path(@deck)

    10.times do
      post deck_quiz_answer_path(@deck), params: { choice: "wrong" }
      break if response.body.include?("Quiz again")
    end

    assert_match(/of \d+/, response.body)
    assert_match(/come back today/i, response.body)
  end

  # A multiple-choice question needs something to choose between.
  test "says so when there are too few cards to build a choice" do
    lonely = current_user_deck_with_one_card

    get deck_quiz_path(lonely)

    assert_response :success
    assert_match(/not enough cards/i, response.body)
  end

  test "refuses another user's deck" do
    theirs = Deck.create!(user: users(:other), name: "Theirs")

    get deck_quiz_path(theirs)

    assert_response :not_found
  end

  private

  # The quiz asks due cards in schedule order, so pin exactly one as due to
  # know which card an answer is being graded against.
  def only_due_card(**attrs)
    Flashcard.for_user(users(:learner)).update_all(due_at: 1.year.from_now, review_count: 1)
    # reload first: update_all changed the rows behind these objects, so an
    # attribute that matches the stale in-memory value would not be written.
    card = @cards.first.reload
    card.update!(attrs.merge(due_at: Time.current))
    card
  end

  # A deck whose only card is also the learner's only card, so no distractors
  # can be borrowed from elsewhere.
  def current_user_deck_with_one_card
    Flashcard.for_user(users(:learner)).destroy_all
    deck = Deck.create!(user: users(:learner), name: "Lonely")
    deck.flashcards.create!(question: "only", answer: "one")
    deck
  end
end
