# Multiple-choice quizzing over cards the learner already has.
#
# Built on the review schedule rather than beside it, but allowed to move a
# card in one direction only. A wrong answer is an "again", exactly as in
# review, so what a quiz shows was forgotten comes back sooner. A right answer
# changes nothing: picking an answer out of four is recognition, and a card
# can be passed by ruling out the other three. Counting that as a "good" grew
# the interval of cards the learner could not have recalled, so only review --
# recall, graded by the learner -- moves a card further out.
#
# Like the review flow, nothing here calls the LLM -- distractors come from the
# learner's other cards, so a quiz costs nothing and works offline.
class QuizzesController < ApplicationController
  LENGTH = 10

  def show
    @deck = current_user.decks.find(params[:deck_id]) if params[:deck_id]
    return finish if exhausted?

    start_quiz unless resuming?

    render_current_question
  end

  # Grades, then redirects back to #show rather than rendering the next
  # question here.
  #
  # Rendering was the bug: Turbo submits these buttons as a form, and Turbo
  # Drive ignores a 200 HTML response to a form submission -- it only follows a
  # redirect (or applies a turbo_stream). So every tap reached the server,
  # graded the card and advanced the quiz while the page sat unchanged on
  # question one. The integration tests read the response body directly, which
  # is why they passed throughout.
  def answer
    @deck = current_user.decks.find(params[:deck_id]) if params[:deck_id]
    return redirect_to quiz_path_for(@deck) unless quiz

    grade(current_card, params[:choice])
    advance

    redirect_to quiz_path_for(@deck), status: :see_other
  end

  private

  # --- session state --------------------------------------------------------

  # A quiz lives in the session: it is a few minutes long and nothing about it
  # is worth keeping once finished. The cards it touches keep the durable part.
  def quiz
    session[:quiz]
  end

  def resuming?
    in_progress? && quiz["index"].to_i < quiz["card_ids"].size
  end

  # The last answer redirects here, so #show has to recognise a finished quiz
  # and hand over the score -- otherwise it would start a fresh quiz and the
  # results page would be unreachable.
  def exhausted?
    in_progress? && quiz["index"].to_i >= quiz["card_ids"].size
  end

  def in_progress?
    quiz.present? && quiz["deck_id"] == @deck&.id
  end

  def start_quiz
    session[:quiz] = {
      "deck_id" => @deck&.id,
      "card_ids" => quiz_cards.map(&:id),
      "index" => 0,
      "correct" => 0
    }
  end

  # Due cards first, because those are the ones slipping. Falls back to the
  # whole collection so a quiz is still possible when nothing is due.
  def quiz_cards
    scope = @deck ? @deck.flashcards : Flashcard.for_user(current_user)
    due = scope.due.in_review_order.limit(LENGTH).to_a
    due.presence || scope.in_review_order.limit(LENGTH).to_a
  end

  def current_card
    return nil unless quiz

    Flashcard.for_user(current_user).find_by(id: quiz["card_ids"][quiz["index"].to_i])
  end

  def advance
    session[:quiz] = quiz.merge("index" => quiz["index"].to_i + 1)
  end

  # --- grading --------------------------------------------------------------

  def grade(card, choice)
    return if card.nil?

    if card.answer == choice
      # Scored, not scheduled: see the note at the top of this class.
      session[:quiz] = quiz.merge("correct" => quiz["correct"].to_i + 1)
    else
      # Same path a forgotten card takes in review: back into today's queue,
      # and harder to graduate next time.
      card.review!("again")
    end
  end

  # --- rendering ------------------------------------------------------------

  def render_current_question
    card = current_card
    return finish if card.nil?

    @question = QuizQuestion.new(card, pool: distractor_pool(card))
    @position = quiz["index"].to_i + 1
    @total = quiz["card_ids"].size

    # Rendered explicitly: #answer has no template of its own, and without this
    # Rails answers 204 and the quiz silently stops after one question.
    return render :too_few unless @question.answerable?

    render :show
  end

  def finish
    @score = quiz&.dig("correct").to_i
    @total = quiz&.dig("card_ids")&.size.to_i
    session.delete(:quiz)
    render :results
  end

  # The deck first, since those are the most confusable, widening to everything
  # the learner owns when a deck is too small to fill four options.
  def distractor_pool(card)
    owned = Flashcard.for_user(current_user).where.not(id: card.id)
    within_deck = card.deck ? owned.where(deck_id: card.deck_id) : owned.none

    within_deck.count >= QuizQuestion::OPTION_COUNT - 1 ? within_deck : owned
  end

  def quiz_path_for(deck)
    deck ? deck_quiz_path(deck) : quiz_path
  end
  helper_method :quiz_path_for
end
