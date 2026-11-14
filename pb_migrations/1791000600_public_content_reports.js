/// Reports submitted inside the app without requiring a Hyse account.
/// The collection is private; only the validated hook may create records.
migrate((db) => {
  const dao = new Dao(db)
  try { dao.findCollectionByNameOrId("public_content_reports"); return } catch (_) {}
  const text = (name, required, max) => new SchemaField({
    name, type: "text", required,
    options: { min: required ? 1 : null, max, pattern: "" }
  })
  const reports = new Collection({
    name: "public_content_reports", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      text("target_location", true, 2048),
      text("contact_email", true, 254),
      new SchemaField({ name: "reason", type: "select", required: true, options: { maxSelect: 1, values: ["illegal", "harassment", "hate", "sexual", "violence", "privacy", "spam", "intellectual_property", "other"] } }),
      text("details", true, 2000),
      new SchemaField({ name: "good_faith", type: "bool", required: true }),
      new SchemaField({ name: "status", type: "select", required: true, options: { maxSelect: 1, values: ["pending", "under_review", "action_taken", "no_action", "appealed", "closed"] } }),
      text("decision_reason", false, 2000),
      text("rate_key", false, 64)
    ],
    indexes: [
      "CREATE INDEX `idx_public_content_reports_status` ON `public_content_reports` (`status`, `created`)",
      "CREATE INDEX `idx_public_content_reports_rate` ON `public_content_reports` (`rate_key`, `created`)"
    ]
  })
  dao.saveCollection(reports)
}, (db) => {
  const dao = new Dao(db)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("public_content_reports")) } catch (_) {}
})
