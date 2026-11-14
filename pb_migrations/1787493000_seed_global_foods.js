migrate((db) => {
  const dao = new Dao(db)
  const collection = dao.findCollectionByNameOrId("global_foods")
  const foods = [
    { name: "Apfel", calories: 52, carbs: 14, protein: 0.3, fat: 0.2, barcode: "" },
    { name: "Haferflocken", calories: 368, carbs: 58.7, protein: 13.5, fat: 7, barcode: "" },
    { name: "Magerquark", calories: 68, carbs: 4, protein: 12, fat: 0.2, barcode: "" }
  ]

  for (const food of foods) {
    try {
      dao.findFirstRecordByFilter(collection.id, "name = {:name}", { name: food.name })
    } catch (_) {
      const record = new Record(collection)
      for (const key in food) record.set(key, food[key])
      dao.saveRecord(record)
    }
  }
}, (db) => {
  const dao = new Dao(db)
  const collection = dao.findCollectionByNameOrId("global_foods")
  for (const name of ["Apfel", "Haferflocken", "Magerquark"]) {
    try {
      const record = dao.findFirstRecordByFilter(collection.id, "name = {:name}", { name })
      dao.deleteRecord(record)
    } catch (_) {}
  }
})
