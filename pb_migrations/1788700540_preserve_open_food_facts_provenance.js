/// <reference path="../pb_data/types.d.ts" />

// Preserve Open Food Facts provenance without rewriting the entire catalogue.
migrate((db) => {
  const dao = new Dao(db)
  let cursor = ""
  while (true) {
    const foods = dao.findRecordsByFilter(
      "global_foods",
      "id > {:cursor} && (source = 'open_food_facts' || data_source = 'Open Food Facts (ODbL 1.0)') && (source != 'open_food_facts' || data_source != 'Open Food Facts (ODbL 1.0)' || source_id = '')",
      "id", 500, 0, { cursor }
    )
    if (!foods.length) break
    for (const food of foods) {
      cursor = food.id
      const barcode = String(food.get("barcode_normalized") || food.get("barcode") || "").replace(/\D/g, "")
      const sourceID = String(food.get("source_id") || barcode)
      if (String(food.get("source")) === "open_food_facts" && String(food.get("data_source")) === "Open Food Facts (ODbL 1.0)" && String(food.get("source_id") || "") === sourceID) continue
      food.set("source", "open_food_facts")
      food.set("source_id", sourceID)
      food.set("data_source", "Open Food Facts (ODbL 1.0)")
      dao.saveRecord(food)
    }
  }

  cursor = ""
  while (true) {
    const foods = dao.findRecordsByFilter("user_foods", "id > {:cursor} && global_food != ''", "id", 500, 0, { cursor })
    if (!foods.length) break
    for (const food of foods) {
      cursor = food.id
      let globalFood
      try { globalFood = dao.findRecordById("global_foods", String(food.get("global_food"))) } catch (_) { continue }
      if (String(globalFood.get("source")) !== "open_food_facts") continue
      const sourceID = String(globalFood.get("source_id") || "")
      if (!sourceID) continue
      if (String(food.get("external_source")) === "Open Food Facts" && String(food.get("external_source_id")) === sourceID) continue
      food.set("external_source", "Open Food Facts")
      food.set("external_source_id", sourceID)
      dao.saveRecord(food)
    }
  }
}, (_db) => {
  // Retain provenance on rollback so copied data never loses its origin.
})
