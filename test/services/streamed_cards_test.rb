require "test_helper"

class StreamedCardsTest < ActiveSupport::TestCase
  RESPONSE = {
    flashcards: [
      { question: "What does 猫 mean?", answer: "Cat" },
      { question: "How do you say {braces} and \"quotes\"?", answer: "こう} {言う\\" }
    ]
  }.to_json

  test "finds every card when the response arrives in one piece" do
    assert_equal JSON.parse(RESPONSE)["flashcards"], cards_from([RESPONSE])
  end

  # The point of it: a card is handed over the moment its closing brace
  # arrives, not when the whole list is done.
  test "hands over each card as soon as it is complete" do
    first_card_ends = RESPONSE.index("},") + 1
    parser = StreamedCards.new
    seen = []

    parser.push(RESPONSE[0...first_card_ends]) { |card| seen << card }
    assert_equal ["What does 猫 mean?"], seen.map { |card| card["question"] }

    parser.push(RESPONSE[first_card_ends..]) { |card| seen << card }
    assert_equal 2, seen.size
  end

  # Gemini splits wherever it likes: inside a word, a key, an escape.
  test "copes with the response split at every character" do
    assert_equal JSON.parse(RESPONSE)["flashcards"], cards_from(RESPONSE.chars)
  end

  test "finds nothing in an empty list" do
    assert_empty cards_from(['{"flashcards":[]}'])
  end

  private

  def cards_from(pieces)
    parser = StreamedCards.new
    cards = []
    pieces.each { |piece| parser.push(piece) { |card| cards << card } }
    cards
  end
end
