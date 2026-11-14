/// Repairs delivery controls that were skipped by the original rollout.
/// The original migration was already recorded on affected installations,
/// therefore this separate migration makes the schema converge safely.
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
}, () => {
  // Keep the fields on rollback: the original delivery migration owns them.
})
