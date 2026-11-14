/// Unlisted, revocable routine snapshots with an optional public cover photo.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  dao.saveCollection(new Collection({
    name: "routine_shares", type: "base", system: false,
    listRule: null,
    viewRule: "",
    createRule: '@request.auth.id != "" && owner = @request.auth.id',
    updateRule: '@request.auth.id != "" && owner = @request.auth.id',
    deleteRule: '@request.auth.id != "" && owner = @request.auth.id',
    schema: [
      new SchemaField({ name: "owner", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "snapshot_json", type: "json", required: true, options: { maxSize: 262144 } }),
      new SchemaField({ name: "image", type: "file", options: { maxSelect: 1, maxSize: 2097152, mimeTypes: ["image/jpeg"], thumbs: ["480x480", "1200x1200"], protected: false } })
    ],
    indexes: ["CREATE INDEX `idx_routine_shares_owner` ON `routine_shares` (`owner`)"]
  }))
}, (db) => {
  const dao = new Dao(db)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("routine_shares")) } catch (_) {}
})
