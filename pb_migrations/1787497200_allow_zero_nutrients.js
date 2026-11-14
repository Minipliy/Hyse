/// PocketBase 0.22 treats numeric zero as empty for required validation.
/// Nutrition values may legitimately be zero, so their database default remains
/// zero while required validation is removed.
migrate((db) => {
  const dao = new Dao(db)
  const foods = dao.findCollectionByNameOrId("user_foods")
  for (const name of [
    "calories", "carbs", "protein", "fat", "sugar", "fiber", "saturated_fat", "salt",
    "serving_size", "amount", "added_sugar", "fruit_sugar", "kcal_per_100g",
    "carbs_per_100g", "protein_per_100g", "fat_per_100g", "added_sugar_per_100g",
    "fruit_sugar_per_100g", "fiber_per_100g", "saturated_fat_per_100g", "salt_per_100g"
  ]) {
    try { foods.schema.getFieldByName(name).required = false } catch (_) {}
  }
  dao.saveCollection(foods)
}, (db) => {
  const dao = new Dao(db)
  const foods = dao.findCollectionByNameOrId("user_foods")
  for (const name of ["calories", "carbs", "protein", "fat", "sugar", "fiber", "saturated_fat", "salt"]) {
    try { foods.schema.getFieldByName(name).required = true } catch (_) {}
  }
  dao.saveCollection(foods)
})
