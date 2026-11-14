/// Ensure every curated food has a documented default portion.
migrate((db) => {
  const dao = new Dao(db)
  const portions = dao.findCollectionByNameOrId("food_portions")
  for (const sourceID of ["CNF-6979", "CNF-6995"]) {
    const food = dao.findFirstRecordByFilter("global_foods", "source_id = {:source}", { source: sourceID })
    let portion = null
    try { portion = dao.findFirstRecordByFilter(portions.id, "global_food = {:food} && name_key = 'serving' && owner = ''", { food: food.id }) } catch (_) {}
    if (!portion) portion = new Record(portions)
    portion.set("owner", ""); portion.set("user_food", ""); portion.set("global_food", food.id)
    portion.set("client_id", ("seed_" + sourceID + "_serving").slice(0, 36)); portion.set("name_key", "serving"); portion.set("custom_name", "")
    portion.set("amount", 100); portion.set("unit", "g"); portion.set("gram_equivalent", 100); portion.set("sort_order", 0); portion.set("is_default", true); portion.set("status", "approved")
    dao.saveRecord(portion)
  }
}, (db) => {
  // Retain portions referenced by historical meal entries.
})
