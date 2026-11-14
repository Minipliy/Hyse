/// Editorial lifecycle for Update Studio posts.
migrate((db) => {
  const dao = new Dao(db)
  const updates = dao.findCollectionByNameOrId("hyse_updates")
  const fields = [
    new SchemaField({ name: "status", type: "select", options: { maxSelect: 1, values: ["draft", "scheduled", "published", "archived"] } }),
    new SchemaField({ name: "scheduled_for", type: "date" })
  ]
  for (const field of fields) {
    if (!updates.schema.getFieldByName(field.name)) updates.schema.addField(field)
  }
  dao.saveCollection(updates)
}, (db) => {
  const dao = new Dao(db), updates = dao.findCollectionByNameOrId("hyse_updates")
  for (const name of ["status", "scheduled_for"]) {
    try { updates.schema.removeField(updates.schema.getFieldByName(name).id) } catch (_) {}
  }
  dao.saveCollection(updates)
})
