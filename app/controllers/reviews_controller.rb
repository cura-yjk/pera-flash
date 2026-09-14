# Studying cards, as opposed to making or editing them.
#
# Nothing here calls the LLM. Cards are inert once created, so a review session
# costs nothing and works whether or not a provider is reachable -- which is
# the point of keeping generation at the creation boundary.
class ReviewsController < ApplicationController
  # The session: everything due, across all decks or within one.
  def show
    @deck = current_user.decks.find(params[:deck_id]) if params[:deck_id]
    @due = due_cards
    @card = @due.first
    @remaining = @due.size
  end

  # Records an answer and hands back the next card.
  def update
    @card = Flashcard.for_user(current_user).find(params[:id])
    @deck = current_user.decks.find(params[:deck_id]) if params[:deck_id]

    @card.review!(params[:grade])

    @due = due_cards
    @next_card = @due.first
    @remaining = @due.size

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to review_path_for(@deck) }
    end
  rescue ArgumentError
    head :unprocessable_entity
  end

  private

  def due_cards
    scope = @deck ? @deck.flashcards : Flashcard.for_user(current_user)
    scope.due.in_review_order.to_a
  end

  def review_path_for(deck)
    deck ? deck_review_path(deck) : review_path
  end
  helper_method :review_path_for
end
