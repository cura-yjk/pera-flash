# Renders readings stored inline with their kanji.
#
# Cards store furigana in Anki's bracket convention -- 猫[ねこ]が好[す]きです --
# rather than in a parallel column. One field means the text and its readings
# cannot drift apart when someone edits a card, and text with no brackets (every
# card made before this existed) renders exactly as it always did.
#
# Readings attach per kanji, which romaji in parentheses cannot do: "(neko ga
# suki desu)" tells you how the sentence sounds but not which character makes
# which sound.
module FuriganaHelper
  KANJI = /[\p{Han}々]+/
  READING = /[\p{Hiragana}\p{Katakana}ー]+/
  ANNOTATION = /(#{KANJI})\[(#{READING})\]/

  # `show: false` strips the readings instead, which is how a learner tests
  # themselves once the kanji starts sticking -- same stored text either way.
  def with_furigana(text, show: true)
    # Escaped BEFORE the ruby tags go in: flashcards are user-editable, so the
    # content is untrusted. Substituting first and escaping after would escape
    # our own markup; not escaping at all would be an injection hole.
    escaped = ERB::Util.html_escape(text.to_s)

    return escaped.gsub(ANNOTATION, '\1') unless show

    escaped.gsub(ANNOTATION) { "<ruby>#{Regexp.last_match(1)}<rt>#{Regexp.last_match(2)}</rt></ruby>" }.html_safe
  end

  # The same annotation pass, but over HTML that has already been rendered and
  # sanitized -- chat messages, which are markdown before they are Japanese.
  #
  # with_furigana escapes its input first, which is right for a flashcard field
  # and wrong here: it would escape the markup we just produced. Instead this
  # substitutes only in the text between tags, so an annotation can never land
  # inside an attribute and turn href="..." into markup.
  def with_furigana_html(html, show: true)
    annotated = html.to_s.split(/(<[^>]*>)/).map do |part|
      next part if part.start_with?("<")

      next part.gsub(ANNOTATION, '\1') unless show

      part.gsub(ANNOTATION) { "<ruby>#{Regexp.last_match(1)}<rt>#{Regexp.last_match(2)}</rt></ruby>" }
    end

    annotated.join.html_safe
  end

  # Chat content rendered the way the chat renders it: markdown, sanitized,
  # then annotated. Used for finished messages and for each update of one still
  # streaming in, so a half-written reply looks like the one that gets saved.
  def chat_html(text)
    with_furigana_html(render_markdown(text), show: show_furigana?)
  end

  # Whether this reader wants readings shown. Defaults to on: a beginner who
  # cannot read the kanji is stuck without them.
  def show_furigana?
    current_user&.show_furigana != false
  end

  # Same question for one particular card, when it is being used as a prompt to
  # recall from. A card the schedule says is known drops its readings, so the
  # kanji is what gets tested -- otherwise every reading is handed over with the
  # question and the kanji is never actually learned.
  #
  # Only ever narrows: readings switched off for the account stay off.
  def show_furigana_for?(card)
    show_furigana? && !card.mastered?
  end
end
