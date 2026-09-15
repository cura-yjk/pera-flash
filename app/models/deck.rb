class Deck < ApplicationRecord
  belongs_to :user
  has_many :flashcards, dependent: :destroy

  validates :name, presence: true

  # Newest first, with the card count already on each row so a list of decks
  # does not fire a COUNT per deck while rendering.
  scope :with_card_counts, lambda { |user|
    where(user: user)
      .left_joins(:flashcards)
      .select("decks.*, COUNT(flashcards.id) AS flashcards_count")
      .group("decks.id")
      .order(created_at: :desc)
  }
end
