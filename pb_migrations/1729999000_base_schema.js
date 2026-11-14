/// Grundschema für eine neue, leere Hyse-Installation.
/// Die ursprüngliche Installation hat die beiden Tabellen "global_foods" und
/// "food_entries" einmal von Hand angelegt; alle späteren Migrationen bauen
/// darauf auf. Auf einer bestehenden Installation tut diese Migration nichts.
migrate((db) => {
  const dao = new Dao(db)
  const exists = (name) => { try { dao.findCollectionByNameOrId(name); return true } catch (_) { return false } }
  const number = (name) => new SchemaField({ name, type: "number", options: { min: null, max: null, noDecimal: false } })
  const text = (name) => new SchemaField({ name, type: "text", options: { min: null, max: null, pattern: "" } })

  if (!exists("global_foods")) {
    dao.saveCollection(new Collection({
      name: "global_foods", type: "base", system: false,
      schema: [text("name"), number("calories"), number("carbs"), number("protein"), number("fat"), text("barcode")]
    }))
  }
  if (!exists("food_entries")) {
    const users = dao.findCollectionByNameOrId("users")
    dao.saveCollection(new Collection({
      name: "food_entries", type: "base", system: false,
      schema: [
        new SchemaField({ name: "user", type: "relation", options: { collectionId: users.id, cascadeDelete: false, maxSelect: 1 } }),
        text("name"), number("calories"), number("carbs"), number("protein"), number("fat"),
        number("amount_g"), new SchemaField({ name: "eaten_at", type: "date", options: { min: "", max: "" } }), text("category")
      ]
    }))
  }
}, (db) => {})
