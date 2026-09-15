# Devise's lockable columns. Sign-up is open and there was nothing stopping
# someone working through a password list against a known email address.
#
# No unlock_token column: unlocking is on a timer rather than by email, because
# this app has no SMTP configured -- an unlock email would simply never arrive,
# and a lock nobody can lift is worse than no lock.
class AddLockableToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.integer :failed_attempts, default: 0, null: false
      t.datetime :locked_at
    end

    add_index :users, :locked_at
  end
end
