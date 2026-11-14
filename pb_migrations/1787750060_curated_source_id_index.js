/// Enforce stable curated source IDs after the schema-and-seed transaction commits.
migrate((db) => {
  const dao = new Dao(db)
  const globals = dao.findCollectionByNameOrId("global_foods")
  globals.indexes.push("CREATE UNIQUE INDEX `idx_global_foods_source_id` ON `global_foods` (`source_id`) WHERE `source_id` != ''")
  dao.saveCollection(globals)
}, (db) => {
  const dao = new Dao(db)
  const globals = dao.findCollectionByNameOrId("global_foods")
  globals.indexes = globals.indexes.filter((value) => !value.includes("idx_global_foods_source_id"))
  dao.saveCollection(globals)
})
