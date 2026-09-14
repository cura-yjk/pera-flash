class UsersController < ApplicationController
  # Show or hide readings. A preference rather than a per-session toggle: once
  # someone can read the kanji they want them off everywhere, not just here.
  def toggle_furigana
    current_user.update!(show_furigana: !current_user.show_furigana)
    redirect_back fallback_location: dashboard_path
  end

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
