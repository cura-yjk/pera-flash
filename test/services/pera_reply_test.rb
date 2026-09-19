require "test_helper"

# What Pera is allowed to see, and what comes back.
#
# Stubbed at the HTTP level rather than with a double, because the thing worth
# asserting is the payload that leaves the app: how much history it carries,
# in what order, and whose cards are named in the instructions. A double would
# only prove that PeraReply calls the methods PeraReply calls.
class PeraReplyTest < ActiveSupport::TestCase
  STREAM_URL = %r{generativelanguage\.googleapis\.com/.*streamGenerateContent}

  setup do
    @user = users(:learner)
    @conversation = conversations(:lesson)
    @deck = decks(:starter)
    @question = @conversation.messages.create!(role: "user", content: "ねこがすきです")
  end

  test "insists on a block, because it has nowhere to put the text otherwise" do
    stub_gemini("anything")

    assert_raises(ArgumentError) { PeraReply.new(@conversation, @question).call }
  end

  test "yields the reply in pieces and returns the whole of it" do
    stub_gemini("猫が", "好きです。", " Nicely done!")

    pieces = []
    whole = PeraReply.new(@conversation, @question).call { |text| pieces << text }

    assert_equal ["猫が", "好きです。", " Nicely done!"], pieces
    assert_equal "猫が好きです。 Nicely done!", whole
  end

  test "does not yield empty chunks" do
    stub_gemini("猫", "", "が好き")

    pieces = []
    PeraReply.new(@conversation, @question).call { |text| pieces << text }

    assert_equal ["猫", "が好き"], pieces
  end

  test "replays the conversation oldest first" do
    stub_gemini("ok")

    PeraReply.new(@conversation, @question).call { |_| }

    assert_equal [
      "How do I say \"cat\" in Japanese?",
      "猫 (neko) means cat.",
      "And how do I say \"I like cats\"?",
      "猫が好きです (neko ga suki desu)."
    ], sent_texts.first(4)
  end

  # The message being answered is already saved when this runs, and #ask sends
  # it too. Replaying it as well showed the model every new message twice.
  test "never replays the message it is answering" do
    stub_gemini("ok")

    PeraReply.new(@conversation, @question).call { |_| }

    assert_equal 1, sent_texts.count(@question.content),
                 "the message being answered should reach the model once, via #ask"
  end

  test "replays no more than MAX_HISTORY_MESSAGES, keeping the newest" do
    40.times { |i| @conversation.messages.create!(role: "user", content: "filler #{i}") }
    stub_gemini("ok")

    PeraReply.new(@conversation, @question).call { |_| }

    history = sent_texts - [@question.content]

    assert_equal PeraReply::MAX_HISTORY_MESSAGES, history.size
    assert_includes history, "filler 39", "the newest turns are the ones a tutor needs"
    assert_not_includes history, "filler 0"
  end

  test "tells Pera which cards the learner keeps failing" do
    struggling_card("What does 犬 mean?")
    stub_gemini("ok")

    PeraReply.new(@conversation, @question).call { |_| }

    assert_includes instructions, "犬"
  end

  test "names no more than STRUGGLING_LIMIT of them" do
    6.times { |i| struggling_card("Card #{i}", lapses: 10 - i) }
    stub_gemini("ok")

    PeraReply.new(@conversation, @question).call { |_| }

    named = (0..5).count { |i| instructions.include?("Card #{i}") }

    assert_equal PeraReply::STRUGGLING_LIMIT, named
  end

  # What somebody keeps forgetting is a fact about them, not about where the
  # card came from.
  test "draws struggling cards from every deck, not just this conversation" do
    other_deck = @user.decks.create!(name: "Kanji from somewhere else")
    struggling_card("What does 鳥 mean?", deck: other_deck)
    stub_gemini("ok")

    PeraReply.new(@conversation, @question).call { |_| }

    assert_includes instructions, "鳥"
  end

  test "leaves another learner's cards out of it" do
    stranger = users(:other)
    struggling_card("What does 魚 mean?", deck: stranger.decks.create!(name: "Not yours"))
    stub_gemini("ok")

    PeraReply.new(@conversation, @question).call { |_| }

    assert_not_includes instructions, "魚"
  end

  private

  # One SSE frame per chunk, which is Gemini's streaming wire format. The
  # request is captured on the way past: it is the thing under test.
  def stub_gemini(*chunks)
    body = chunks.map do |text|
      "data: #{{ 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => text }] } }] }.to_json}\n\n"
    end.join

    stub_request(:post, STREAM_URL).to_return do |request|
      @payload = JSON.parse(request.body)
      { status: 200, headers: { "Content-Type" => "text/event-stream" }, body: body }
    end
  end

  # Gemini carries the prompt in systemInstruction, separately from the turns.
  # ruby_llm 1.16 did not: it sent #with_instructions as turn zero of
  # `contents`, which is why these read the payload rather than the chat
  # object -- where the prompt lands is the gem's business and has changed
  # once already.
  def instructions
    parts = @payload.dig("systemInstruction", "parts")
    return "" if parts.nil?

    parts.map { |part| part["text"] }.join(" ").to_s
  end

  # Every piece of text the model was sent as conversation, in order.
  def sent_texts
    @payload.fetch("contents")
            .flat_map { |turn| turn.fetch("parts").map { |part| part["text"] } }
            .compact
  end

  def struggling_card(question, deck: @deck, lapses: Flashcard::STRUGGLING_LAPSES + 1)
    deck.flashcards.create!(question: question, answer: "...", lapse_count: lapses)
  end
end
