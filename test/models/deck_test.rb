require "test_helper"

class DeckTest < ActiveSupport::TestCase
  setup do
    @user = users(:learner)
    @deck = decks(:starter)
  end

  test "needs a name" do
    deck = @user.decks.new(name: "")

    assert_not deck.valid?
    assert_includes deck.errors[:name], "can't be blank"
  end

  test "belongs to someone" do
    assert_not Deck.new(name: "Ownerless").valid?
  end

  test "takes its cards with it when it goes" do
    @deck.flashcards.create!(question: "What does 猫 mean?", answer: "Cat")

    assert_difference -> { Flashcard.count }, -1 do
      @deck.destroy!
    end
  end

  # --- with_card_counts -----------------------------------------------------
  #
  # The count rides along on the row so that rendering a list of decks does not
  # fire a COUNT per deck.

  test "carries the card count on the row" do
    2.times { |i| @deck.flashcards.create!(question: "Q#{i}", answer: "A#{i}") }

    row = Deck.with_card_counts(@user).find(@deck.id)

    assert_equal 2, row.flashcards_count.to_i
  end

  test "counts a deck with no cards as zero rather than dropping it" do
    empty = @user.decks.create!(name: "Nothing in here yet")

    row = Deck.with_card_counts(@user).find(empty.id)

    assert_equal 0, row.flashcards_count.to_i
  end

  test "newest first" do
    older = @user.decks.create!(name: "Older deck", created_at: 2.days.ago)
    newer = @user.decks.create!(name: "Newer deck", created_at: 1.minute.ago)

    ordered = Deck.with_card_counts(@user).to_a

    assert_operator ordered.index(newer), :<, ordered.index(older)
  end

  test "is one learner's decks only" do
    stranger_deck = users(:other).decks.create!(name: "Somebody else's deck")

    assert_not_includes Deck.with_card_counts(@user), stranger_deck
  end
end
