/// FTS5 index for a large multilingual global food catalogue.
migrate((db) => {
  db.newQuery("CREATE VIRTUAL TABLE IF NOT EXISTS global_foods_fts USING fts5(record_id UNINDEXED, name, name_de, brand, tokenize='unicode61 remove_diacritics 2', prefix='2 3 4')").execute()
  db.newQuery("DELETE FROM global_foods_fts").execute()
  db.newQuery("INSERT INTO global_foods_fts(record_id,name,name_de,brand) SELECT id,coalesce(name,''),coalesce(name_de,''),coalesce(brand,'') FROM global_foods WHERE moderation_status='approved'").execute()
  db.newQuery("CREATE TRIGGER IF NOT EXISTS global_foods_fts_insert AFTER INSERT ON global_foods WHEN new.moderation_status='approved' BEGIN INSERT INTO global_foods_fts(record_id,name,name_de,brand) VALUES(new.id,coalesce(new.name,''),coalesce(new.name_de,''),coalesce(new.brand,'')); END").execute()
  db.newQuery("CREATE TRIGGER IF NOT EXISTS global_foods_fts_delete AFTER DELETE ON global_foods BEGIN DELETE FROM global_foods_fts WHERE record_id=old.id; END").execute()
  db.newQuery("CREATE TRIGGER IF NOT EXISTS global_foods_fts_update AFTER UPDATE ON global_foods BEGIN DELETE FROM global_foods_fts WHERE record_id=old.id; INSERT INTO global_foods_fts(record_id,name,name_de,brand) SELECT new.id,coalesce(new.name,''),coalesce(new.name_de,''),coalesce(new.brand,'') WHERE new.moderation_status='approved'; END").execute()
}, (db) => {
  db.newQuery("DROP TRIGGER IF EXISTS global_foods_fts_update").execute()
  db.newQuery("DROP TRIGGER IF EXISTS global_foods_fts_delete").execute()
  db.newQuery("DROP TRIGGER IF EXISTS global_foods_fts_insert").execute()
  db.newQuery("DROP TABLE IF EXISTS global_foods_fts").execute()
})
