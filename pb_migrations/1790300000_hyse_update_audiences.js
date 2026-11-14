/// Audience routing for editorial Hyse updates.
migrate((db) => {
  const dao = new Dao(db)
  const updates = dao.findCollectionByNameOrId("hyse_updates")
  if (!updates.schema.getFieldByName("audience")) {
    updates.schema.addField(new SchemaField({
      name: "audience", type: "select", options: { maxSelect: 1, values: ["all", "training", "nutrition"] }
    }))
  }
  dao.saveCollection(updates)
}, (db) => {
  const dao = new Dao(db)
  const updates = dao.findCollectionByNameOrId("hyse_updates")
  try { updates.schema.removeField(updates.schema.getFieldByName("audience").id) } catch (_) {}
  dao.saveCollection(updates)
})
