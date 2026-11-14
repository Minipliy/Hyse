/// Adds the two unambiguous US customary food units used by the app. Existing
/// records remain unchanged; the fields keep accepting g and ml as before.
migrate((db) => {
  const dao = new Dao(db)
  const values = ["g", "ml", "oz", "fl oz"]
  const expand = (collectionName, fieldName) => {
    try {
      const collection = dao.findCollectionByNameOrId(collectionName)
      const field = collection.schema.getFieldByName(fieldName)
      if (!field || field.type !== "select") return
      field.options.values = values
      dao.saveCollection(collection)
    } catch (_) {}
  }

  expand("global_foods", "unit")
  expand("user_foods", "unit")
  expand("global_food_submissions", "unit")
  expand("food_portions", "unit")
  expand("user_food_usage", "last_unit")
}, (db) => {
  // Deliberately keep the expanded values on rollback. Removing a select
  // option while records use it would make valid food history unreadable.
})
