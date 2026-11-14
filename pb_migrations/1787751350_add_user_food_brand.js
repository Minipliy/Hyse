/// The iOS saved-food decoder expects a brand key even when it is empty.
migrate((db) => {
  const dao = new Dao(db)
  const foods = dao.findCollectionByNameOrId("user_foods")
  if (!foods.schema.getFieldByName("brand")) {
    foods.schema.addField(new SchemaField({
      name: "brand",
      type: "text",
      required: false,
      options: { min: null, max: 180, pattern: "" }
    }))
    dao.saveCollection(foods)
  }
}, (_db) => {})
