/// PocketBase 0.22.x: reject stale root snapshots without changing existing data.
migrate((db) => {
  const dao = new Dao(db)
  for (const name of ["exercises", "workout_routines", "workouts"]) {
    const collection = dao.findCollectionByNameOrId(name)
    try { collection.schema.getFieldByName("client_updated_at"); continue } catch (_) {}
    collection.schema.addField(new SchemaField({
      name: "client_updated_at",
      type: "date",
      required: false
    }))
    dao.saveCollection(collection)
  }
}, (db) => {
  const dao = new Dao(db)
  for (const name of ["exercises", "workout_routines", "workouts"]) {
    const collection = dao.findCollectionByNameOrId(name)
    try { collection.schema.removeField(collection.schema.getFieldByName("client_updated_at").id) } catch (_) { continue }
    dao.saveCollection(collection)
  }
})
