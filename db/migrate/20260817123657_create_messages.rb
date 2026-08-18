class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.text :content
      t.string :role

      t.timestamps
    end
    # Compount index for fast ordered fetching of chat history
    add_index :messages, [:conversation_id, :created_at]
  end
end
