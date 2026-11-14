/// Selected German restaurant menu foods from the operators' published values.
/// Values are per 100 g; serving sizes describe the stated standard build.
/// Source: Subway Germany, March 2026, 15 cm sandwiches:
/// https://www.subway.com/v1v2/assets/de-at/nutrition/documents/germany-nutritional-information-full-menu-c2-march-2026-german.pdf
/// McDonald's Germany product pages were checked on 2026-10-13.
migrate((db) => {
  const dao = new Dao(db)
  const collection = dao.findCollectionByNameOrId("global_foods")
  const subwayURL = "https://www.subway.com/v1v2/assets/de-at/nutrition/documents/germany-nutritional-information-full-menu-c2-march-2026-german.pdf"
  // name, standard serving g, kcal, carbohydrates, protein, fat, sugar,
  // fibre, saturated fat, salt (the last eight values are per 100 g).
  const subway = [
    ["Chicken Teriyaki",227,119,17,9.5,1.5,4.4,1.3,0.6,0.6],
    ["Plant-based Chicken Teriyaki",227,127,19,8.2,1.9,4.1,2.8,0.6,0.99],
    ["Chicken Fajita",209,120,17,9.9,1.2,3.8,1.4,0.6,0.9],
    ["Rotisserie-Style Chicken",209,125,17,10,1.9,3.4,1.4,0.6,0.6],
    ["Chicken Tandoori",199,195,20,13,7.2,5.2,1.4,2.9,1.1],
    ["Dölicious Chicken",263,161,18,10,6.1,3.1,1.8,1.2,1.2],
    ["Tuna",227,147,16,8.9,5.3,3.5,1.3,0.8,0.7],
    ["Italian B.M.T.",217,170,17,9.6,7.2,3.5,1.5,2.9,1.1],
    ["BBQ Rib",217,219,17,10,12,3.6,1.8,4.9,1.1],
    ["Nacho Chicken",233,178,20,8.1,7.2,3.6,1.6,1.9,0.8],
    ["Philly Beef & Cheese",221,138,18,9.2,3.3,4.4,1.5,1.7,0.8],
    ["Salami",169,150,21,6.9,4.5,4.2,1.7,1.9,0.7],
    ["Ham",195,123,18,8.6,1.9,3.9,1.7,0.7,0.6],
    ["Spicy Vegan Patty",238,127,18,8.8,4,3.9,2.7,0.8,0.7],
    ["Smashed Falafel",245,210,22,5.9,11,3.4,4,2.2,1.2],
    ["Veggie Delite",165,140,21,6.6,3.3,4.5,1.8,1.9,0.6],
    ["Plant-based Dölicious Chicken",262,158,19,9.7,4.9,2.9,3.3,0.8,1.5]
  ]
  const products = subway.map((row, index) => ({
    id: "SUBWAY-DE-2026-03-SANDWICH-" + String(index + 1).padStart(2, "0"),
    name: row[0] + " (15 cm)", brand: "Subway", serving: row[1],
    calories: row[2], carbs: row[3], protein: row[4], fat: row[5],
    sugar: row[6], fiber: row[7], saturated_fat: row[8], salt: row[9],
    url: subwayURL, date: "2026-03",
    note: "German standard 15 cm sandwich with recommended bread, vegetables and sauce; customization changes the values."
  }))
  products.push(
    { id: "MCD-DE-CHICKEN-CHEESE-BOX", name: "Chicken & Cheese Box", brand: "McDonald's", serving: 447,
      calories: 258, carbs: 21, protein: 12, fat: 14, sugar: 1.5, fiber: 1.3, saturated_fat: 3.6, salt: 1.7,
      url: "https://www.mcdonalds.com/de/de-de/product/chicken-cheese-box--3210.html", date: "2026-10-13" },
    { id: "MCD-DE-MCRIB-SWEET-HEAT", name: "McRib Sweet Heat", brand: "McDonald's", serving: 224,
      calories: 224, carbs: 23, protein: 11, fat: 9.6, sugar: 7.8, fiber: 1.5, saturated_fat: 3.7, salt: 1.3,
      url: "https://www.mcdonalds.com/de/de-de/product/mcrib-sweet-heart.html", date: "2026-10-13",
      note: "Limited-time product; nutrition applies to the standard German recipe." },
    { id: "MCD-DE-FLAT-WHITE-GRANDE", name: "Flat White grande", brand: "McDonald's", serving: 323,
      calories: 34, carbs: 2.5, protein: 1.8, fat: 1.9, sugar: 2.5, fiber: 0, saturated_fat: 0, salt: 0.07,
      url: "https://www.mcdonalds.com/de/de-de/product/flat-white-grande-200155.html", date: "2026-10-13" }
  )
  for (const product of products) {
    let record = null
    try { record = dao.findFirstRecordByFilter(collection.id, "source_id = {:id}", { id: product.id }) } catch (_) {}
    if (!record) record = new Record(collection)
    record.set("name", product.name)
    record.set("name_de", product.name)
    record.set("source_name_en", product.name)
    record.set("brand", product.brand)
    record.set("unit", "g")
    record.set("serving_size", product.serving)
    record.set("reference_amount", 100)
    record.set("reference_unit", "g")
    for (const key of ["calories","carbs","protein","fat","sugar","fiber","saturated_fat","salt"]) record.set(key, product[key])
    record.set("barcode", "")
    record.set("creator", "")
    record.set("source", "manufacturer")
    record.set("source_id", product.id)
    record.set("data_source", product.url)
    record.set("source_note", product.note || "Official German product values per 100 g; standard recipe; customization changes the values.")
    record.set("data_date", product.date)
    record.set("preparation", "prepared")
    record.set("average_values", false)
    record.set("moderation_status", "approved")
    record.set("normalized_key", "manufacturer:restaurant|" + product.id)
    dao.saveRecord(record)
  }
}, (_db) => {
  // Keep catalogue rows referenced by saved foods and diary entries.
})
