require "application_system_test_case"

# Generating flashcards from a chat, with the model stubbed at the HTTP level
# so the cards stream through the real pipeline -- the streaming response,
# flashcard_stream_controller, and the preview form they are saved from.
class GeneratingFlashcardsTest < ApplicationSystemTestCase
  setup do
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
    json = { flashcards: cards }.to_json
    body = json.chars.each_slice(17).map do |piece|
      "data: #{{ 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => piece.join }] } }] }.to_json}\n\n"
    end.join

    stub_request(:post, %r{generativelanguage\.googleapis\.com/.*streamGenerateContent})
      .to_return(status: 200, headers: { "Content-Type" => "text/event-stream" }, body: body)
  end
end
