class CreateFlashcards < ActiveRecord::Migration[8.1]
  def change
    create_table :flashcards do |t|
      t.string :question
      t.string :answer
      t.references :conversation, foreign_key: true
      t.references :deck, foreign_key: true

      t.timestamps
    end
  end
end
