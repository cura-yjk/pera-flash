require "test_helper"

class QuizQuestionTest < ActiveSupport::TestCase
  setup do
    @deck = decks(:starter)
    @card = @deck.flashcards.create!(question: "What does 猫 mean?", answer: "Cat")
    @pool = 5.times.map { |i| @deck.flashcards.create!(question: "Q#{i}", answer: "Wrong #{i}") }
  end

  test "offers the correct answer among distractors" do
    options = QuizQuestion.new(@card, pool: @pool).options

    assert_equal QuizQuestion::OPTION_COUNT, options.size
    assert_includes options, "Cat"
  end

  test "distractors come from other cards, never the answer itself" do
    options = QuizQuestion.new(@card, pool: @pool).options

    assert_equal 1, options.count("Cat"), "the answer must appear exactly once"
    assert((options - ["Cat"]).all? { |o| o.start_with?("Wrong") })
  end

  # Position must not move between rendering and grading.
  test "the order is stable once asked" do
    question = QuizQuestion.new(@card, pool: @pool)

    assert_equal question.options, question.options
  end

  test "grades the correct choice" do
    question = QuizQuestion.new(@card, pool: @pool)

    assert question.correct?("Cat")
    assert_not question.correct?("Wrong 1")
  end

  # Two cards sharing an answer would put the same text in two places, and one
  # of them would be marked wrong.
  test "never repeats an answer among the options" do
    duplicates = 5.times.map { @deck.flashcards.create!(question: "dup", answer: "Same") }

    options = QuizQuestion.new(@card, pool: duplicates).options

    assert_equal options.uniq, options
  end

  test "is not answerable when there is nothing to choose between" do
    assert_not QuizQuestion.new(@card, pool: []).answerable?
  end

  test "works with fewer distractors than a full set" do
    question = QuizQuestion.new(@card, pool: @pool.first(1))

    assert question.answerable?
    assert_equal 2, question.options.size
  end
end
