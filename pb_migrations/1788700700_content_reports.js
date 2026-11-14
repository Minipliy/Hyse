/// DSA/GDPR-oriented user reports for profiles, avatars and social content.
/// The collection is deliberately closed to direct PocketBase API access;
/// pb_hooks/content_reports.pb.js validates targets and owns the workflow.
migrate((db) => {
  const dao = new Dao(db)
  try { dao.findCollectionByNameOrId("content_reports"); return } catch (_) {}
  const users = dao.findCollectionByNameOrId("users")
  const text = (name, required, max) => new SchemaField({
    name, type: "text", required,
    options: { min: required ? 1 : null, max, pattern: "" }
  })
  const reports = new Collection({
    name: "content_reports", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      new SchemaField({ name: "reporter", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "target_type", type: "select", required: true, options: { maxSelect: 1, values: ["user", "avatar", "community", "community_post", "workout", "workout_comment"] } }),
      text("target_id", true, 64),
      text("target_label", false, 200),
      text("target_excerpt", false, 1000),
      new SchemaField({ name: "reason", type: "select", required: true, options: { maxSelect: 1, values: ["illegal", "harassment", "hate", "sexual", "violence", "privacy", "spam", "intellectual_property", "other"] } }),
      text("details", true, 2000),
      new SchemaField({ name: "good_faith", type: "bool", required: true }),
      new SchemaField({ name: "status", type: "select", required: true, options: { maxSelect: 1, values: ["pending", "under_review", "action_taken", "no_action", "appealed", "closed"] } }),
      text("decision_code", false, 120),
      text("decision_reason", false, 2000),
      text("appeal_details", false, 2000),
      new SchemaField({ name: "appealed_at", type: "date" })
    ],
    indexes: [
      "CREATE INDEX `idx_content_reports_reporter` ON `content_reports` (`reporter`, `created`)",
      "CREATE INDEX `idx_content_reports_status` ON `content_reports` (`status`, `created`)",
      "CREATE INDEX `idx_content_reports_target` ON `content_reports` (`target_type`, `target_id`, `created`)"
    ]
  })
  dao.saveCollection(reports)
}, (db) => {
  const dao = new Dao(db)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("content_reports")) } catch (_) {}
})
