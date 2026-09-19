require "test_helper"

# Mostly Devise, which is not ours to test. What is ours: the account is the
# owner of everything in the app, so closing one has to take the whole of it --
# :registerable means a learner can do that to themselves from the account page.
class UserTest < ActiveSupport::TestCase
  setup { @user = users(:learner) }

  test "an email belongs to one account" do
    duplicate = User.new(email: @user.email, password: "password123")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], "has already been taken"
  end

  test "closing an account takes its conversations" do
    user = User.create!(email: "closing@example.com", password: "password123")
    user.conversations.create!(title: "A chat")

    assert_difference -> { Conversation.count }, -1 do
      user.destroy!
    end
  end

  test "closing an account takes its messages with the conversation" do
    user = User.create!(email: "closing-messages@example.com", password: "password123")
    conversation = user.conversations.create!(title: "A chat")
    conversation.messages.create!(role: "user", content: "こんにちは")

    assert_difference -> { Message.count }, -1 do
      user.destroy!
    end
  end

  test "closing an account takes its decks" do
    user = User.create!(email: "closing-decks@example.com", password: "password123")
    user.decks.create!(name: "A deck")

    assert_difference -> { Deck.count }, -1 do
      user.destroy!
    end
  end

  test "closing an account takes the cards in those decks" do
    user = User.create!(email: "closing-cards@example.com", password: "password123")
    deck = user.decks.create!(name: "A deck")
    deck.flashcards.create!(question: "What does 猫 mean?", answer: "Cat")

    assert_difference -> { Flashcard.count }, -1 do
      user.destroy!
    end
  end

  # The card above has a deck but no conversation. Every card the app actually
  # makes has both -- flashcards#create builds them through the conversation --
  # and conversations are destroyed before decks, while their cards still exist.
  test "closing an account takes a card made the way the app makes them" do
    user = User.create!(email: "closing-real-card@example.com", password: "password123")
    conversation = user.conversations.create!(title: "A chat")
    deck = user.decks.create!(name: "A deck")
    conversation.flashcards.create!(question: "What does 猫 mean?", answer: "Cat", deck: deck)

    assert_difference -> { Flashcard.count }, -1 do
      user.destroy!
    end
  end

  test "one learner's account is not another's" do
    assert_not_equal users(:other).id, @user.id
    assert_empty User.where(email: @user.email).where.not(id: @user.id)
  end
end
