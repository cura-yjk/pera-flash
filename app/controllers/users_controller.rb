class UsersController < ApplicationController
  # Show or hide readings. A preference rather than a per-session toggle: once
  # someone can read the kanji they want them off everywhere, not just here.
  def toggle_furigana
    current_user.update!(show_furigana: !current_user.show_furigana)

    redirect_to back_with_reveal_state
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

  private

  # Back where they came from, carrying whether the answer was on screen.
  #
  # redirect_back cannot add a query parameter, so the referer is rebuilt --
  # and only its path and query are kept, never the host. The referer comes
  # from the client, and redirecting to a host it names is how an open redirect
  # starts.
  def back_with_reveal_state
    target = URI.parse(request.referer.presence || dashboard_path)
    here = [target.path.presence || dashboard_path, target.query].compact.join("?")

    params[:revealed].present? ? with_revealed(here) : here
  rescue URI::InvalidURIError
    dashboard_path
  end

  def with_revealed(path)
    separator = path.include?("?") ? "&" : "?"

    "#{path}#{separator}revealed=1"
  end
end
