/// Apple-verified purchases linked to a Hyse account. Only server hooks write these.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const text = (name, required, max = 0) => new SchemaField({ name, type: "text", required, options: { min: required ? 1 : null, max, pattern: "" } })
  const user = () => new SchemaField({ name: "user", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } })
  const receipts = new Collection({
    name: "premium_apple_receipts", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [user(), text("receipt_data", true), text("environment", true, 16)],
    indexes: ["CREATE UNIQUE INDEX `idx_premium_apple_receipts_user` ON `premium_apple_receipts` (`user`)"]
  })
  dao.saveCollection(receipts)
  const claims = new Collection({
    name: "premium_apple_claims", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [user(), text("original_transaction_id", true, 64), text("product_id", true, 120), new SchemaField({ name: "expires_at", type: "date" })],
    indexes: ["CREATE UNIQUE INDEX `idx_premium_apple_claims_transaction` ON `premium_apple_claims` (`original_transaction_id`)"]
  })
  dao.saveCollection(claims)
}, (db) => {
  const dao = new Dao(db)
  for (const name of ["premium_apple_claims", "premium_apple_receipts"]) {
    try { dao.deleteCollection(dao.findCollectionByNameOrId(name)) } catch (_) {}
  }
})
