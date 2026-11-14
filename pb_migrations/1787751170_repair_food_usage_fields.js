/// Repairs fields skipped by the original null-vs-throw existence check on
/// PocketBase 0.22. Idempotent for clean installations and the live upgrade.
migrate((db) => {
  const dao = new Dao(db)
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

  const digits = (value) => String(value || "").replace(/[^0-9]/g, "")
  const approved = {}
  for (const collectionName of ["global_foods", "user_foods"]) {
    const records = dao.findRecordsByFilter(collectionName, "barcode != ''", "", 0, 0)
    for (const record of records) {
      const raw = String(record.get("barcode") || ""); const normalized = digits(raw)
      record.set("barcode_raw", raw); record.set("barcode_normalized", normalized)
      if (collectionName === "global_foods" && record.get("moderation_status") === "approved") {
        if (normalized && approved[normalized]) record.set("moderation_status", "pending")
        else if (normalized) approved[normalized] = record.id
      }
      dao.saveRecord(record)
    }
  }

  const slug = (value) => String(value || "").trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 120)
  const entries = dao.findRecordsByFilter("user_foods", "record_type = 'entry'", "", 0, 0)
  for (const entry of entries) {
    let source = "user_food"; let key = ""
    if (entry.get("global_recipe")) { source = "recipe"; key = "recipe:global:" + entry.get("global_recipe") }
    else if (entry.get("user_recipe")) { source = "recipe"; key = "recipe:user:" + entry.get("user_recipe") }
    else if (entry.get("recipe_client_id")) { source = "recipe"; key = "recipe:local:" + entry.get("recipe_client_id") }
    else if (entry.get("global_food")) { source = "global_food"; key = "global_food:" + entry.get("global_food") }
    else { key = "snapshot:" + slug(entry.get("name")) + ":" + String(entry.get("unit") || "g") }
    entry.set("source_type", source); entry.set("source_key", key); dao.saveRecord(entry)
  }
}, (_db) => {})
