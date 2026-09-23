class RemoveLocaleFromUsers < ActiveRecord::Migration[8.0]
  # The app is English-only, so a per-user interface language has nothing left
  # to select. Reversible: rolling back restores the column, empty -- the
  # choices themselves are not recoverable from here.
  def change
    remove_column :users, :locale, :string
  end
end
