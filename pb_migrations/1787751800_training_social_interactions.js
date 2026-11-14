/// PocketBase 0.22.x: private interactions on friends' completed workouts.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const workouts = dao.findCollectionByNameOrId("workouts")
  const relation = (name, collection) => new SchemaField({ name, type: "relation", required: true, options: { collectionId: collection.id, cascadeDelete: true, maxSelect: 1 } })

  const likes = new Collection({
    name: "training_workout_likes", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [relation("user", users), relation("workout", workouts)],
    indexes: [
      "CREATE UNIQUE INDEX `idx_training_workout_likes_unique` ON `training_workout_likes` (`user`, `workout`)",
      "CREATE INDEX `idx_training_workout_likes_workout` ON `training_workout_likes` (`workout`)"
    ]
  })
  dao.saveCollection(likes)

  const comments = new Collection({
    name: "training_workout_comments", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      relation("user", users), relation("workout", workouts),
      new SchemaField({ name: "body", type: "text", required: true, options: { min: 1, max: 1000, pattern: "" } })
    ],
    indexes: [
      "CREATE INDEX `idx_training_workout_comments_workout` ON `training_workout_comments` (`workout`, `created`)",
      "CREATE INDEX `idx_training_workout_comments_user` ON `training_workout_comments` (`user`)"
    ]
  })
  dao.saveCollection(comments)
}, (db) => {
  const dao = new Dao(db)
  for (const name of ["training_workout_comments", "training_workout_likes"]) {
    try { dao.deleteCollection(dao.findCollectionByNameOrId(name)) } catch (_) {}
  }
})
