/// PocketBase 0.22 treats an omitted JSON maxSize as zero. Repair every JSON
/// field created by the original migrations so valid snapshots can be stored.
migrate((db) => {
  const dao = new Dao(db)
  const targets = {
    exercises: ["primary_muscles", "secondary_muscles", "snapshot_json"],
    global_brands: ["aliases"],
    global_food_migration_audit: ["snapshot"],
    global_recipe_submissions: ["snapshot_json"],
    global_recipes: ["snapshot_json"],
    user_account_state: ["settings_json", "usage_json"],
    user_recipes: ["filters", "ingredients", "preparation_steps", "snapshot_json", "tags"],
    workout_exercises: ["primary_muscles_snapshot", "secondary_muscles_snapshot"],
    workout_routines: ["snapshot_json"],
    workout_sets: ["personal_record_flags"],
    workouts: ["snapshot_json"]
  }
  for (const collectionName of Object.keys(targets)) {
    const collection = dao.findCollectionByNameOrId(collectionName)
    let changed = false
    for (const fieldName of targets[collectionName]) {
      const field = collection.schema.getFieldByName(fieldName)
      if (!field || field.type !== "json" || Number(field.options.maxSize || 0) > 0) continue
      field.options.maxSize = 5242880
      changed = true
    }
    if (changed) dao.saveCollection(collection)
  }
}, (_db) => {})
