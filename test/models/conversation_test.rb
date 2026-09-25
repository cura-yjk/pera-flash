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


  # --- naming a chat --------------------------------------------------------

  test "a short first message is the name as it is" do
    assert_equal "How does this app work?", Conversation.name_from("How does this app work?")
  end

  test "a long first message is cut at a word" do
    name = Conversation.name_from("I keep mixing up は and が when I talk about what I like and what I do not")

    assert_equal "I keep mixing up は and が when I talk…", name
    assert_operator name.length, :<=, Conversation::NAME_LENGTH
  end

  # Japanese has no spaces to cut at.
  test "long Japanese is cut at the length" do
    name = Conversation.name_from("にほんごのべんきょうをはじめたばかりですがなにからはじめればいいかぜんぜんわかりません")

    assert_equal Conversation::NAME_LENGTH, name.length
    assert name.end_with?("…")
  end

  # Readings are for reading the chat, not for a list of chat names.
  test "furigana is left out of the name" do
    assert_equal "猫が好きです", Conversation.name_from("猫[ねこ]が好[す]きです")
  end

  test "the name comes from the first line with something on it" do
    assert_equal "ねこが すきです。", Conversation.name_from("\n\n  ねこが すきです。\nIs this right?")
  end

  test "names a new chat after the first thing the learner said" do
    conversation = users(:learner).conversations.create!
    message = conversation.messages.create!(role: "user", content: "How do I count flat things?")

    conversation.name_after(message)

    assert_equal "How do I count flat things?", conversation.reload.title
  end

  # Named once: a later message cannot rename it, and nor can the first
  # message of a chat the learner had already renamed.
  test "does not rename a chat that already has a name" do
    message = @conversation.messages.create!(role: "user", content: "Something else entirely")

    @conversation.name_after(message)

    assert_equal "Talking about cats", @conversation.reload.title
  end

  test "a name longer than the limit is refused" do
    @conversation.title = "a" * (Conversation::MAX_TITLE_LENGTH + 1)

    assert_not @conversation.valid?
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
end
