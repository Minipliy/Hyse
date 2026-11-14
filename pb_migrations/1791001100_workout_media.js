/// Store one optional photo or video with a completed workout.
migrate((db) => {
  const dao = new Dao(db)
  const workouts = dao.findCollectionByNameOrId("workouts")
  let exists = false
  try { exists = !!workouts.schema.getFieldByName("media") } catch (_) {}
  if (!exists) {
    workouts.schema.addField(new SchemaField({
      name: "media",
      type: "file",
      options: {
        maxSelect: 1,
        maxSize: 15728640,
        mimeTypes: ["image/jpeg", "image/png", "image/webp", "video/mp4", "video/quicktime"],
        thumbs: ["640x640"],
        protected: false
      }
    }))
    dao.saveCollection(workouts)
  }
}, (db) => {
  const dao = new Dao(db)
  const workouts = dao.findCollectionByNameOrId("workouts")
  let field = null
  try { field = workouts.schema.getFieldByName("media") } catch (_) {}
  if (field) {
    workouts.schema.removeField(field.id)
    dao.saveCollection(workouts)
  }
})
