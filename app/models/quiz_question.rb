# One multiple-choice question: a card, plus wrong answers drawn from other
# cards the learner owns.
#
# Not an ActiveRecord model -- a quiz question has no life beyond the moment
# it is asked. The card carries all the state that outlasts it.
#
# Distractors come from real cards rather than being generated, which keeps a
# quiz free and offline like the review flow, and makes the wrong answers
# plausibly confusable: they are the same learner's material on the same topic.
class QuizQuestion
  OPTION_COUNT = 4

  attr_reader :card

  def initialize(card, pool:)
    @card = card
    @pool = pool
  end

  # The correct answer among distractors, in a stable shuffled order so the
  # position does not move between rendering the question and grading it.
  def options
    @options ||= ([card.answer] + distractors).shuffle
  end

  def correct?(choice)
    choice.to_s == card.answer
  end

  # A quiz needs something to choose between. With only one option there is no
  # question -- the caller falls back to a plain review instead.
  def answerable?
    options.size > 1
  end

  private

  # Distinct answers only: two cards that happen to share an answer would put
  # the same text in two places, and one of them would be marked wrong.
  def distractors
    @pool.map(&:answer)
         .uniq
         .reject { |answer| answer == card.answer }
         .sample(OPTION_COUNT - 1)
  end
end
