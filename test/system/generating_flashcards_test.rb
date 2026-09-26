require "application_system_test_case"

# Generating flashcards from a chat, with the model stubbed at the HTTP level
# so the cards stream through the real pipeline -- the streaming response,
# flashcard_stream_controller, and the preview form they are saved from.
class GeneratingFlashcardsTest < ApplicationSystemTestCase
  # Generation is rate limited per user (ConversationsController), counted in
  # Rails.cache, which the in-process server shares across tests: without this
  # the sixth generation in a minute is refused, whichever test makes it.
  setup do
    Rails.cache.clear
    @conversation = conversations(:lesson)
    sign_in_as(users(:learner))
  end

  test "cards stream into the preview and save" do
    stub_card_stream([
      { question: "How do you say 'I like cats'?", answer: "猫が好きです" },
      { question: "What does 好き mean?", answer: "Liked, fond of" }
    ])

    visit conversation_path(@conversation)
    click_and_confirm("Generate flashcards", expect: "Review your flashcards")

    assert_field with: "How do you say 'I like cats'?", wait: 10
    assert_field with: "What does 好き mean?"
    assert_no_text "is writing your flashcards"

    assert_difference -> { @conversation.flashcards.count }, 2 do
      click_and_confirm("Save to Flashcards", expect: "2 cards added!")
    end
  end

  # Save stays off until the list is complete: saving half of it would lose
  # the rest, since the next generation starts after the saved cards.
  test "Save waits for the whole list" do
    stub_card_stream([{ question: "What does 猫 mean?", answer: "Cat" }])

    visit conversation_path(@conversation)
    click_and_confirm("Generate flashcards", expect: "Review your flashcards")

    assert_button "Save to Flashcards", disabled: false, wait: 10
  end

  # The notice says why, and its own button tries again -- no scrolling back
  # up to the Generate button.
  test "a busy Gemini says so, and Try again brings the cards" do
    stub_request(:post, %r{generativelanguage\.googleapis\.com/.*streamGenerateContent})
      .to_return(status: 503, body: { error: { message: "high demand" } }.to_json).then
      .to_return(status: 200, headers: { "Content-Type" => "text/event-stream" },
                 body: card_stream_body([{ question: "犬[いぬ]", answer: "dog" }]))

    visit conversation_path(@conversation)
    click_and_confirm("Generate flashcards", expect: "busy right now")
    click_and_confirm("Try again", expect: "Review your flashcards")

    assert_field with: "犬[いぬ]", wait: 10
  end

  # Nothing worth a card is an answer, not an empty form with a Save button.
  test "nothing to card says so, with nothing to save" do
    stub_card_stream([])

    visit conversation_path(@conversation)
    click_and_confirm("Generate flashcards", expect: "Nothing to make cards from")

    assert_no_button "Save to Flashcards"
  end

  test "a failed generation says so and saves nothing" do
    stub_request(:post, %r{generativelanguage\.googleapis\.com/.*streamGenerateContent}).to_return(status: 500, body: "{}")

    visit conversation_path(@conversation)
    click_and_confirm("Generate flashcards", expect: "make flashcards just now")

    assert_no_button "Save to Flashcards"
  end

  private

  # Gemini's streaming wire format, with the cards' JSON cut into pieces that
  # fall mid-card, the way the real thing arrives.
  def stub_card_stream(cards)
    stub_request(:post, %r{generativelanguage\.googleapis\.com/.*streamGenerateContent})
      .to_return(status: 200, headers: { "Content-Type" => "text/event-stream" }, body: card_stream_body(cards))
  end

  def card_stream_body(cards)
    { flashcards: cards }.to_json.chars.each_slice(17).map do |piece|
      "data: #{{ 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => piece.join }] } }] }.to_json}\n\n"
    end.join
  end
end
