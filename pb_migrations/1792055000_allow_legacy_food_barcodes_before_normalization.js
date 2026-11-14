/// PocketBase validates submitted fields before the user_foods request hook
/// canonicalizes barcodes. Old iOS versions copied the raw optional barcode
/// into barcode_normalized, preventing otherwise valid foods from syncing.
migrate((db) => {
  const dao = new Dao(db)
  const foods = dao.findCollectionByNameOrId("user_foods")
  const field = foods.schema.getFieldByName("barcode_normalized")
  field.options.max = 80
  field.options.pattern = ""
  dao.saveCollection(foods)
}, (db) => {
  const dao = new Dao(db)
  const foods = dao.findCollectionByNameOrId("user_foods")
  const field = foods.schema.getFieldByName("barcode_normalized")
  field.options.max = 14
  field.options.pattern = "^[0-9]{0,14}$"
  dao.saveCollection(foods)
})
