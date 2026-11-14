/// Keep authenticated barcode lookups fast with a large approved catalogue.
migrate((db) => {
  const dao = new Dao(db)
  const collection = dao.findCollectionByNameOrId("global_foods")
  collection.indexes = collection.indexes.filter((value) => !value.includes("idx_global_foods_barcode_lookup"))
  collection.indexes.push("CREATE INDEX `idx_global_foods_barcode_lookup` ON `global_foods` (`barcode_normalized`, `moderation_status`)")
  dao.saveCollection(collection)
}, (db) => {
  const dao = new Dao(db)
  const collection = dao.findCollectionByNameOrId("global_foods")
  collection.indexes = collection.indexes.filter((value) => !value.includes("idx_global_foods_barcode_lookup"))
  dao.saveCollection(collection)
})
