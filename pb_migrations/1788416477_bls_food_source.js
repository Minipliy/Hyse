/// Allow official BLS foods and transparent recipe calculations in the global catalogue.
migrate((db) => {
  const dao = new Dao(db)
  const globals = dao.findCollectionByNameOrId("global_foods")
  const source = globals.schema.getFieldByName("source")
  const values = Array.isArray(source.options.values) ? source.options.values.slice() : []
  for (const value of ["bls", "recipe_calculation"]) {
    if (!values.includes(value)) values.push(value)
  }
  source.options.values = values
  dao.saveCollection(globals)
}, (db) => {
  // Keep the enum values during rollback because records may already use them.
})
