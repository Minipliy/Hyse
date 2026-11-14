/// Allow kettlebell exercises to round-trip through PocketBase instead of
/// remaining local-only when a routine or workout is synchronized.
migrate((db) => {
  const dao = new Dao(db)

  const exercises = dao.findCollectionByNameOrId("exercises")
  const equipment = exercises.schema.getFieldByName("equipment")
  if (!equipment.options.values.includes("kettlebell")) {
    equipment.options.values.push("kettlebell")
  }
  dao.saveCollection(exercises)

  const workoutExercises = dao.findCollectionByNameOrId("workout_exercises")
  const snapshot = workoutExercises.schema.getFieldByName("equipment_snapshot")
  if (!snapshot.options.values.includes("kettlebell")) {
    snapshot.options.values.push("kettlebell")
  }
  dao.saveCollection(workoutExercises)
}, (db) => {
  const dao = new Dao(db)

  const exercises = dao.findCollectionByNameOrId("exercises")
  const equipment = exercises.schema.getFieldByName("equipment")
  equipment.options.values = equipment.options.values.filter((value) => value !== "kettlebell")
  dao.saveCollection(exercises)

  const workoutExercises = dao.findCollectionByNameOrId("workout_exercises")
  const snapshot = workoutExercises.schema.getFieldByName("equipment_snapshot")
  snapshot.options.values = snapshot.options.values.filter((value) => value !== "kettlebell")
  dao.saveCollection(workoutExercises)
})
