/// PocketBase 0.22 treats a JSON field with maxSize 0 as allowing no bytes.
/// Existing recipe_shares therefore reject every nonempty snapshot with HTTP 400.
migrate((db) => {
  const dao = new Dao(db)
  const shares = dao.findCollectionByNameOrId("recipe_shares")
  shares.schema.getFieldByName("snapshot_json").options.maxSize = 262144
  dao.saveCollection(shares)
}, (db) => {
  const dao = new Dao(db)
  const shares = dao.findCollectionByNameOrId("recipe_shares")
  shares.schema.getFieldByName("snapshot_json").options.maxSize = 0
  dao.saveCollection(shares)
})
