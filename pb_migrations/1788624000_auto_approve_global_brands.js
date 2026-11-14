/// Brands are catalogue metadata and become globally available immediately.
/// Promote proposals created before the automatic-publication workflow.
migrate((db) => {
  const dao = new Dao(db)
  const marker = "automatic_global_brand_migration"
  const records = dao.findRecordsByFilter("global_brands", "status = 'pending'", "", 0, 0)
  for (const record of records) {
    record.set("status", "approved")
    record.set("reviewed_by", marker)
    record.set("reviewed_at", new Date().toISOString())
    dao.saveRecord(record)
  }
}, (db) => {
  const dao = new Dao(db)
  const marker = "automatic_global_brand_migration"
  const records = dao.findRecordsByFilter("global_brands", "status = 'approved' && reviewed_by = {:marker}", "", 0, 0, { marker })
  for (const record of records) {
    record.set("status", "pending")
    record.set("reviewed_by", "")
    record.set("reviewed_at", "")
    dao.saveRecord(record)
  }
})
