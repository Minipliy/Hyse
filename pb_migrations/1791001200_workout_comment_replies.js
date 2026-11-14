/// Allow workout comments to reference another comment in the same workout.
migrate((db) => {
  const dao = new Dao(db)
  const comments = dao.findCollectionByNameOrId("training_workout_comments")
  let existing = null
  try { existing = comments.schema.getFieldByName("reply_to") } catch (_) {}
  if (existing) return
  comments.schema.addField(new SchemaField({
    name: "reply_to", type: "relation", required: false,
    options: { collectionId: comments.id, cascadeDelete: false, maxSelect: 1 }
  }))
  comments.indexes.push("CREATE INDEX `idx_training_workout_comments_reply` ON `training_workout_comments` (`reply_to`)")
  dao.saveCollection(comments)
}, (db) => {
  const dao = new Dao(db)
  const comments = dao.findCollectionByNameOrId("training_workout_comments")
  try { comments.schema.removeField(comments.schema.getFieldByName("reply_to").id) } catch (_) {}
  comments.indexes = comments.indexes.filter((value) => value.indexOf("idx_training_workout_comments_reply") < 0)
  dao.saveCollection(comments)
})
