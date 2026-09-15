module ApplicationHelper
  # The navbar carries the review queue and the quiz on every page, so both
  # numbers are needed well outside the dashboard that used to own them.
  #
  # Memoized under names of their own rather than reusing @due_count /
  # @flashcard_count, which the dashboard controller assigns for its stat tiles
  # -- sharing those would make the helper depend on which controller rendered it.
  def due_card_count
    return 0 unless user_signed_in?

    @due_card_count ||= Flashcard.for_user(current_user).due.count
  end

  # A quiz needs enough cards to build wrong answers from, so the link stays
  # hidden below that -- the dashboard applies the same guard, and QuizzesController
  # renders `too_few` for anyone who gets there anyway.
  def quiz_available?
    return false unless user_signed_in?

    @navbar_card_count ||= Flashcard.for_user(current_user).count
    @navbar_card_count >= QuizQuestion::OPTION_COUNT
  end

  def render_markdown(text)
    Kramdown::Document.new(text, input: 'GFM', syntax_highlighter: "rouge").to_html
  end
end
