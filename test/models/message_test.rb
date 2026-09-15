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
end
