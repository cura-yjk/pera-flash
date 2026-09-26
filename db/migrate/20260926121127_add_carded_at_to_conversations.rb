# When cards were last saved from a conversation, whether or not any were new.
#
# "What is new since the last batch" used to key off the newest card's
# created_at, which has two holes: a save whose cards were all duplicates
# (and so all skipped) left nothing to key off, and the "✅ N cards added"
# confirmation, written after the cards, always counted as new material.
# Nullable and unfilled: a conversation without it falls back to its cards,
# and the old code, on a rollback, ignores the column.
class AddCardedAtToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :carded_at, :datetime
  end
end
