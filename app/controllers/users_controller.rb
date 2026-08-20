class UsersController < ApplicationController
  def dashboard
    @conversations = current_user.conversations.order(created_at: :asc)
    @decks = current_user.decks.left_joins(:flashcards)
                         .select("decks.*, COUNT(flashcards.id) AS flashcards_count")
                         .group("decks.id")
                         .order(created_at: :desc)

    flashcards = Flashcard.left_joins(:deck, :conversation)
                          .where("decks.user_id = :uid OR conversations.user_id = :uid", uid: current_user.id)

    @deck_count = current_user.decks.count
    @flashcard_count = flashcards.count
    @random_flashcard = flashcards.order(Arel.sql("RANDOM()")).first
    @recent_flashcards = flashcards.order(created_at: :desc).limit(3)
  end
end
