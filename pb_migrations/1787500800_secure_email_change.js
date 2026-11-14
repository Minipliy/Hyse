/// PocketBase 0.22.x: one-time passwordless email-change confirmation after recent reauthentication.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")

  const reauth = new Collection({
    name: "hyse_reauth_sessions", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      new SchemaField({ name: "user", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "token_hash", type: "text", required: true, options: { min: 64, max: 64, pattern: "^[a-f0-9]{64}$" } }),
      new SchemaField({ name: "method", type: "select", required: true, options: { maxSelect: 1, values: ["password", "google", "apple"] } }),
      new SchemaField({ name: "expires_at", type: "date", required: true }),
      new SchemaField({ name: "used", type: "bool" })
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_hyse_reauth_token` ON `hyse_reauth_sessions` (`token_hash`)"]
  })
  dao.saveCollection(reauth)

  const requests = new Collection({
    name: "hyse_email_change_requests", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      new SchemaField({ name: "user", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "old_email", type: "email", required: true }),
      new SchemaField({ name: "new_email", type: "email", required: true }),
      new SchemaField({ name: "token_hash", type: "text", required: true, options: { min: 64, max: 64, pattern: "^[a-f0-9]{64}$" } }),
      new SchemaField({ name: "expires_at", type: "date", required: true }),
      new SchemaField({ name: "used", type: "bool" })
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_hyse_email_change_token` ON `hyse_email_change_requests` (`token_hash`)"]
  })
  dao.saveCollection(requests)
}, (db) => {
  const dao = new Dao(db)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("hyse_email_change_requests")) } catch (_) {}
  try { dao.deleteCollection(dao.findCollectionByNameOrId("hyse_reauth_sessions")) } catch (_) {}
})
