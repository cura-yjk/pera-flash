# Solid Cache's table, created as a migration rather than left to
# db/cache_schema.rb.
#
# Every database in config/database.yml points at the same DATABASE_URL here,
# so the cache table lives in the primary database and the primary schema
# should own it. The release phase runs db:migrate, which never loads
# cache_schema.rb -- so production had no solid_cache_entries at all.
#
# That was not a dormant problem. Rails.cache backs the controller rate limits,
# and SolidCache's failsafe only swallows timeouts and disconnects, not the
# StatementInvalid a missing table raises: the first message anyone sent after
# rate limiting shipped would have 500'd.
class CreateSolidCacheEntries < ActiveRecord::Migration[8.1]
  def change
    return if table_exists?(:solid_cache_entries)

    create_table :solid_cache_entries do |t|
      t.binary :key, limit: 1024, null: false
      t.binary :value, limit: 536_870_912, null: false
      t.datetime :created_at, null: false
      t.integer :key_hash, limit: 8, null: false
      t.integer :byte_size, limit: 4, null: false

      t.index :byte_size
      t.index %i[key_hash byte_size]
      t.index :key_hash, unique: true
    end
  end
end
