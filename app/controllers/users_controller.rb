class UsersController < ApplicationController
  def dashboard
    @conversations = current_user.conversations.order(created_at: :asc)
    @decks = current_user.decks

    flashcards = Flashcard.left_joins(:deck, :conversation)
                          .where("decks.user_id = :uid OR conversations.user_id = :uid", uid: current_user.id)

    @deck_count = @decks.count
    @flashcard_count = flashcards.count
    @random_flashcard = flashcards.order(Arel.sql("RANDOM()")).first
    @recent_flashcards = flashcards.order(created_at: :desc).limit(3)
  end
end
