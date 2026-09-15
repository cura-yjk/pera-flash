require "application_system_test_case"

# The quiz and the review, driven through a real browser.
#
# The quiz is here because of a bug that shipped: tapping an answer graded the
# card and advanced the session server-side while the page never moved, because
# Turbo discards a 200 HTML response to a form submission. The integration test
# read response.body, saw the next question in it, and passed throughout.
class StudyingTest < ApplicationSystemTestCase
  setup do
    @user = users(:learner)
    @deck = decks(:starter)
    @cards = 6.times.map { |i| @deck.flashcards.create!(question: "Question #{i}?", answer: "Answer #{i}") }
    sign_in_as(@user)
  end

  test "answering a quiz question moves to the next one" do
    visit deck_quiz_path(@deck)
    assert_text(/Question 1 of/i)

    answer_current_question(expect: /Question 2 of/i)
  end

  test "working through the whole quiz reaches a score" do
    visit deck_quiz_path(@deck)

    # Assert the question is on screen before answering it. A click issued
    # before the page has settled lands on a node Turbo is about to replace,
    # does nothing, and reads exactly like a broken quiz -- which is what sent
    # me looking for a bug in the controller that was not there.
    #
    # Scoped to the options grid as well: the results page reuses the same
    # button classes, so an unscoped "first button" clicks "Back to decks".
    (1..@cards.size).each do |question|
      assert_text(/Question #{question} of/i)
      answer_current_question(expect: question == @cards.size ? /Quiz again/i : /Question #{question + 1} of/i)
    end

    assert_text(/Quiz again/i)
    assert_text(/\d+ of \d+/)
  end

  # The same selector the single-click test uses. `within(".d-grid")` looked
  # tidier but scopes to a node Turbo replaces, so the click after it goes
  # nowhere.
  def answer_current_question(expect:)
    option = first(".btn.btn-outline-secondary").text

    click_and_confirm(option, expect: expect)
  end

  test "a review reveals the answer only when asked, then grades it" do
    card = @cards.first
    Flashcard.for_user(@user).update_all(due_at: 1.day.from_now)
    card.update!(due_at: 1.hour.ago)

    visit review_path

    assert_text card.question
    assert_no_text card.answer

    click_and_confirm("Show answer", expect: card.answer)

    # Waits for the screen before looking at the database: Capybara returns as
    # soon as a click is dispatched, so checking the card first races the
    # request that updates it -- which is how this failed in CI while passing
    # locally.
    click_and_confirm("Good", expect: "Nothing due right now")

    # And the card really moved, rather than the queue just looking empty.
    assert_operator card.reload.interval_days, :>, 0
  end

  # Toggling repeatedly, because the report was that it is inconsistent rather
  # than broken: each click has to land, and the page that comes back has to
  # show the setting that was just chosen -- not the snapshot Turbo kept of the
  # page as it was a moment ago.
  test "the readings toggle lands every time" do
    Flashcard.for_user(@user).update_all(due_at: 1.day.from_now)
    @cards.first.update!(question: "猫[ねこ]が好[す]きです", due_at: 1.hour.ago)

    visit review_path

    4.times do |attempt|
      showing = attempt.even?

      click_and_confirm(showing ? "Hide readings" : "Show readings",
                        expect: showing ? "Show readings" : "Hide readings")

      assert_equal !showing, @user.reload.show_furigana, "click #{attempt + 1} did not land"
      if showing
        assert_no_selector "ruby rt"
      else
        assert_selector "ruby rt", text: "ねこ"
      end
    end
  end

  # Revealing is the learner's decision. Switching readings sent the page back
  # to the server, and the card came back hidden again -- with the grade
  # buttons still showing, so you were asked to grade an answer you could no
  # longer see.
  test "showing the answer survives switching readings" do
    card = @cards.first
    Flashcard.for_user(@user).update_all(due_at: 1.day.from_now)
    card.update!(question: "猫[ねこ]です", due_at: 1.hour.ago)

    visit review_path
    click_and_confirm("Show answer", expect: card.answer)

    click_and_confirm("Hide readings", expect: "Show readings")

    assert_text card.answer
    assert_button "Good"
    assert_no_button "Show answer"
    assert_no_selector "ruby rt"
  end

  test "readings can be switched off from the review page" do
    Flashcard.for_user(@user).update_all(due_at: 1.day.from_now)
    @cards.first.update!(question: "猫[ねこ]が好[す]きです", due_at: 1.hour.ago)

    visit review_path
    assert_selector "ruby rt", text: "ねこ"

    # Waits for the round trip before looking at the card: asserting straight
    # after the click races the page swap, and a stale node reads as a
    # perfectly healthy failure.
    click_and_confirm("Hide readings", expect: "Show readings")
    assert_no_selector "ruby rt"
    assert_text "猫が好きです"
  end
end
