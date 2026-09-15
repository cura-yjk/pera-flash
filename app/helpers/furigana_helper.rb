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
  KANA = /[\p{Hiragana}\p{Katakana}ー]/
  READING = /#{KANA}+/

  # A word annotated as a whole: kanji, then anything up to the bracket.
  #
  # The convention is one reading per kanji -- 食[た]べる -- and the model is
  # told so, but it writes 書き出し[かきだし] often enough that a strict pattern
  # left raw square brackets on screen: 5 in one measured reply, 27 in another.
  # Matching the wider shape and then deciding what the reading covers is the
  # only thing that holds up.
  ANNOTATION = /([\p{Han}々][\p{Han}々\p{Hiragana}\p{Katakana}ー]*)\[(#{READING})\]/

  # `show: false` strips the readings instead, which is how a learner tests
  # themselves once the kanji starts sticking -- same stored text either way.
  def with_furigana(text, show: true)
    # Escaped BEFORE the ruby tags go in: flashcards are user-editable, so the
    # content is untrusted. Substituting first and escaping after would escape
    # our own markup; not escaping at all would be an injection hole.
    escaped = ERB::Util.html_escape(text.to_s)

    # html_safe on this branch too. gsub on a SafeBuffer hands back a plain
    # String, which the view then escapes a second time -- so a card reading
    # "It's polite" rendered as "It&#39;s polite" the moment readings were
    # switched off. Safe to mark: the text was escaped above, and stripping the
    # bracket annotations cannot reintroduce markup.
    return escaped.gsub(ANNOTATION, '\1').html_safe unless show

    annotate(escaped).html_safe
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

      annotate(part)
    end

    annotated.join.html_safe
  end

  # Puts each reading over the text it belongs to.
  #
  # The hard case is deciding how much of the match the reading covers, because
  # 書き出し[かきだし] and 私は本[ほん] are the same shape: kanji, kana, kanji,
  # bracket. Guessing wrong on the second would print ほん above 私は本, which
  # is worse than the raw brackets it replaces -- a learner cannot tell a
  # confidently wrong reading from a right one.
  #
  # The kana decide it. In a real word the kana are part of the reading and
  # appear inside it in order (き and し are both in かきだし); a particle
  # between two words is not (は is not in ほん). So: cover the whole match when
  # the kana check out, and fall back to the last kanji run when they do not.
  def annotate(text)
    text.gsub(ANNOTATION) do
      word = Regexp.last_match(1)
      reading = Regexp.last_match(2)

      if reads_as_one_word?(word, reading)
        ruby(word, reading)
      else
        head, kanji = word.match(/\A(.*?)(#{KANJI})\z/m).captures
        "#{head}#{ruby(kanji, reading)}"
      end
    end
  end

  def ruby(text, reading)
    "<ruby>#{text}<rt>#{reading}</rt></ruby>"
  end

  # Every kana in the word, in order, somewhere in the reading.
  def reads_as_one_word?(word, reading)
    kana = word.scan(KANA)
    return true if kana.empty?

    remaining = reading.dup
    kana.all? do |character|
      index = remaining.index(character)
      index && remaining = remaining[(index + 1)..]
    end
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
