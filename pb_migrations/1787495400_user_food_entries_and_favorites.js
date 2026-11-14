/// PocketBase 0.22.x: account-owned eaten foods and per-user global favorites.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const globals = dao.findCollectionByNameOrId("global_foods")
  const foods = dao.findCollectionByNameOrId("user_foods")

  foods.listRule = "user = @request.auth.id"
  foods.viewRule = "user = @request.auth.id"
  foods.createRule = '@request.auth.id != "" && user = @request.auth.id'
  foods.updateRule = "user = @request.auth.id"
  foods.deleteRule = "user = @request.auth.id"
  foods.schema.addField(new SchemaField({ name: "record_type", type: "select", options: { maxSelect: 1, values: ["saved", "entry"] } }))
  foods.schema.addField(new SchemaField({ name: "global_food", type: "relation", options: { collectionId: globals.id, cascadeDelete: false, maxSelect: 1 } }))
  foods.schema.addField(new SchemaField({ name: "amount", type: "number", options: { min: 0, max: null, noDecimal: false } }))
  foods.schema.addField(new SchemaField({ name: "meal", type: "text", options: { min: null, max: 120, pattern: "" } }))
  foods.schema.addField(new SchemaField({ name: "category_id", type: "text", options: { min: null, max: 36, pattern: "" } }))
  foods.schema.addField(new SchemaField({ name: "eaten_at", type: "date" }))
  foods.schema.addField(new SchemaField({ name: "added_sugar", type: "number", options: { min: 0, max: null, noDecimal: false } }))
  foods.schema.addField(new SchemaField({ name: "fruit_sugar", type: "number", options: { min: 0, max: null, noDecimal: false } }))
  for (const name of ["kcal_per_100g", "carbs_per_100g", "protein_per_100g", "fat_per_100g", "added_sugar_per_100g", "fruit_sugar_per_100g", "fiber_per_100g", "saturated_fat_per_100g", "salt_per_100g"]) {
    foods.schema.addField(new SchemaField({ name, type: "number", options: { min: 0, max: null, noDecimal: false } }))
  }
  foods.indexes = [
    "CREATE UNIQUE INDEX `idx_user_foods_user_client` ON `user_foods` (`user`, `client_id`)",
    "CREATE INDEX `idx_user_foods_user_name` ON `user_foods` (`user`, `name`)",
    "CREATE INDEX `idx_user_foods_user_type_date` ON `user_foods` (`user`, `record_type`, `eaten_at`)"
  ]
  dao.saveCollection(foods)

  const favorites = new Collection({
    name: "user_favorites", type: "base", system: false,
    listRule: "user = @request.auth.id", viewRule: "user = @request.auth.id",
    createRule: '@request.auth.id != "" && user = @request.auth.id',
    updateRule: "user = @request.auth.id", deleteRule: "user = @request.auth.id",
    schema: [
      new SchemaField({ name: "user", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "global_food", type: "relation", required: true, options: { collectionId: globals.id, cascadeDelete: true, maxSelect: 1 } })
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_user_favorites_user_global` ON `user_favorites` (`user`, `global_food`)"]
  })
  dao.saveCollection(favorites)

  // Preserve entries created by older app versions while moving the source of truth.
  try {
    const legacyEntries = dao.findRecordsByFilter("food_entries", "id != \x27\x27", "", 0, 0)
    for (const legacy of legacyEntries) {
      const user = String(legacy.get("user") || "")
      const client = String(legacy.get("client_id") || "")
      if (!user || !client) continue
      try {
        dao.findFirstRecordByFilter("user_foods", "user = \x27" + user + "\x27 && client_id = \x27" + client + "\x27")
        continue
      } catch (_) {}
      const record = new Record(foods)
      for (const name of ["name", "calories", "carbs", "protein", "fat", "unit", "category_id", "kcal_per_100g", "carbs_per_100g", "protein_per_100g", "fat_per_100g", "added_sugar_per_100g", "fruit_sugar_per_100g", "fiber_per_100g", "saturated_fat_per_100g", "salt_per_100g"]) record.set(name, legacy.get(name))
      record.set("user", user)
      record.set("client_id", client)
      record.set("record_type", "entry")
      record.set("amount", legacy.get("amount_g"))
      record.set("meal", legacy.get("category"))
      record.set("eaten_at", legacy.get("eaten_at"))
      record.set("global_food", legacy.get("food"))
      record.set("sugar", Number(legacy.get("added_sugar_per_100g") || 0) + Number(legacy.get("fruit_sugar_per_100g") || 0))
      record.set("fiber", legacy.get("fiber_per_100g"))
      record.set("saturated_fat", legacy.get("saturated_fat_per_100g"))
      record.set("salt", legacy.get("salt_per_100g"))
      dao.saveRecord(record)
    }
  } catch (_) {}

  globals.listRule = '@request.auth.id != ""'
  globals.viewRule = '@request.auth.id != ""'
  globals.createRule = null
  globals.updateRule = null
  globals.deleteRule = null
  dao.saveCollection(globals)
}, (db) => {
  const dao = new Dao(db)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("user_favorites")) } catch (_) {}
  const foods = dao.findCollectionByNameOrId("user_foods")
  for (const name of ["record_type", "global_food", "amount", "meal", "category_id", "eaten_at", "added_sugar", "fruit_sugar", "kcal_per_100g", "carbs_per_100g", "protein_per_100g", "fat_per_100g", "added_sugar_per_100g", "fruit_sugar_per_100g", "fiber_per_100g", "saturated_fat_per_100g", "salt_per_100g"]) {
    try { foods.schema.removeField(foods.schema.getFieldByName(name).id) } catch (_) {}
  }
  foods.indexes = [
    "CREATE UNIQUE INDEX `idx_user_foods_user_client` ON `user_foods` (`user`, `client_id`)",
    "CREATE INDEX `idx_user_foods_user_name` ON `user_foods` (`user`, `name`)"
  ]
  dao.saveCollection(foods)
})
