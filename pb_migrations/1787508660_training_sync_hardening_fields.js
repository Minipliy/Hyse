/// PocketBase 0.22.x: corrective idempotent field migration.
migrate((db) => {
  const dao = new Dao(db)
  for (const name of ["exercises", "workout_routines", "workouts"]) {
    const collection = dao.findCollectionByNameOrId(name)
    let exists = false
    try { exists = !!collection.schema.getFieldByName("client_updated_at") } catch (_) {}
    if (exists) continue
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
    try {
      const field = collection.schema.getFieldByName("client_updated_at")
      if (!field) continue
      collection.schema.removeField(field.id)
      dao.saveCollection(collection)
    } catch (_) {}
  }
})
