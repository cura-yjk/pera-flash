class AddLocaleToUsers < ActiveRecord::Migration[8.1]
  def change
    # Null means "follow the browser". Only set once someone picks a language,
    # so a learner whose browser is in Korean gets Korean without being asked,
    # and an explicit choice is never overridden by a different device.
    add_column :users, :locale, :string
  end
end
