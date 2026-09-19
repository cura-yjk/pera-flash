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

  # The join to messages multiplies the flashcard rows: `lesson` has 4 messages
  # and 1 card, so a COUNT without DISTINCT reports 4 cards.
  test "with_counts counts messages and cards independently" do
    counted = Conversation.with_counts.find(@conversation.id)

    assert_equal @conversation.messages.count, counted.messages_count
    assert_equal @conversation.flashcards.count, counted.flashcards_count
  end

  test "started excludes conversations nobody spoke in" do
    started = Conversation.started.map(&:id)

    assert_includes started, @conversation.id
    assert_not_includes started, conversations(:abandoned).id
  end


  # What turns a history list of "Let's chat!" into something navigable. It is
  # one more model call, made after the first reply is saved.
  test "names the chat after the first thing the learner said" do
    stub_title("Talking about cats")
    conversation = default_titled_conversation
    conversation.messages.create!(role: "user", content: "ねこがすきです")

    conversation.generate_title_from_first_message

    assert_equal "Talking about cats", conversation.reload.title
  end

  test "takes the title as the model gives it, without the surrounding space" do
    stub_title("  Cats and how to like them\n")
    conversation = default_titled_conversation
    conversation.messages.create!(role: "user", content: "ねこがすきです")

    conversation.generate_title_from_first_message

    assert_equal "Cats and how to like them", conversation.reload.title
  end

  # Only the default title is replaced, so a conversation is named once and a
  # later message cannot rename it -- nor pay for a call to do so.
  test "does not rename a chat that already has one" do
    conversation = conversations(:lesson)

    conversation.generate_title_from_first_message

    assert_not_requested :post, llm_url
    assert_equal "Talking about cats", conversation.reload.title
  end

  test "waits until there is something to name it after" do
    conversation = default_titled_conversation

    conversation.generate_title_from_first_message

    assert_not_requested :post, llm_url
    assert_equal "Let's chat!", conversation.reload.title
  end

  # A card is filed in a deck and reviewed from there; it outlives the chat it
  # was made in. Nothing deletes a conversation on its own today -- there is no
  # destroy route -- but closing an account does, and the cards must not take
  # the database's foreign key with them on the way out.
  test "a card outlives the chat it came from" do
    card = @conversation.flashcards.create!(question: "What does 猫 mean?", answer: "Cat",
                                            deck: decks(:starter))

    @conversation.destroy!

    assert Flashcard.exists?(card.id), "the card should survive its conversation"
    assert_nil card.reload.conversation_id
  end

  private

  # Follows LlmChat, so switching provider cannot silently leave these stubs
  # pointing at an endpoint nothing calls.
  # A conversation as #create leaves it: the default title, which is the only
  # one generate_title_from_first_message will replace.
  def default_titled_conversation
    users(:learner).conversations.create!
  end

  def stub_title(text)
    stub_request(:post, llm_url).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { "candidates" => [{ "content" => { "parts" => [{ "text" => text }] } }] }.to_json
    )
  end

  def llm_url
    %r{\Ahttps://generativelanguage\.googleapis\.com/.*#{Regexp.escape(LlmChat::MODEL)}:generateContent}
  end
end
