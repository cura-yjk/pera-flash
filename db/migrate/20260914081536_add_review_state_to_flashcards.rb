class AddReviewStateToFlashcards < ActiveRecord::Migration[8.0]
  def change
    # Spaced-repetition state. A card is due when due_at has passed; a card
    # that has never been studied has due_at nil and sorts first.
    add_column :flashcards, :due_at, :datetime
    add_column :flashcards, :last_reviewed_at, :datetime

    # Days until the next review, and the per-card multiplier that grows it.
    # Ease starts at SM-2's 2.5 and is pushed down by cards you keep missing.
    add_column :flashcards, :interval_days, :float, default: 0.0, null: false
    add_column :flashcards, :ease, :float, default: 2.5, null: false

    add_column :flashcards, :review_count, :integer, default: 0, null: false
    add_column :flashcards, :lapse_count, :integer, default: 0, null: false

    # The query every review screen runs: this deck's cards, soonest due first.
    add_index :flashcards, [ :deck_id, :due_at ]
  end
end
