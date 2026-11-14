/// PocketBase 0.22.x: moderated user submissions for the shared food catalogue.
migrate((db) => {
  const dao = new Dao(db)
  const globals = dao.findCollectionByNameOrId("global_foods")
  const users = dao.findCollectionByNameOrId("users")

  globals.schema.addField(new SchemaField({ name: "brand", type: "text", options: { min: null, max: 160, pattern: "" } }))
  globals.schema.addField(new SchemaField({ name: "unit", type: "select", options: { maxSelect: 1, values: ["g", "ml"] } }))
  globals.schema.addField(new SchemaField({ name: "serving_size", type: "number", options: { min: 0, max: null, noDecimal: false } }))
  for (const name of ["sugar", "fiber", "saturated_fat", "salt"]) {
    globals.schema.addField(new SchemaField({ name, type: "number", options: { min: 0, max: null, noDecimal: false } }))
  }
  globals.schema.addField(new SchemaField({ name: "creator", type: "relation", options: { collectionId: users.id, cascadeDelete: false, maxSelect: 1 } }))
  globals.schema.addField(new SchemaField({ name: "source", type: "select", options: { maxSelect: 1, values: ["seed", "user", "open_food_facts"] } }))
  globals.schema.addField(new SchemaField({ name: "moderation_status", type: "select", options: { maxSelect: 1, values: ["pending", "approved", "rejected"] } }))
  globals.schema.addField(new SchemaField({ name: "normalized_key", type: "text", options: { min: null, max: 500, pattern: "" } }))
  globals.listRule = '@request.auth.id != "" && (moderation_status = "approved" || moderation_status = "" || creator = @request.auth.id)'
  globals.viewRule = globals.listRule
  globals.createRule = null
  globals.updateRule = null
  globals.deleteRule = null
  globals.indexes = [
    "CREATE INDEX `idx_global_foods_name` ON `global_foods` (`name`)",
    "CREATE INDEX `idx_global_foods_barcode` ON `global_foods` (`barcode`) WHERE `barcode` != ''",
    "CREATE UNIQUE INDEX `idx_global_foods_normalized_key` ON `global_foods` (`normalized_key`) WHERE `normalized_key` != ''",
    "CREATE INDEX `idx_global_foods_moderation` ON `global_foods` (`moderation_status`, `creator`)"
  ]
  dao.saveCollection(globals)
}, (db) => {
  const dao = new Dao(db)
  const globals = dao.findCollectionByNameOrId("global_foods")
  for (const name of ["brand", "unit", "serving_size", "sugar", "fiber", "saturated_fat", "salt", "creator", "source", "moderation_status", "normalized_key"]) {
    try { globals.schema.removeField(globals.schema.getFieldByName(name).id) } catch (_) {}
  }
  globals.indexes = [
    "CREATE INDEX `idx_global_foods_name` ON `global_foods` (`name`)",
    "CREATE INDEX `idx_global_foods_barcode` ON `global_foods` (`barcode`) WHERE `barcode` != ''"
  ]
  dao.saveCollection(globals)
})
