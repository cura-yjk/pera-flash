# Picks finished cards out of FlashcardsSchema JSON while it is still being
# written, so each one can be shown as soon as it is complete rather than after
# the whole list.
#
#   cards = StreamedCards.new
#   cards.push('{"flashcards":[{"question":"What') { |card| ... } # nothing yet
#   cards.push(' does 猫 mean?","answer":"Cat"},')   { |card| ... } # one card
#
# Not a general JSON parser. It tracks just enough -- whether it is inside a
# string, and how deeply nested -- to know when a card object has closed, then
# hands that object's text to JSON.parse. Braces and quotes inside a card's
# text are inside a string, so they do not count.
class StreamedCards
  # {"flashcards": [ {card} ] } -- the outer object, the array, then a card.
  CARD_DEPTH = 3

  def initialize
    @depth = 0
    @in_string = false
    @escaped = false
    @card = nil
  end

  # Feeds the next piece of the response. Yields each card completed by it, as
  # a Hash with "question" and "answer".
  def push(text, &on_card)
    text.each_char do |char|
      @card << char if @card
      @in_string ? read_string(char) : read_structure(char, &on_card)
    end
  end

  private

  def read_structure(char, &)
    case char
    when '"' then @in_string = true
    when "{", "[" then nest(char)
    when "}", "]" then unnest(char, &)
    end
  end

  def nest(char)
    @depth += 1
    @card = +"{" if char == "{" && @depth == CARD_DEPTH
  end

  def unnest(char)
    if char == "}" && @depth == CARD_DEPTH
      yield JSON.parse(@card)
      @card = nil
    end
    @depth -= 1
  end

  def read_string(char)
    if @escaped
      @escaped = false
    elsif char == "\\"
      @escaped = true
    elsif char == '"'
      @in_string = false
    end
  end
end
