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

  # Chat content -- both the learner's messages and Pera's replies -- rendered
  # as markdown and then sanitized.
  #
  # The sanitize step is not optional. Kramdown passes raw HTML straight
  # through, and this output was being handed to raw(), so anything a user
  # typed into the chat executed in their browser: <script>alert(1)</script>
  # came back verbatim, and [x](javascript:...) became a live link.
  #
  # The allowlist is spelled out because Rails' default one strips <table>,
  # and Pera's vocabulary breakdown is a table -- the default would quietly
  # delete the most useful part of every reply. RUBY_TAGS are what
  # with_furigana_html inserts.
  MARKDOWN_TAGS = %w[
    p br hr div span strong em b i u del ins code pre blockquote
    h1 h2 h3 h4 h5 h6 ul ol li a
    table thead tbody tfoot tr th td
    ruby rt rp
  ].freeze
  MARKDOWN_ATTRIBUTES = %w[href title class colspan rowspan].freeze

  def render_markdown(text)
    html = Kramdown::Document.new(separate_tables(text.to_s), input: "GFM", syntax_highlighter: "rouge").to_html

    sanitize(html, tags: MARKDOWN_TAGS, attributes: MARKDOWN_ATTRIBUTES)
  end

  TABLE_ROW = /\A\s*\|.*\|\s*\z/
  TABLE_DELIMITER = /\A\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)+\|?\s*\z/
  CODE_FENCE = /\A\s*(```|~~~)/

  # Kramdown starts a table only after a blank line. Pera often writes its
  # breakdown table on the line straight after "**Breakdown:**", and the whole
  # table then rendered as a paragraph of raw pipes -- one of the four real
  # correction replies on file on 2026-09-26. A blank line is put in front of
  # any table header (a row followed by a |---| row) that follows text, keeping
  # its indentation so the table stays inside its list item. Code blocks are
  # left as they are.
  def separate_tables(text)
    lines = text.lines(chomp: true)
    in_code = false

    lines.each_with_index.flat_map do |line, i|
      in_code = !in_code if line.match?(CODE_FENCE)
      table_after_text?(lines, i) && !in_code ? ["", line] : [line]
    end.join("\n")
  end

  def table_after_text?(lines, index)
    return false if index.zero?

    previous = lines[index - 1]
    lines[index].match?(TABLE_ROW) && lines[index + 1].to_s.match?(TABLE_DELIMITER) &&
      previous.strip.present? && !previous.match?(TABLE_ROW)
  end
end
