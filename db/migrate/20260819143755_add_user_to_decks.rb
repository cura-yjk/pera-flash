class AddUserToDecks < ActiveRecord::Migration[8.1]
  def change
    add_reference :decks, :user, null: false, foreign_key: true
  end
end
