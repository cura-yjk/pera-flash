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
    assert_not_requested :post, llm_url
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

  # Picking the answer out of four is recognition, and recall is harder: a
  # card can be passed by ruling out the other three. So a right answer here
  # leaves the card exactly where it was, and only recalling it in review
  # moves it further out.
  test "a correct answer leaves the card's schedule to review" do
    card = only_due_card(review_count: 3, interval_days: 10, ease: 2.5)
    before = card.reload.attributes.slice("interval_days", "ease", "due_at", "review_count", "lapse_count")

    get deck_quiz_path(@deck)
    post deck_quiz_answer_path(@deck), params: { choice: card.answer }

    assert_equal before, card.reload.attributes.slice(*before.keys)
  end

  test "a correct answer still counts toward the score" do
    card = only_due_card
    get deck_quiz_path(@deck)
    post deck_quiz_answer_path(@deck), params: { choice: card.answer }

    session[:quiz]["card_ids"].size.pred.times do
      follow_redirect!
      post deck_quiz_answer_path(@deck), params: { choice: "not it" }
    end
    follow_redirect!

    assert_match(/1 of/, response.body)
  end

  # Regression, twice over. #answer has no template of its own, so it first
  # replied 204 and the quiz stopped dead after one question. Rendering :show
  # fixed that for this test but not for a browser: Turbo submits the option
  # buttons as a form and ignores a 200 HTML response to one, so every tap
  # graded a card while the page sat still. Only a redirect drives the page
  # forward -- assert that, not just the body, or the browser bug hides here
  # again.
  test "answering redirects to the next question" do
    get deck_quiz_path(@deck)

    post deck_quiz_answer_path(@deck), params: { choice: "wrong" }

    assert_redirected_to deck_quiz_path(@deck)
    follow_redirect!
    assert_match(/Question 2 of/, response.body)
  end

  test "walking the whole quiz ends on a score" do
    get deck_quiz_path(@deck)

    10.times do
      post deck_quiz_answer_path(@deck), params: { choice: "wrong" }
      follow_redirect!
      break if response.body.include?("Quiz again")
    end

    assert_match(/of \d+/, response.body)
    assert_match(/come back today/i, response.body)
  end

  test "a mastered card is asked without its readings" do
    only_due_card(review_count: 9, interval_days: 30, ease: 2.5)
       .update!(question: "猫[ねこ]は?", answer: "cat")

    get deck_quiz_path(@deck)

    assert_match "猫は?", response.body
    assert_no_match(/<ruby>猫/, response.body)
  end

  test "a card still being learned keeps its readings" do
    only_due_card(review_count: 1, interval_days: 1, ease: 2.5)
       .update!(question: "猫[ねこ]は?", answer: "cat")

    get deck_quiz_path(@deck)

    assert_match(/<ruby>猫<rt>ねこ<\/rt><\/ruby>/, response.body)
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

  # Follows LlmChat, so switching provider cannot silently leave these stubs
  # pointing at an endpoint nothing calls.
  def llm_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end

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
