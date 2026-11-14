/// Delivery controls for editorial Hyse updates.
migrate((db) => {
  const dao = new Dao(db)
  const updates = dao.findCollectionByNameOrId("hyse_updates")
  const fields = [
    new SchemaField({ name: "show_popup", type: "bool" }),
    new SchemaField({ name: "show_notification_center", type: "bool" }),
    new SchemaField({ name: "cta", type: "text", options: { min: null, max: 80, pattern: "" } })
  ]
  for (const field of fields) {
    if (!updates.schema.getFieldByName(field.name)) updates.schema.addField(field)
  }
  dao.saveCollection(updates)
}, (db) => {
  const dao = new Dao(db)
  const updates = dao.findCollectionByNameOrId("hyse_updates")
  for (const name of ["show_popup", "show_notification_center", "cta"]) {
    try { updates.schema.removeField(updates.schema.getFieldByName(name).id) } catch (_) {}
  }
  dao.saveCollection(updates)
})
