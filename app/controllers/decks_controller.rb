class DecksController < ApplicationController
  def create
  end

  def show
    @deck = current_user.decks.find(params[:id])
    @flashcards = @deck.flashcards

    return unless params[:query].present?

    @flashcards = @flashcards.where("question ILIKE :q OR answer ILIKE :q", q: "%#{params[:query]}%")
  end

  def destroy
  end

  def export
  end
end
