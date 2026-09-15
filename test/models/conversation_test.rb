require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  setup { @conversation = conversations(:lesson) }

  # Generating used to send the whole transcript every time and ask the model
  # to focus on recent topics and avoid the existing cards -- two instructions
  # it could ignore. Scoping the input makes duplication impossible instead.
  test "only offers messages newer than the last flashcard" do
    contents = @conversation.messages_for_flashcards.map(&:content)

    assert_includes contents, messages(:late_question).content
    assert_includes contents, messages(:late_answer).content
    assert_not_includes contents, messages(:early_question).content
  end

  # A topic already under way when the last cards were made would otherwise
  # lose its opening line.
  test "carries one message of lead-in context from before the cutoff" do
    ordered = @conversation.messages_for_flashcards.order(:created_at)

    assert_equal messages(:early_answer).content, ordered.first.content,
                 "expected the last message before the cutoff as lead-in"
  end

  test "offers the whole conversation when no flashcards exist yet" do
    @conversation.flashcards.destroy_all

    assert_equal @conversation.messages.count, @conversation.messages_for_flashcards.count
  end

  # Titling is cosmetic -- a conversation keeping its default title is a far
  # better outcome than failing the message that triggered the attempt.
  test "a failed title attempt does not raise" do
    stub_request(:post, llm_url).to_timeout
    conversation = conversations(:lesson)
    conversation.update!(title: "Let's chat!")

    assert_nothing_raised { conversation.generate_title_from_first_message }
    assert_equal "Let's chat!", conversation.reload.title
  end

  # Regression: lead-in context was returned even with nothing new after it,
  # which made "nothing to generate" look like "one message to generate".
  test "offers nothing at all when no messages follow the last flashcard" do
    @conversation.flashcards.update_all(created_at: Time.current)

    assert_empty @conversation.messages_for_flashcards
  end

  test "is ordered oldest first" do
    ordered = @conversation.messages_for_flashcards.order(:created_at).to_a

    assert_equal ordered.sort_by(&:created_at), ordered
  end

  private

  # Follows LlmChat, so switching provider cannot silently leave these stubs
  # pointing at an endpoint nothing calls.
  def llm_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end
end
