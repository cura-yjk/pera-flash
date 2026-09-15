class UsersController < ApplicationController
  # Show or hide readings. A preference rather than a per-session toggle: once
  # someone can read the kanji they want them off everywhere, not just here.
  def toggle_furigana
    current_user.update!(show_furigana: !current_user.show_furigana)
    redirect_back fallback_location: dashboard_path
  end

  # Saved on the user, so the choice follows them to another device rather
  # than living in a cookie. Until someone picks, the browser's own languages
  # decide -- see ApplicationController#chosen_locale.
  def update_locale
    locale = params[:locale].to_s
    current_user.update!(locale: locale) if I18n.available_locales.map(&:to_s).include?(locale)

    redirect_back fallback_location: dashboard_path
  end

  # How many of each list the dashboard shows. Everything below is "recent",
  # so the newest few, taken in the query rather than by loading the lot.
  RECENT = 3
  RECENT_CONVERSATIONS = 7

  def dashboard
    # Newest 7, limited in the query. This read `.last(7)` on a descending
    # relation, which returns the *oldest* seven -- so "Recent Conversations"
    # was showing the least recent ones.
    @conversations = current_user.conversations.started.order(created_at: :desc).limit(RECENT_CONVERSATIONS)
    @decks = Deck.with_card_counts(current_user).limit(RECENT)

    flashcards = Flashcard.for_user(current_user)

    @deck_count = current_user.decks.count
    @flashcard_count = flashcards.count
    @random_flashcard = flashcards.order(Arel.sql("RANDOM()")).first
    @recent_flashcards = flashcards.order(created_at: :desc).limit(3)
  end
end
