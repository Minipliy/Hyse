/// Public, unlisted snapshots created only by an authenticated recipe owner.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const shares = new Collection({
    name: "recipe_shares", type: "base", system: false,
    listRule: null,
    viewRule: "",
    createRule: '@request.auth.id != "" && owner = @request.auth.id',
    updateRule: '@request.auth.id != "" && owner = @request.auth.id',
    deleteRule: '@request.auth.id != "" && owner = @request.auth.id',
    schema: [
      new SchemaField({ name: "owner", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "snapshot_json", type: "json", required: true }),
      new SchemaField({ name: "image", type: "file", options: { maxSelect: 1, maxSize: 2097152, mimeTypes: ["image/jpeg"], thumbs: ["480x480", "1200x1200"], protected: false } })
    ],
    indexes: ["CREATE INDEX `idx_recipe_shares_owner` ON `recipe_shares` (`owner`)"]
  })
  dao.saveCollection(shares)
}, (db) => {
  const dao = new Dao(db)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("recipe_shares")) } catch (_) {}
})
