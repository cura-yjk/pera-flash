class AddShowFuriganaToUsers < ActiveRecord::Migration[8.0]
  def change
    # Readings on by default: a beginner who cannot read the kanji is stuck
    # without them. Turning them off is how you test yourself later.
    add_column :users, :show_furigana, :boolean, default: true, null: false
  end
end
