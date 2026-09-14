class Flashcard < ApplicationRecord
  belongs_to :conversation, optional: true
  belongs_to :deck, optional: true

  validates :question, presence: true
  validates :answer, presence: true

  # --- ownership ------------------------------------------------------------

  # A card reaches its owner through either association, and cards exist with
  # only one of them: seeded cards have a deck and no conversation, while a
  # card built from a chat has both. Everything that asks "whose card is this?"
  # goes through here, so the answer can't differ between screens -- it used to,
  # and cards with no conversation were invisible in the index while showing up
  # in their deck.
  scope :for_user, lambda { |user|
    left_joins(:deck, :conversation)
      .where("decks.user_id = :uid OR conversations.user_id = :uid", uid: user.id)
  }

  # --- spaced repetition ----------------------------------------------------

  # SM-2, reduced to three self-graded answers. Anki's six-point scale asks for
  # a confidence judgement beginners can't make reliably.
  GRADES = %w[again good easy].freeze

  STARTING_EASE = 2.5
  # Below this a card would come back so often it stops being a review and
  # starts being a wall.
  MINIMUM_EASE = 1.3
  # First successful answers jump straight to these, rather than multiplying up
  # from zero.
  FIRST_GOOD_INTERVAL = 1.0
  FIRST_EASY_INTERVAL = 4.0
  EASY_BONUS = 1.3

  scope :due, lambda { |at = Time.current|
    where(due_at: ..at).or(where(due_at: nil))
  }

  # Never studied first, then whatever is most overdue.
  scope :in_review_order, -> { order(Arel.sql("due_at IS NOT NULL, due_at ASC, created_at ASC")) }

  def studied?
    review_count.positive?
  end

  # Records an answer and schedules the next sighting. Returns self so callers
  # can read the new due_at without reloading.
  def review!(grade)
    grade = grade.to_s
    raise ArgumentError, "unknown grade: #{grade.inspect}" unless GRADES.include?(grade)

    apply(grade)
    self.last_reviewed_at = Time.current
    self.due_at = last_reviewed_at + interval_days.days
    self.review_count += 1
    save!
    self
  end

  private

  def apply(grade)
    case grade
    when "again" then forgot
    when "good"  then self.interval_days = studied? ? interval_days * ease : FIRST_GOOD_INTERVAL
    when "easy"  then recalled_easily
    end
  end

  # Straight back into today's queue, and the card gets harder to graduate:
  # a card you keep missing should keep coming back.
  def forgot
    self.interval_days = 0.0
    self.ease = [ease - 0.2, MINIMUM_EASE].max
    self.lapse_count += 1
  end

  def recalled_easily
    self.interval_days = studied? ? interval_days * ease * EASY_BONUS : FIRST_EASY_INTERVAL
    self.ease += 0.15
  end
end
