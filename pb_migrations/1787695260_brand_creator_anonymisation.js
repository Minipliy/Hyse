/// Allows approved global brands to remain available without retaining an
/// account relation after the contributor deletes their Hyse account.
migrate((db) => {
  const dao = new Dao(db)
  const brands = dao.findCollectionByNameOrId("global_brands")
  brands.schema.getFieldByName("created_by").required = false
  dao.saveCollection(brands)
}, (db) => {
  const dao = new Dao(db)
  const brands = dao.findCollectionByNameOrId("global_brands")
  brands.schema.getFieldByName("created_by").required = true
  dao.saveCollection(brands)
})
