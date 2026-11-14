/// PocketBase 0.22.x: completes the account-owned, offline-first food schema.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const globals = dao.findCollectionByNameOrId("global_foods")

  globals.listRule = '@request.auth.id != ""'
  globals.viewRule = '@request.auth.id != ""'
  globals.createRule = null
  globals.updateRule = null
  globals.deleteRule = null
  globals.indexes = [
    "CREATE INDEX `idx_global_foods_name` ON `global_foods` (`name`)",
    "CREATE INDEX `idx_global_foods_barcode` ON `global_foods` (`barcode`) WHERE `barcode` != ''"
  ]
  dao.saveCollection(globals)

  const entries = dao.findCollectionByNameOrId("food_entries")
  entries.listRule = "user = @request.auth.id"
  entries.viewRule = "user = @request.auth.id"
  entries.createRule = '@request.auth.id != "" && user = @request.auth.id'
  entries.updateRule = "user = @request.auth.id"
  entries.deleteRule = "user = @request.auth.id"
  const userField = entries.schema.getFieldByName("user")
  userField.required = true
  userField.options.cascadeDelete = true
  const requiredExisting = ["name", "calories", "carbs", "protein", "fat", "amount_g", "eaten_at", "category"]
  for (const name of requiredExisting) entries.schema.getFieldByName(name).required = true
  entries.schema.addField(new SchemaField({ name: "food", type: "relation", options: { collectionId: globals.id, cascadeDelete: false, maxSelect: 1 } }))
  entries.schema.addField(new SchemaField({ name: "client_id", type: "text", required: true, options: { min: 36, max: 36, pattern: "" } }))
  entries.schema.addField(new SchemaField({ name: "category_id", type: "text", required: true, options: { min: 36, max: 36, pattern: "" } }))
  entries.schema.addField(new SchemaField({ name: "unit", type: "select", required: true, options: { maxSelect: 1, values: ["g", "ml"] } }))
  for (const name of ["kcal_per_100g", "carbs_per_100g", "protein_per_100g", "fat_per_100g", "added_sugar_per_100g", "fruit_sugar_per_100g", "fiber_per_100g", "saturated_fat_per_100g", "salt_per_100g"]) {
    entries.schema.addField(new SchemaField({ name, type: "number", required: true, options: { min: 0, max: null, noDecimal: false } }))
  }
  entries.indexes = [
    "CREATE UNIQUE INDEX `idx_food_entries_user_client` ON `food_entries` (`user`, `client_id`)",
    "CREATE INDEX `idx_food_entries_user_eaten` ON `food_entries` (`user`, `eaten_at`)"
  ]
  dao.saveCollection(entries)

  const personal = new Collection({
    name: "user_foods", type: "base", system: false,
    listRule: "user = @request.auth.id", viewRule: "user = @request.auth.id",
    createRule: '@request.auth.id != "" && user = @request.auth.id',
    updateRule: "user = @request.auth.id", deleteRule: "user = @request.auth.id",
    schema: [
      new SchemaField({ name: "user", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "client_id", type: "text", required: true, options: { min: 36, max: 36, pattern: "" } }),
      new SchemaField({ name: "name", type: "text", required: true, options: { min: 1, max: 200, pattern: "" } }),
      new SchemaField({ name: "calories", type: "number", required: true, options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "carbs", type: "number", required: true, options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "protein", type: "number", required: true, options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "fat", type: "number", required: true, options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "sugar", type: "number", required: true, options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "fiber", type: "number", required: true, options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "saturated_fat", type: "number", required: true, options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "salt", type: "number", required: true, options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "barcode", type: "text", options: { min: null, max: 80, pattern: "" } }),
      new SchemaField({ name: "unit", type: "select", required: true, options: { maxSelect: 1, values: ["g", "ml"] } }),
      new SchemaField({ name: "serving_size", type: "number", options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "is_favorite", type: "bool" }),
      new SchemaField({ name: "is_fruit", type: "bool" })
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_user_foods_user_client` ON `user_foods` (`user`, `client_id`)",
      "CREATE INDEX `idx_user_foods_user_name` ON `user_foods` (`user`, `name`)"
    ]
  })
  dao.saveCollection(personal)
}, (db) => {
  const dao = new Dao(db)
  const personal = dao.findCollectionByNameOrId("user_foods")
  dao.deleteCollection(personal)
})
