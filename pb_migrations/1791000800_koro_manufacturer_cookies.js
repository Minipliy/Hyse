/// KoRo barcode products checked against the manufacturer's product pages on 2026-09-28.
/// Each GTIN is a separate package; nutrients are the manufacturer's values per 100 g.
migrate((db) => {
  const dao = new Dao(db)
  const globals = dao.findCollectionByNameOrId("global_foods")
  const source = globals.schema.getFieldByName("source")
  const values = Array.isArray(source.options.values) ? source.options.values.slice() : []
  if (!values.includes("manufacturer")) values.push("manufacturer")
  source.options.values = values
  dao.saveCollection(globals)

  const products = [
    { barcode: "4260654782752", name: "Bio Cookie Chocolate Chip 50 g", serving: 50, kcal: 537, carbs: 48, protein: 10, fat: 34, sugar: 23, fiber: 7.3, saturated: 22, salt: 0.04, url: "https://www.koro.com/bede/bio-cookie-chocolate-chip-50-g" },
    { barcode: "4260654782769", name: "Bio Cookie Chocolate Chip 12 x 50 g", serving: 50, kcal: 537, carbs: 48, protein: 10, fat: 34, sugar: 23, fiber: 7.3, saturated: 22, salt: 0.04, url: "https://www.koro.com/bede/bio-cookie-chocolate-chip-12-x-50-g" },
    { barcode: "4260654782776", name: "Bio Cookie Salted Caramel 50 g", serving: 50, kcal: 487, carbs: 46, protein: 10, fat: 28, sugar: 18, fiber: 6.5, saturated: 12, salt: 0.23, url: "https://www.koro.com/bede/bio-cookie-salted-caramel-50-g" },
    { barcode: "4260654782783", name: "Bio Cookie Salted Caramel 12 x 50 g", serving: 50, kcal: 487, carbs: 46, protein: 10, fat: 28, sugar: 18, fiber: 6.5, saturated: 12, salt: 0.23, url: "https://www.koro.com/bede/detail/5781753e940d50ee943e10c80ba2a6b9" },
    { barcode: "4255582813845", name: "Bio Cookie mit 16 % Pistazie 50 g", serving: 50, kcal: 519, carbs: 42, protein: 10, fat: 33, sugar: 21, fiber: 5.5, saturated: 11, salt: 0.1, url: "https://www.koro.com/chde/bio-cookie-mit-16-pistazie-50-g" },
    { barcode: "4255582813890", name: "Bio Cookie mit 16 % Pistazie 12 x 50 g", serving: 50, kcal: 519, carbs: 42, protein: 10, fat: 33, sugar: 21, fiber: 5.5, saturated: 11, salt: 0.1, url: "https://www.koro.com/bede/bio-cookie-mit-16-pistazie-12-x-50-g" },
    { barcode: "4255582816051", name: "Bio Cookie Peanut Chocolate Chip 50 g", serving: 50, kcal: 484, carbs: 45, protein: 12, fat: 27, sugar: 22, fiber: 6.2, saturated: 8.8, salt: 0.1, url: "https://www.koro.com/nl/bio-cookie-peanut-chocolate-chip-50-g" },
    { barcode: "4255582816068", name: "Bio Cookie Peanut Chocolate Chip 12 x 50 g", serving: 50, kcal: 484, carbs: 45, protein: 12, fat: 27, sugar: 22, fiber: 6.2, saturated: 8.8, salt: 0.1, url: "https://www.koro.com/bede/bio-cookie-peanut-chocolate-chip-12-x-50-g" },
    { barcode: "4255582819779", name: "Bio Cookie Caramelised Pecan Walnut 50 g", serving: 50, kcal: 384, carbs: 53, protein: 6, fat: 15, sugar: 22, fiber: 6.9, saturated: 5.4, salt: 0.11, url: "https://www.koro.com/bede/bio-cookie-caramelised-pecan-walnut-50-g" },
    { barcode: "4255582819403", name: "Bio Mini Cookies mit 16 % Pistazie 150 g", serving: 150, kcal: 519, carbs: 42, protein: 10, fat: 33, sugar: 21, fiber: 5.5, saturated: 11, salt: 0.1, url: "https://www.koro.com/bede/bio-mini-cookies-mit-16-pistazie-150-g" },
    { barcode: "4255582819410", name: "Bio Mini Cookies Caramelized Almond 150 g", serving: 150, kcal: 468, carbs: 45, protein: 8.1, fat: 26, sugar: 25, fiber: 7.6, saturated: 7.1, salt: 0.19, url: "https://www.koro.com/bede/bio-mini-cookies-caramelized-almond-150-g" },
    { barcode: "4255582819427", name: "Bio Mini Cookies Peanut Chocolate Chip 150 g", serving: 150, kcal: 484, carbs: 45, protein: 12, fat: 27, sugar: 22, fiber: 6.2, saturated: 8.8, salt: 0.1, url: "https://www.koro.com/bede/bio-mini-cookies-peanut-chocolate-chip-150-g" },
    { barcode: "4255582818611", name: "Biskorini Hazelnut Chocolate Chip Cookie 250 g", serving: 100, kcal: 502, carbs: 57, protein: 8.3, fat: 26, sugar: 15, fiber: 3.2, saturated: 4.6, salt: 0.4, url: "https://www.koro.com/bede/biskorini-250-g" },
    { barcode: "4260718292692", name: "Cookie Fudge Cluster in dunkler Schokolade 1 kg", serving: 100, kcal: 499, carbs: 58, protein: 4.7, fat: 27, sugar: 44, fiber: 5.1, saturated: 15, salt: 0.49, url: "https://www.koro.com/bede/cookie-fudge-cluster-in-dunkler-schokolade-1-kg" }
  ]

  for (const product of products) {
    let existing = null
    try { existing = dao.findFirstRecordByFilter(globals.id, "barcode_normalized = {:barcode}", { barcode: product.barcode }) } catch (_) {}
    // Keep user submissions and OFF-licensed rows intact if they already own a GTIN.
    if (existing) continue
    const record = new Record(globals)
    record.set("name", product.name)
    record.set("name_de", "KoRo Kekse: " + product.name)
    record.set("source_name_en", product.name)
    record.set("brand", "KoRo")
    record.set("barcode", product.barcode)
    record.set("barcode_raw", product.barcode)
    record.set("barcode_normalized", product.barcode)
    record.set("unit", "g")
    record.set("serving_size", product.serving)
    record.set("calories", product.kcal)
    record.set("carbs", product.carbs)
    record.set("protein", product.protein)
    record.set("fat", product.fat)
    record.set("sugar", product.sugar)
    record.set("fiber", product.fiber)
    record.set("saturated_fat", product.saturated)
    record.set("salt", product.salt)
    record.set("creator", "")
    record.set("source", "manufacturer")
    record.set("moderation_status", "approved")
    record.set("source_id", "KoRo-" + product.barcode)
    record.set("data_source", "KoRo product page (manufacturer)")
    record.set("source_note", product.url + " ; nutrition per 100 g; package GTIN verified 2026-09-28.")
    record.set("data_date", "2026-09-28")
    record.set("reference_amount", 100)
    record.set("reference_unit", "g")
    record.set("average_values", false)
    record.set("normalized_key", "manufacturer:koro|" + product.barcode)
    record.set("is_fruit", false)
    dao.saveRecord(record)
  }
}, (db) => {
  // Retain foods that may already be referenced by user entries.
})
