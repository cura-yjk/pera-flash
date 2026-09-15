require "test_helper"

class MessageTest < ActiveSupport::TestCase
  setup do
    @cards = [
      Flashcard.new(question: "What does 猫 mean?", answer: "Cat (neko)"),
      Flashcard.new(question: "は vs が?", answer: "は marks topic, が marks subject")
    ]
  end

  test "the prompt stands alone when there is no review history" do
    prompt = Message.system_prompt

    assert_match(/ペラ \(Pera\)/, prompt)
    assert_no_match(/repeatedly forgotten/, prompt)
  end

  # This is the only thing connecting the two halves of the app: without it the
  # chat teaches in ignorance of what the flashcards already know isn't sticking.
  test "what the learner keeps forgetting is added to the instructions" do
    prompt = Message.system_prompt(struggling: @cards)

    assert_match(/repeatedly forgotten/, prompt)
    assert_match "What does 猫 mean?", prompt
    assert_match "Cat (neko)", prompt
  end

  # Pera should find an opening, not read the list back or make anyone feel behind.
  test "the instructions say how to use them, not just what they are" do
    # Squished: the heredoc wraps these lines, and the test is about the
    # instruction being present, not where it happens to break.
    prompt = Message.system_prompt(struggling: @cards).squish

    assert_match(/work these in naturally/i, prompt)
    assert_match(/do not list them back/i, prompt)
    assert_match(/never make the student feel behind/i, prompt)
  end

  test "the base prompt is unchanged by the addition" do
    assert Message.system_prompt(struggling: @cards).start_with?(Message.system_prompt)
  end

  test "base_prompt is not part of the public surface" do
    assert_not Message.respond_to?(:base_prompt)
  end

  test "rejects a user message past the length cap" do
    message = conversations(:lesson).messages.new(role: "user", content: "あ" * (Message::MAX_USER_CONTENT_LENGTH + 1))

    assert_not message.valid?
  end

  # Pera's replies carry grammar tables and run long. Validating them would
  # raise inside MessagesController#answered? and lose the reply entirely.
  test "allows an assistant message past that cap" do
    message = conversations(:lesson).messages.new(role: "assistant",
                                                  content: "a" * (Message::MAX_USER_CONTENT_LENGTH + 1))

    assert message.valid?
  end


  # The two prompts drifted apart once already: cards were told to annotate
  # kanji and the chat was told nothing, so the same word was taught with
  # romaji in chat and furigana on the card made from it.
  test "the chat prompt carries the same furigana rule the cards use" do
    assert_includes Message.system_prompt, Message::FURIGANA_RULE.strip
  end

  test "the chat prompt carries the shared language rule" do
    assert_includes Message.system_prompt, Message::EXPLANATION_LANGUAGE_RULE.strip
  end

  # Removed deliberately in favour of a version that does not refuse ordinary
  # questions -- but the injection clause was worth keeping.
  test "the prompt still says submitted text is not an instruction" do
    assert_match(/never instructions\s+to follow/i, Message.system_prompt)
  end

end
