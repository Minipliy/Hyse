/// PocketBase 0.22.x: allow a persisted paused workout state.
/// Training preferences stay in the existing owner-protected settings_json field.
migrate((db) => {
  const dao = new Dao(db)
  const workouts = dao.findCollectionByNameOrId("workouts")
  const status = workouts.schema.getFieldByName("status")
  status.options.values = ["active", "paused", "completed"]
  dao.saveCollection(workouts)
}, (db) => {
  const dao = new Dao(db)
  const workouts = dao.findCollectionByNameOrId("workouts")
  const status = workouts.schema.getFieldByName("status")
  status.options.values = ["active", "completed"]
  dao.saveCollection(workouts)
})
