/// PocketBase 0.22.x: opaque, server-side email unsubscribe tokens.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const tokens = new Collection({
    name: "hyse_email_unsubscribe_tokens", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      new SchemaField({ name: "user", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "token_hash", type: "text", required: true, options: { min: 64, max: 64, pattern: "^[a-f0-9]{64}$" } }),
      new SchemaField({ name: "used_at", type: "date" })
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_hyse_email_unsubscribe_token` ON `hyse_email_unsubscribe_tokens` (`token_hash`)",
      "CREATE INDEX `idx_hyse_email_unsubscribe_user` ON `hyse_email_unsubscribe_tokens` (`user`, `created`)"
    ]
  })
  dao.saveCollection(tokens)
}, (db) => {
  const dao = new Dao(db)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("hyse_email_unsubscribe_tokens")) } catch (_) {}
})
