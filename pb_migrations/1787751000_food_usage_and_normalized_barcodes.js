/// Server-owned, reconstructable food usage plus canonical barcode storage.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const globals = dao.findCollectionByNameOrId("global_foods")
  const foods = dao.findCollectionByNameOrId("user_foods")

  const add = (collection, field) => {
    if (!collection.schema.getFieldByName(field.name)) collection.schema.addField(new SchemaField(field))
  }

  add(globals, { name: "barcode_raw", type: "text", options: { min: null, max: 80, pattern: "" } })
  add(globals, { name: "barcode_normalized", type: "text", options: { min: null, max: 14, pattern: "^[0-9]{0,14}$" } })
  dao.saveCollection(globals)

  for (const field of [
    { name: "barcode_raw", type: "text", options: { min: null, max: 80, pattern: "" } },
    { name: "barcode_normalized", type: "text", options: { min: null, max: 14, pattern: "^[0-9]{0,14}$" } },
    { name: "source_type", type: "select", options: { maxSelect: 1, values: ["global_food", "user_food", "recipe", "external_food", "local_guest_food"] } },
    { name: "source_key", type: "text", options: { min: null, max: 240, pattern: "" } },
    { name: "source_food_client_id", type: "text", options: { min: null, max: 36, pattern: "" } },
    { name: "external_source", type: "text", options: { min: null, max: 80, pattern: "" } },
    { name: "external_source_id", type: "text", options: { min: null, max: 160, pattern: "" } },
    { name: "external_fetched_at", type: "date" },
    { name: "portion_id", type: "text", options: { min: null, max: 36, pattern: "" } }
  ]) add(foods, field)
  dao.saveCollection(foods)

  const usage = new Collection({
    name: "user_food_usage", type: "base", system: false,
    listRule: "user = @request.auth.id", viewRule: "user = @request.auth.id",
    // Only hooks and the authenticated rebuild route may mutate aggregates.
    createRule: null, updateRule: null, deleteRule: null,
    schema: [
      new SchemaField({ name: "user", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "source_key", type: "text", required: true, options: { min: 1, max: 240, pattern: "" } }),
      new SchemaField({ name: "source", type: "select", required: true, options: { maxSelect: 1, values: ["global_food", "user_food", "recipe", "external_food", "local_guest_food"] } }),
      new SchemaField({ name: "food_id", type: "text", options: { min: null, max: 160, pattern: "" } }),
      new SchemaField({ name: "client_item_id", type: "text", options: { min: null, max: 36, pattern: "" } }),
      new SchemaField({ name: "last_name", type: "text", options: { min: null, max: 200, pattern: "" } }),
      new SchemaField({ name: "usage_count", type: "number", required: true, options: { min: 0, max: null, noDecimal: true } }),
      new SchemaField({ name: "first_used_at", type: "date", required: true }),
      new SchemaField({ name: "last_used_at", type: "date", required: true }),
      new SchemaField({ name: "last_amount", type: "number", options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "last_unit", type: "select", options: { maxSelect: 1, values: ["g", "ml"] } }),
      new SchemaField({ name: "last_portion_name", type: "text", options: { min: null, max: 160, pattern: "" } }),
      new SchemaField({ name: "last_portion_id", type: "text", options: { min: null, max: 36, pattern: "" } }),
      new SchemaField({ name: "last_portion_count", type: "number", options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "last_meal", type: "text", options: { min: null, max: 120, pattern: "" } }),
      new SchemaField({ name: "last_entry_client_id", type: "text", required: true, options: { min: 1, max: 36, pattern: "" } }),
      new SchemaField({ name: "server_updated_at", type: "date", required: true })
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_user_food_usage_user_source` ON `user_food_usage` (`user`, `source_key`)",
      "CREATE INDEX `idx_user_food_usage_user_count` ON `user_food_usage` (`user`, `usage_count` DESC)",
      "CREATE INDEX `idx_user_food_usage_user_last` ON `user_food_usage` (`user`, `last_used_at` DESC)"
    ]
  })
  dao.saveCollection(usage)

  const digits = (value) => String(value || "").replace(/[^0-9]/g, "")
  const approvedBarcodes = {}
  for (const collection of [globals, foods]) {
    const records = dao.findRecordsByFilter(collection.name, "barcode != ''", "", 0, 0)
    for (const record of records) {
      const raw = String(record.get("barcode") || "")
      record.set("barcode_raw", raw)
      const normalized = digits(raw)
      if (collection.name === "global_foods" && record.get("moderation_status") === "approved" && approvedBarcodes[normalized]) {
        // Keep the record reviewable, but never expose two approved catalogue
        // matches for the same canonical GTIN.
        record.set("moderation_status", "pending")
      } else if (collection.name === "global_foods" && record.get("moderation_status") === "approved") {
        approvedBarcodes[normalized] = record.id
      }
      record.set("barcode_normalized", normalized)
      dao.saveRecord(record)
    }
  }

  // Persist a snapshot key on every historical entry before relations can be
  // deleted. The hook performs the authoritative first rebuild after startup.
  const entries = dao.findRecordsByFilter("user_foods", "record_type = 'entry'", "", 0, 0)
  const slug = (value) => String(value || "").trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 120)
  for (const entry of entries) {
    let source = "user_food"
    var key = ""
    if (entry.get("global_recipe")) { source = "recipe"; key = "recipe:global:" + entry.get("global_recipe") }
    else if (entry.get("user_recipe")) { source = "recipe"; key = "recipe:user:" + entry.get("user_recipe") }
    else if (entry.get("recipe_client_id")) { source = "recipe"; key = "recipe:local:" + entry.get("recipe_client_id") }
    else if (entry.get("global_food")) { source = "global_food"; key = "global_food:" + entry.get("global_food") }
    else { key = "snapshot:" + slug(entry.get("name")) + ":" + String(entry.get("unit") || "g") }
    entry.set("source_type", source)
    entry.set("source_key", key)
    dao.saveRecord(entry)
  }

  // First reconstruction for every existing account. Subsequent rebuilds use
  // the same meal-entry source through the server hook/route.
  const grouped = {}
  for (const entry of entries) {
    const user = String(entry.get("user") || "")
    const key = String(entry.get("source_key") || "")
    if (!user || !key) continue
    const groupKey = user + "|" + key
    const usedAt = String(entry.get("eaten_at") || entry.get("created") || "")
    if (!grouped[groupKey]) grouped[groupKey] = { user, key, source: String(entry.get("source_type") || "user_food"), first: usedAt, last: usedAt, count: 0, entry }
    const value = grouped[groupKey]
    value.count += 1
    if (usedAt < value.first) value.first = usedAt
    if (usedAt >= value.last) { value.last = usedAt; value.entry = entry }
  }
  const rebuiltAt = new Date().toISOString()
  for (const value of Object.values(grouped)) {
    const entry = value.entry
    const record = new Record(usage)
    record.set("user", value.user); record.set("source_key", value.key); record.set("source", value.source)
    record.set("food_id", value.key.split(":").pop())
    record.set("client_item_id", String(entry.get("recipe_client_id") || entry.get("source_food_client_id") || ""))
    record.set("last_name", String(entry.get("name") || "")); record.set("usage_count", value.count)
    record.set("first_used_at", value.first); record.set("last_used_at", value.last)
    record.set("last_amount", Number(entry.get("amount") || 0)); record.set("last_unit", String(entry.get("unit") || "g"))
    record.set("last_portion_name", String(entry.get("portion_name") || "")); record.set("last_portion_id", String(entry.get("portion_id") || ""))
    record.set("last_portion_count", Number(entry.get("portion_count") || 0)); record.set("last_meal", String(entry.get("meal_key") || entry.get("meal") || ""))
    record.set("last_entry_client_id", String(entry.get("client_id") || entry.id)); record.set("server_updated_at", rebuiltAt)
    dao.saveRecord(record)
  }
}, (db) => {
  const dao = new Dao(db)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("user_food_usage")) } catch (_) {}
  const foods = dao.findCollectionByNameOrId("user_foods")
  for (const name of ["barcode_raw", "barcode_normalized", "source_type", "source_key", "source_food_client_id", "external_source", "external_source_id", "external_fetched_at", "portion_id"]) {
    try { foods.schema.removeField(foods.schema.getFieldByName(name).id) } catch (_) {}
  }
  foods.indexes = foods.indexes.filter((value) => !value.includes("idx_user_foods_user_barcode_normalized") && !value.includes("idx_user_foods_user_source_key"))
  dao.saveCollection(foods)
  const globals = dao.findCollectionByNameOrId("global_foods")
  for (const name of ["barcode_raw", "barcode_normalized"]) {
    try { globals.schema.removeField(globals.schema.getFieldByName(name).id) } catch (_) {}
  }
  globals.indexes = globals.indexes.filter((value) => !value.includes("idx_global_foods_barcode_normalized") && !value.includes("idx_global_foods_approved_barcode"))
  dao.saveCollection(globals)
})
