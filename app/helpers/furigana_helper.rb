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

  # Whether this reader wants readings shown. Defaults to on: a beginner who
  # cannot read the kanji is stuck without them.
  def show_furigana?
    current_user&.show_furigana != false
  end
end
