/// PocketBase 0.22 interprets a JSON maxSize of 0 as allowing no content.
/// The original micronutrient migration created both fields with that default,
/// so food and diary uploads carrying a profile are rejected with HTTP 400.
migrate((db) => {
  const dao = new Dao(db)
  for (const name of ["user_foods", "global_foods"]) {
    const collection = dao.findCollectionByNameOrId(name)
    collection.schema.getFieldByName("micronutrients").options.maxSize = 262144
    dao.saveCollection(collection)
  }
}, (db) => {
  const dao = new Dao(db)
  for (const name of ["user_foods", "global_foods"]) {
    const collection = dao.findCollectionByNameOrId(name)
    collection.schema.getFieldByName("micronutrients").options.maxSize = 0
    dao.saveCollection(collection)
  }
})
