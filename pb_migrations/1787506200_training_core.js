/// PocketBase 0.22.x: offline-first strength training core.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const relation = (name, collection, required = true, cascadeDelete = true) => new SchemaField({ name, type: "relation", required, options: { collectionId: collection.id, cascadeDelete, maxSelect: 1 } })
  const text = (name, required = false, max = 0) => new SchemaField({ name, type: "text", required, options: { min: null, max: max || null, pattern: "" } })
  const number = (name, noDecimal = false) => new SchemaField({ name, type: "number", options: { min: null, max: null, noDecimal } })
  const select = (name, values, required = false) => new SchemaField({ name, type: "select", required, options: { maxSelect: 1, values } })
  const json = (name) => new SchemaField({ name, type: "json" })
  const ownRule = '@request.auth.id != "" && user = @request.auth.id'
  const ownCreate = '@request.auth.id != "" && user = @request.auth.id'

  const exercises = new Collection({
    name: "exercises", type: "base", system: false,
    listRule: '@request.auth.id != "" && (visibility = "public" || user = @request.auth.id)',
    viewRule: '@request.auth.id != "" && (visibility = "public" || user = @request.auth.id)',
    createRule: '@request.auth.id != "" && user = @request.auth.id && created_by = @request.auth.id && is_custom = true',
    updateRule: '@request.auth.id != "" && user = @request.auth.id && created_by = @request.auth.id && is_custom = true',
    deleteRule: '@request.auth.id != "" && user = @request.auth.id && created_by = @request.auth.id && is_custom = true',
    schema: [
      relation("user", users), relation("created_by", users), text("client_id", true, 36), text("name_key", true, 120),
      text("english_name", true, 180), text("german_name", false, 180), text("description", false, 4000), text("technique", false, 4000),
      select("exercise_type", ["weight_reps", "bodyweight", "duration", "distance_duration", "reps_only"], true),
      select("equipment", ["barbell", "dumbbell", "machine", "cable", "bodyweight", "bands", "cardio", "other"], true),
      json("primary_muscles"), json("secondary_muscles"), new SchemaField({ name: "media", type: "file", options: { maxSelect: 1, maxSize: 5242880, mimeTypes: ["image/jpeg", "image/png", "image/webp", "video/mp4"], thumbs: ["320x320"], protected: false } }),
      new SchemaField({ name: "is_custom", type: "bool" }), select("visibility", ["private", "public"], true), select("moderation_status", ["private", "pending", "approved", "rejected"], true), json("snapshot_json")
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_exercises_user_client` ON `exercises` (`user`, `client_id`)", "CREATE INDEX `idx_exercises_library` ON `exercises` (`visibility`, `equipment`, `exercise_type`)"]
  })
  dao.saveCollection(exercises)

  const routines = new Collection({
    name: "workout_routines", type: "base", system: false,
    listRule: ownRule, viewRule: ownRule, createRule: ownCreate, updateRule: ownRule, deleteRule: ownRule,
    schema: [relation("user", users), text("client_id", true, 36), text("name", true, 180), text("description", false, 4000), text("folder", false, 180), number("order", true), number("planned_weekday", true), select("visibility", ["private", "public"], true), json("snapshot_json")],
    indexes: ["CREATE UNIQUE INDEX `idx_workout_routines_user_client` ON `workout_routines` (`user`, `client_id`)"]
  })
  dao.saveCollection(routines)

  const routineExercises = new Collection({
    name: "routine_exercises", type: "base", system: false,
    listRule: ownRule, viewRule: ownRule, createRule: ownCreate, updateRule: ownRule, deleteRule: ownRule,
    schema: [relation("user", users), relation("routine", routines), relation("exercise", exercises, false, false), text("client_id", true, 36), text("exercise_client_id", true, 36), number("position", true), text("notes", false, 2000), number("rest_seconds", true), text("superset_group", false, 80)],
    indexes: ["CREATE UNIQUE INDEX `idx_routine_exercises_user_client` ON `routine_exercises` (`user`, `client_id`)", "CREATE INDEX `idx_routine_exercises_position` ON `routine_exercises` (`routine`, `position`)"]
  })
  dao.saveCollection(routineExercises)

  const routineSets = new Collection({
    name: "routine_sets", type: "base", system: false,
    listRule: ownRule, viewRule: ownRule, createRule: ownCreate, updateRule: ownRule, deleteRule: ownRule,
    schema: [relation("user", users), relation("routine_exercise", routineExercises), text("client_id", true, 36), number("position", true), select("set_type", ["normal", "warmup", "drop_set", "failure", "superset"], true), number("target_weight"), number("target_reps", true), number("target_duration"), number("target_distance"), number("target_rpe")],
    indexes: ["CREATE UNIQUE INDEX `idx_routine_sets_user_client` ON `routine_sets` (`user`, `client_id`)"]
  })
  dao.saveCollection(routineSets)

  const workouts = new Collection({
    name: "workouts", type: "base", system: false,
    listRule: ownRule, viewRule: ownRule, createRule: ownCreate, updateRule: ownRule, deleteRule: ownRule,
    schema: [relation("user", users), relation("routine", routines, false, false), text("client_id", true, 36), text("name", true, 180), select("status", ["active", "completed"], true), new SchemaField({ name: "started_at", type: "date", required: true }), new SchemaField({ name: "completed_at", type: "date" }), text("timezone", true, 100), text("notes", false, 6000), select("visibility", ["private", "public"], true), number("duration", true), number("total_volume"), json("snapshot_json")],
    indexes: ["CREATE UNIQUE INDEX `idx_workouts_user_client` ON `workouts` (`user`, `client_id`)", "CREATE INDEX `idx_workouts_user_completed` ON `workouts` (`user`, `completed_at`)"]
  })
  dao.saveCollection(workouts)

  const workoutExercises = new Collection({
    name: "workout_exercises", type: "base", system: false,
    listRule: ownRule, viewRule: ownRule, createRule: ownCreate, updateRule: ownRule, deleteRule: ownRule,
    schema: [relation("user", users), relation("workout", workouts), relation("exercise", exercises, false, false), text("client_id", true, 36), text("exercise_client_id", true, 36), number("position", true), text("exercise_name_snapshot", true, 180), text("exercise_name_de_snapshot", false, 180), select("exercise_type_snapshot", ["weight_reps", "bodyweight", "duration", "distance_duration", "reps_only"], true), select("equipment_snapshot", ["barbell", "dumbbell", "machine", "cable", "bodyweight", "bands", "cardio", "other"], true), json("primary_muscles_snapshot"), json("secondary_muscles_snapshot"), text("notes", false, 2000), number("rest_seconds", true), text("superset_group", false, 80)],
    indexes: ["CREATE UNIQUE INDEX `idx_workout_exercises_user_client` ON `workout_exercises` (`user`, `client_id`)", "CREATE INDEX `idx_workout_exercises_position` ON `workout_exercises` (`workout`, `position`)"]
  })
  dao.saveCollection(workoutExercises)

  const workoutSets = new Collection({
    name: "workout_sets", type: "base", system: false,
    listRule: ownRule, viewRule: ownRule, createRule: ownCreate, updateRule: ownRule, deleteRule: ownRule,
    schema: [relation("user", users), relation("workout_exercise", workoutExercises), text("client_id", true, 36), number("position", true), select("set_type", ["normal", "warmup", "drop_set", "failure", "superset"], true), number("weight"), number("reps", true), number("duration"), number("distance"), number("assisted_weight"), number("rpe"), new SchemaField({ name: "completed", type: "bool" }), new SchemaField({ name: "completed_at", type: "date" }), number("volume"), json("personal_record_flags")],
    indexes: ["CREATE UNIQUE INDEX `idx_workout_sets_user_client` ON `workout_sets` (`user`, `client_id`)"]
  })
  dao.saveCollection(workoutSets)

  const favorites = new Collection({
    name: "exercise_favorites", type: "base", system: false,
    listRule: ownRule, viewRule: ownRule, createRule: ownCreate, updateRule: ownRule, deleteRule: ownRule,
    schema: [relation("user", users), relation("exercise", exercises, false, true), text("exercise_client_id", true, 36)],
    indexes: ["CREATE UNIQUE INDEX `idx_exercise_favorites_user_exercise` ON `exercise_favorites` (`user`, `exercise_client_id`)"]
  })
  dao.saveCollection(favorites)

  const streaks = new Collection({
    name: "training_streaks", type: "base", system: false,
    listRule: ownRule, viewRule: ownRule, createRule: null, updateRule: null, deleteRule: null,
    schema: [relation("user", users), number("current_streak", true), number("longest_streak", true), text("last_valid_training_day", false, 10), text("timezone", true, 100)],
    indexes: ["CREATE UNIQUE INDEX `idx_training_streaks_user` ON `training_streaks` (`user`)"]
  })
  dao.saveCollection(streaks)

  const streakEvents = new Collection({
    name: "training_streak_events", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [relation("user", users), relation("workout", workouts), text("day", true, 10)],
    indexes: ["CREATE UNIQUE INDEX `idx_training_streak_events_user_day` ON `training_streak_events` (`user`, `day`)"]
  })
  dao.saveCollection(streakEvents)
}, (db) => {
  const dao = new Dao(db)
  for (const name of ["training_streak_events", "training_streaks", "exercise_favorites", "workout_sets", "workout_exercises", "workouts", "routine_sets", "routine_exercises", "workout_routines", "exercises"]) {
    try { dao.deleteCollection(dao.findCollectionByNameOrId(name)) } catch (_) {}
  }
})
