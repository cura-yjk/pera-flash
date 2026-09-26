require "test_helper"

# Only the seeding is tested: running the lab is a real request per case,
# which is the point of it and exactly what the suite must never do.
class PromptLabTest < ActiveSupport::TestCase
  test "seeds every case as a chat of its own" do
    learner = PromptLab.seed!

    assert_equal PromptLab::CASES.map { |c| c[:title] }.sort, learner.conversations.pluck(:title).sort
    PromptLab::CASES.each do |kase|
      conversation = learner.conversations.find_by!(title: kase[:title])
      assert_equal kase[:messages].map(&:last), conversation.messages.order(:created_at).pluck(:content),
                   "#{kase[:title]}: messages out of order"
    end
  end

  test "the long chat is longer than generation will read" do
    long = PromptLab::CASES.find { |c| c[:title].start_with?("Long chat") }

    assert_operator long[:messages].size, :>, Conversation::FLASHCARD_MESSAGE_LIMIT
  end

  test "seeding again replaces the lab learner's data instead of adding to it" do
    PromptLab.seed!
    learner = PromptLab.seed!

    assert_equal PromptLab::CASES.size, learner.conversations.count
    assert_equal PromptLab::DECK[:cards].size, Flashcard.for_user(learner).count
  end

  # db/seeds.rb deletes everyone; this must not.
  test "leaves every other learner's chats, decks and cards alone" do
    other = users(:learner)
    before = [ other.conversations.count, other.decks.count, Flashcard.for_user(other).count ]

    PromptLab.seed!

    assert_equal before, [ other.conversations.count, other.decks.count, Flashcard.for_user(other).count ]
  end
end
