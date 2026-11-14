/// PocketBase 0.22.x: immutable revisions for approved global foods and stable meal keys.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const globals = dao.findCollectionByNameOrId("global_foods")
  const foods = dao.findCollectionByNameOrId("user_foods")

  const submissions = new Collection({
    name: "global_food_submissions", type: "base", system: false,
    // A user can only see their own revision history. Mutations are performed
    // exclusively by the validated routes in global_food_submissions.pb.js.
    listRule: '@request.auth.id != "" && submitted_by = @request.auth.id',
    viewRule: '@request.auth.id != "" && submitted_by = @request.auth.id',
    createRule: null, updateRule: null, deleteRule: null,
    schema: [
      new SchemaField({ name: "submitted_by", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "source_food", type: "relation", required: true, options: { collectionId: globals.id, cascadeDelete: false, maxSelect: 1 } }),
      new SchemaField({ name: "client_id", type: "text", required: true, options: { min: 1, max: 36, pattern: "" } }),
      new SchemaField({ name: "base_updated", type: "date" }),
      new SchemaField({ name: "status", type: "select", required: true, options: { maxSelect: 1, values: ["pending", "approved", "rejected"] } }),
      new SchemaField({ name: "name", type: "text", required: true, options: { min: 1, max: 200, pattern: "" } }),
      new SchemaField({ name: "brand", type: "text", options: { min: null, max: 160, pattern: "" } }),
      new SchemaField({ name: "barcode", type: "text", options: { min: null, max: 64, pattern: "" } }),
      new SchemaField({ name: "unit", type: "select", required: true, options: { maxSelect: 1, values: ["g", "ml"] } }),
      new SchemaField({ name: "serving_size", type: "number", options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "calories", type: "number", options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "carbs", type: "number", options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "protein", type: "number", options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "fat", type: "number", options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "sugar", type: "number", options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "fiber", type: "number", options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "saturated_fat", type: "number", options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "salt", type: "number", options: { min: 0, max: null, noDecimal: false } }),
      new SchemaField({ name: "is_fruit", type: "bool" }),
      new SchemaField({ name: "reviewed_by", type: "text", options: { min: null, max: 64, pattern: "" } }),
      new SchemaField({ name: "reviewed_at", type: "date" }),
      new SchemaField({ name: "rejection_reason", type: "text", options: { min: null, max: 1000, pattern: "" } })
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_global_submission_pending` ON `global_food_submissions` (`submitted_by`, `source_food`) WHERE `status` = 'pending'",
      "CREATE INDEX `idx_global_submission_source_status` ON `global_food_submissions` (`source_food`, `status`, `updated`)"
    ]
  })
  dao.saveCollection(submissions)

  foods.schema.addField(new SchemaField({ name: "global_submission", type: "relation", options: { collectionId: submissions.id, cascadeDelete: false, maxSelect: 1 } }))
  foods.schema.addField(new SchemaField({ name: "meal_key", type: "select", options: { maxSelect: 1, values: ["breakfast", "lunch", "dinner", "snacks"] } }))
  dao.saveCollection(foods)

  const mealKey = (value) => {
    const key = String(value || "").trim().toLocaleLowerCase("de-DE")
    if (["frühstück", "fruehstueck", "breakfast"].includes(key)) return "breakfast"
    if (["mittag", "mittagessen", "lunch"].includes(key)) return "lunch"
    if (["abendbrot", "abendessen", "dinner"].includes(key)) return "dinner"
    if (["snack", "snacks"].includes(key)) return "snacks"
    return ""
  }
  const entries = dao.findRecordsByFilter("user_foods", "record_type = 'entry'", "", 0, 0)
  for (const entry of entries) {
    const key = mealKey(entry.get("meal"))
    if (!key) continue
    entry.set("meal_key", key)
    entry.set("meal", key)
    dao.saveRecord(entry)
  }
}, (db) => {
  const dao = new Dao(db)
  const foods = dao.findCollectionByNameOrId("user_foods")
  for (const name of ["global_submission", "meal_key"]) {
    try { foods.schema.removeField(foods.schema.getFieldByName(name).id) } catch (_) {}
  }
  dao.saveCollection(foods)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("global_food_submissions")) } catch (_) {}
})
