require "test_helper"

class KnownCardsTest < ActiveSupport::TestCase
  setup do
    @user = users(:learner)
    @deck = @user.decks.create!(name: "Animals")
  end

  test "finds a card with the same front" do
    card = @deck.flashcards.create!(question: "猫[ねこ]", answer: "cat")

    assert_equal card, KnownCards.new(@user).match("猫[ねこ]")
  end

  # Readings are annotation, not part of the word: a card written before
  # furigana, or with the reading left off, is still the same card.
  test "ignores readings, spacing and punctuation" do
    card = @deck.flashcards.create!(question: "猫[ねこ]が 好[す]きです。", answer: "I like cats")

    assert_equal card, KnownCards.new(@user).match("猫が好きです")
    assert_equal card, KnownCards.new(@user).match("〜猫[ねこ]が好[す]きです！")
  end

  # Cards made before the fronts became Japanese carried the Japanese on the
  # back ("How do you say cat?" / 猫[ねこ]), so that is where to look for it.
  test "finds an old-style card by its answer" do
    card = @deck.flashcards.create!(question: "How do you say cat?", answer: "猫[ねこ]")

    assert_equal card, KnownCards.new(@user).match("猫")
  end

  test "does not match a card that only shares a word" do
    @deck.flashcards.create!(question: "猫[ねこ]", answer: "cat")

    assert_nil KnownCards.new(@user).match("猫[ねこ]が好[す]きです")
  end

  test "remembers what it has been told about since, so a batch cannot repeat itself" do
    known = KnownCards.new(@user)
    first = @deck.flashcards.build(question: "犬[いぬ]", answer: "dog")
    known.add(first)

    assert_equal first, known.match("犬")
  end

  test "never matches an empty front" do
    @deck.flashcards.create!(question: "。", answer: "full stop")

    assert_nil KnownCards.new(@user).match("")
    assert_nil KnownCards.new(@user).match("  ")
  end

  test "leaves another learner's cards out" do
    users(:other).decks.create!(name: "Theirs").flashcards.create!(question: "鳥[とり]", answer: "bird")

    assert_nil KnownCards.new(@user).match("鳥")
  end
end
