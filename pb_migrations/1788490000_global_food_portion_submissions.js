/// Keep publication of a personal portion idempotent. The private source and
/// the approved global copy deliberately share a client_id but have different
/// ownership scopes.
migrate((db) => {
  const dao = new Dao(db)
  const collection = dao.findCollectionByNameOrId("food_portions")
  collection.indexes = collection.indexes.filter((value) => !value.includes("idx_food_portions_global_client"))
  collection.indexes.push("CREATE UNIQUE INDEX `idx_food_portions_global_client` ON `food_portions` (`global_food`, `client_id`) WHERE `global_food` != ''")
  dao.saveCollection(collection)
}, (db) => {
  const dao = new Dao(db)
  const collection = dao.findCollectionByNameOrId("food_portions")
  collection.indexes = collection.indexes.filter((value) => !value.includes("idx_food_portions_global_client"))
  dao.saveCollection(collection)
})
