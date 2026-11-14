/// Server-backed Hyse Premium codes and account grants.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const text = (name, required, max) => new SchemaField({
    name, type: "text", required,
    options: { min: required ? 1 : null, max, pattern: "" }
  })
  const relation = (name, collection, required = false, cascadeDelete = false) => new SchemaField({
    name, type: "relation", required,
    options: { collectionId: collection.id, cascadeDelete, maxSelect: 1 }
  })

  const codes = new Collection({
    name: "premium_codes", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      text("code_hash", true, 64),
      text("code_preview", true, 12),
      new SchemaField({ name: "kind", type: "select", required: true, options: { maxSelect: 1, values: ["nutrition", "training", "complete"] } }),
      new SchemaField({ name: "duration_key", type: "select", required: true, options: { maxSelect: 1, values: ["one_week", "one_month", "three_months", "six_months", "one_year", "forever", "custom"] } }),
      new SchemaField({ name: "duration_days", type: "number", required: true, options: { min: 0, max: 3650, noDecimal: true } }),
      text("label", false, 120),
      relation("redeemed_by", users),
      new SchemaField({ name: "redeemed_at", type: "date" })
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_premium_codes_hash` ON `premium_codes` (`code_hash`)"]
  })
  dao.saveCollection(codes)

  const grants = new Collection({
    name: "premium_grants", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      relation("user", users, true, true),
      relation("code", codes, true, false),
      new SchemaField({ name: "kind", type: "select", required: true, options: { maxSelect: 1, values: ["nutrition", "training", "complete"] } }),
      new SchemaField({ name: "starts_at", type: "date", required: true }),
      new SchemaField({ name: "expires_at", type: "date" })
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_premium_grants_user_code` ON `premium_grants` (`user`, `code`)"]
  })
  dao.saveCollection(grants)
}, (db) => {
  const dao = new Dao(db)
  for (const name of ["premium_grants", "premium_codes"]) {
    try { dao.deleteCollection(dao.findCollectionByNameOrId(name)) } catch (_) {}
  }
})
