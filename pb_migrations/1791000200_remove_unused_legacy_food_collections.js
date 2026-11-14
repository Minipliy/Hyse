/// Removes empty food collections superseded by global_foods and user_foods.
/// Keep this migration narrow: other empty collections still have live callers.
migrate((db) => {
  const dao = new Dao(db)
  for (const name of ["calorie_entries", "food_entries", "foods"]) {
    let collection
    try { collection = dao.findCollectionByNameOrId(name) } catch (_) { continue }

    if (dao.findRecordsByFilter(name, "id != ''", "", 1, 0).length !== 0) {
      throw new Error("Refusing to remove nonempty collection: " + name)
    }
    dao.deleteCollection(collection)
  }
}, (_db) => {
  // These empty legacy schemas can be restored from their original migrations.
})
