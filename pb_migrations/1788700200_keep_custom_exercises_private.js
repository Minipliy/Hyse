/// User-created exercises always remain private to their owner.
migrate((db) => {
  const dao = new Dao(db)
  const collection = dao.findCollectionByNameOrId("exercises")
  collection.createRule = '@request.auth.id != "" && user = @request.auth.id && created_by = @request.auth.id && is_custom = true && visibility = "private" && moderation_status = "private"'
  collection.updateRule = '@request.auth.id != "" && user = @request.auth.id && created_by = @request.auth.id && is_custom = true && visibility = "private" && moderation_status = "private"'
  dao.saveCollection(collection)
}, (db) => {
  const dao = new Dao(db)
  const collection = dao.findCollectionByNameOrId("exercises")
  collection.createRule = '@request.auth.id != "" && user = @request.auth.id && created_by = @request.auth.id && is_custom = true'
  collection.updateRule = '@request.auth.id != "" && user = @request.auth.id && created_by = @request.auth.id && is_custom = true'
  dao.saveCollection(collection)
})
