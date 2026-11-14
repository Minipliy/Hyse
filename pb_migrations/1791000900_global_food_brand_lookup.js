/// Keep the initial brand list fast even when the global food catalogue grows.
migrate((db) => {
  db.newQuery("CREATE INDEX IF NOT EXISTS idx_global_foods_approved_brand ON global_foods (brand COLLATE NOCASE) WHERE moderation_status = 'approved' AND brand != ''").execute()
}, (db) => {
  db.newQuery("DROP INDEX IF EXISTS idx_global_foods_approved_brand").execute()
})
