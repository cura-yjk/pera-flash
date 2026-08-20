class DecksController < ApplicationController
  # List the current user's decks, annotated with each deck's flashcard
  # count via a LEFT JOIN + COUNT (so decks with zero flashcards still show)
  def index
    @decks = current_user.decks.left_joins(:flashcards)
                         .select("decks.*, COUNT(flashcards.id) AS flashcards_count")
                         .group("decks.id")
                         .order(created_at: :desc)
  end

  # Create a new deck for the current user
  def create
    @deck = current_user.decks.new(deck_params)

    if @deck.save
      redirect_to decks_path, notice: "Deck created."
    else
      # Re-fetch @decks (same query as #index) since validation failure
      # re-renders the index view, which expects @decks to be present
      @decks = current_user.decks.left_joins(:flashcards)
                           .select("decks.*, COUNT(flashcards.id) AS flashcards_count")
                           .group("decks.id")
                           .order(created_at: :desc)
      render :index, status: :unprocessable_entity
    end
  end

  # Show a single deck's flashcards, optionally filtered by a search query
  # against question/answer text (case-insensitive)
  def show
    @deck = current_user.decks.find(params[:id])
    @flashcards = @deck.flashcards

    return unless params[:query].present?

    @flashcards = @flashcards.where("question ILIKE :q OR answer ILIKE :q", q: "%#{params[:query]}%")
  end

  # TODO: not yet implemented
  def destroy
  end

  # TODO: not yet implemented
  def export
  end

  private

  # Whitelist deck attributes safe for mass assignment
  def deck_params
    params.require(:deck).permit(:name)
  end
end
