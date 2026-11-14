/// Metadata-only updates must not rebuild the full-text search entry.
/// Run before the provenance backfill, including on existing installations.
migrate((db) => {
  db.newQuery("DROP TRIGGER IF EXISTS global_foods_fts_update").execute()
  db.newQuery("CREATE TRIGGER global_foods_fts_update AFTER UPDATE ON global_foods " +
    "WHEN old.id IS NOT new.id OR old.name IS NOT new.name OR old.name_de IS NOT new.name_de OR old.brand IS NOT new.brand OR old.moderation_status IS NOT new.moderation_status " +
    "BEGIN DELETE FROM global_foods_fts WHERE record_id=old.id; " +
    "INSERT INTO global_foods_fts(record_id,name,name_de,brand) SELECT new.id,coalesce(new.name,''),coalesce(new.name_de,''),coalesce(new.brand,'') WHERE new.moderation_status='approved'; END").execute()
}, (db) => {
  db.newQuery("DROP TRIGGER IF EXISTS global_foods_fts_update").execute()
  db.newQuery("CREATE TRIGGER global_foods_fts_update AFTER UPDATE ON global_foods " +
    "BEGIN DELETE FROM global_foods_fts WHERE record_id=old.id; " +
    "INSERT INTO global_foods_fts(record_id,name,name_de,brand) SELECT new.id,coalesce(new.name,''),coalesce(new.name_de,''),coalesce(new.brand,'') WHERE new.moderation_status='approved'; END").execute()
})
