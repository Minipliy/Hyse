/// Optional per-100 g/ml micronutrient snapshots. Existing records remain valid.
migrate((db) => {
  const dao = new Dao(db)
  for (const name of ["user_foods", "global_foods"]) {
    const collection = dao.findCollectionByNameOrId(name)
    if (!collection.schema.getFieldByName("micronutrients")) {
      collection.schema.addField(new SchemaField({ name: "micronutrients", type: "json" }))
      dao.saveCollection(collection)
    }
  }
}, (db) => {
  const dao = new Dao(db)
  for (const name of ["user_foods", "global_foods"]) {
    const collection = dao.findCollectionByNameOrId(name)
    const field = collection.schema.getFieldByName("micronutrients")
    if (field) {
      collection.schema.removeField(field.id)
      dao.saveCollection(collection)
    }
  }
})
