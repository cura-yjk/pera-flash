class UsersController < ApplicationController
  def dashboard
    @due_count = Flashcard.for_user(current_user).due.count
    @conversations = current_user.conversations.where.associated(:messages).distinct.order(created_at: :desc)
    @decks = current_user.decks.left_joins(:flashcards)
                         .select("decks.*, COUNT(flashcards.id) AS flashcards_count")
                         .group("decks.id")
                         .order(created_at: :desc)

    flashcards = Flashcard.for_user(current_user)

    @deck_count = current_user.decks.count
    @flashcard_count = flashcards.count
    @random_flashcard = flashcards.order(Arel.sql("RANDOM()")).first
    @recent_flashcards = flashcards.order(created_at: :desc).limit(3)
  end
end
