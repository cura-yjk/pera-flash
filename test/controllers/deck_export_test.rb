require "test_helper"

class DeckExportTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:learner)
    @deck = decks(:starter)
  end

  test "exports the deck as CSV" do
    @deck.flashcards.create!(question: "What does 猫 mean?", answer: "cat")

    get export_deck_path(@deck)

    assert_response :success
    assert_match "text/csv", response.media_type
    assert_match "What does 猫 mean?", response.body
  end

  # Excel, Numbers and Sheets run a cell starting with = + - or @ as a formula.
  # Card text is partly written by the model, so this is not only about what a
  # learner types into their own cards.
  test "a cell that looks like a formula is exported as text" do
    @deck.flashcards.create!(question: '=HYPERLINK("http://example.com","Click")', answer: "+1")

    get export_deck_path(@deck)

    assert_match %q('=HYPERLINK), response.body
    assert_match "'+1", response.body
    assert_no_match(/^=HYPERLINK/, response.body)
  end

  test "ordinary text is left alone" do
    @deck.flashcards.create!(question: "猫[ねこ]が好きです", answer: "I like cats")

    get export_deck_path(@deck)

    assert_match "猫[ねこ]が好きです", response.body
    assert_no_match(/'猫/, response.body)
  end

  test "another user's deck cannot be exported" do
    theirs = Deck.create!(user: users(:other), name: "Theirs")

    get export_deck_path(theirs)

    assert_response :not_found
  end
end
