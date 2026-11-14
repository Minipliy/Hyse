/// PocketBase 0.22.x: immutable consent receipts, reusable global brands and
/// relational named food portions. Existing text brands and serving_size stay
/// in place as compatibility snapshots for older app versions.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const globals = dao.findCollectionByNameOrId("global_foods")
  const foods = dao.findCollectionByNameOrId("user_foods")
  const relation = (name, collection, required = false, cascadeDelete = false) => new SchemaField({ name, type: "relation", required, options: { collectionId: collection.id, cascadeDelete, maxSelect: 1 } })
  const text = (name, required = false, max = 0) => new SchemaField({ name, type: "text", required, options: { min: required ? 1 : null, max: max || null, pattern: "" } })
  const select = (name, values, required = false) => new SchemaField({ name, type: "select", required, options: { maxSelect: 1, values } })

  const consents = new Collection({
    name: "user_consents", type: "base", system: false,
    listRule: '@request.auth.id != "" && user = @request.auth.id',
    viewRule: '@request.auth.id != "" && user = @request.auth.id',
    createRule: null, updateRule: null, deleteRule: null,
    schema: [
      relation("user", users, true, true), text("installation_id", true, 64),
      select("category", ["terms", "privacy_notice", "marketing_email"], true),
      new SchemaField({ name: "granted", type: "bool" }), text("document_version", true, 100),
      select("language", ["en", "de"], true), text("source", true, 80),
      new SchemaField({ name: "recorded_at", type: "date", required: true }),
      new SchemaField({ name: "revoked_at", type: "date" })
    ],
    indexes: ["CREATE INDEX `idx_user_consents_history` ON `user_consents` (`user`, `category`, `recorded_at`)"]
  })
  dao.saveCollection(consents)

  const brands = new Collection({
    name: "global_brands", type: "base", system: false,
    listRule: '@request.auth.id != "" && (status = "approved" || created_by = @request.auth.id)',
    viewRule: '@request.auth.id != "" && (status = "approved" || created_by = @request.auth.id)',
    createRule: null, updateRule: null, deleteRule: null,
    schema: [
      text("name", true, 160), text("normalized_name", true, 180), text("slug", true, 180),
      new SchemaField({ name: "aliases", type: "json" }),
      new SchemaField({ name: "logo", type: "file", options: { maxSelect: 1, maxSize: 2097152, mimeTypes: ["image/jpeg", "image/png", "image/webp"], thumbs: ["96x96", "256x256"], protected: true } }),
      select("status", ["pending", "approved", "rejected", "merged"], true),
      relation("created_by", users, true, false),
      text("reviewed_by", false, 64), new SchemaField({ name: "reviewed_at", type: "date" })
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_global_brands_normalized` ON `global_brands` (`normalized_name`)",
      "CREATE INDEX `idx_global_brands_status_name` ON `global_brands` (`status`, `name`)"
    ]
  })
  dao.saveCollection(brands)
  brands.schema.addField(relation("merged_into", brands, false, false))
  dao.saveCollection(brands)

  globals.schema.addField(relation("brand_relation", brands, false, false))
  foods.schema.addField(relation("brand_relation", brands, false, false))
  foods.schema.addField(text("portion_name", false, 120))
  foods.schema.addField(new SchemaField({ name: "portion_count", type: "number", options: { min: 0, max: null, noDecimal: false } }))
  dao.saveCollection(globals)
  dao.saveCollection(foods)

  const portions = new Collection({
    name: "food_portions", type: "base", system: false,
    listRule: '@request.auth.id != "" && ((owner = @request.auth.id) || (global_food != "" && status = "approved"))',
    viewRule: '@request.auth.id != "" && ((owner = @request.auth.id) || (global_food != "" && status = "approved"))',
    createRule: '@request.auth.id != "" && owner = @request.auth.id && user_food.user = @request.auth.id',
    updateRule: '@request.auth.id != "" && owner = @request.auth.id && user_food.user = @request.auth.id',
    deleteRule: '@request.auth.id != "" && owner = @request.auth.id && user_food.user = @request.auth.id',
    schema: [
      relation("owner", users, false, true), relation("user_food", foods, false, true), relation("global_food", globals, false, false),
      text("client_id", true, 36), text("name_key", false, 40), text("custom_name", false, 120),
      new SchemaField({ name: "amount", type: "number", required: true, options: { min: 0.0001, max: null, noDecimal: false } }),
      select("unit", ["g", "ml"], true),
      new SchemaField({ name: "gram_equivalent", type: "number", options: { min: 0.0001, max: null, noDecimal: false } }),
      new SchemaField({ name: "sort_order", type: "number", options: { min: 0, max: 10000, noDecimal: true } }),
      new SchemaField({ name: "is_default", type: "bool" }), select("status", ["private", "pending", "approved", "rejected"], true)
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_food_portions_owner_client` ON `food_portions` (`owner`, `client_id`) WHERE `owner` != ''",
      "CREATE INDEX `idx_food_portions_user_food` ON `food_portions` (`user_food`, `sort_order`)",
      "CREATE INDEX `idx_food_portions_global_food` ON `food_portions` (`global_food`, `status`, `sort_order`)"
    ]
  })
  dao.saveCollection(portions)
}, (db) => {
  const dao = new Dao(db)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("food_portions")) } catch (_) {}
  const globals = dao.findCollectionByNameOrId("global_foods")
  const foods = dao.findCollectionByNameOrId("user_foods")
  for (const collection of [globals, foods]) {
    try { collection.schema.removeField(collection.schema.getFieldByName("brand_relation").id); dao.saveCollection(collection) } catch (_) {}
  }
  for (const name of ["portion_name", "portion_count"]) { try { foods.schema.removeField(foods.schema.getFieldByName(name).id) } catch (_) {} }
  dao.saveCollection(foods)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("global_brands")) } catch (_) {}
  try { dao.deleteCollection(dao.findCollectionByNameOrId("user_consents")) } catch (_) {}
})
