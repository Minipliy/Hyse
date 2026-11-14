/// New catalogue foods are submissions first; legacy pending globals are
/// inventoried without deleting or mutating meal/personal records.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const globals = dao.findCollectionByNameOrId("global_foods")
  const submissions = dao.findCollectionByNameOrId("global_food_submissions")

  const sourceFood = submissions.schema.getFieldByName("source_food")
  sourceFood.required = false
  submissions.schema.addField(new SchemaField({ name: "submission_kind", type: "select", options: { maxSelect: 1, values: ["create", "update"] } }))
  submissions.schema.addField(new SchemaField({ name: "personal_food_client_id", type: "text", options: { min: null, max: 36, pattern: "" } }))
  submissions.schema.addField(new SchemaField({ name: "migration_origin", type: "text", options: { min: null, max: 80, pattern: "" } }))
  // The old source-based unique index collapses every source-less creation
  // into one row per user. Replace it with explicit create/update scopes.
  submissions.indexes = submissions.indexes.filter((value) => !value.includes("idx_global_submission_pending`"))
  dao.saveCollection(submissions)
  const existingSubmissions = dao.findRecordsByFilter("global_food_submissions", "submission_kind = ''", "", 0, 0)
  for (const submission of existingSubmissions) {
    submission.set("submission_kind", "update")
    submission.set("personal_food_client_id", submission.get("client_id"))
    dao.saveRecord(submission)
  }

  // Empty-status records without a creator are legacy seeds, not user drafts.
  globals.listRule = '@request.auth.id != "" && (moderation_status = "approved" || (moderation_status = "" && creator = ""))'
  globals.viewRule = globals.listRule
  globals.createRule = null; globals.updateRule = null; globals.deleteRule = null
  dao.saveCollection(globals)

  const audit = new Collection({
    name: "global_food_migration_audit", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      new SchemaField({ name: "original_global_id", type: "text", required: true, options: { min: 1, max: 40, pattern: "" } }),
      new SchemaField({ name: "creator", type: "relation", options: { collectionId: users.id, cascadeDelete: false, maxSelect: 1 } }),
      new SchemaField({ name: "submission", type: "relation", options: { collectionId: submissions.id, cascadeDelete: false, maxSelect: 1 } }),
      new SchemaField({ name: "classification", type: "select", required: true, options: { maxSelect: 1, values: ["clearly_unreviewed_user_global"] } }),
      new SchemaField({ name: "snapshot", type: "json", required: true }),
      new SchemaField({ name: "rollback_note", type: "text", required: true, options: { min: 1, max: 500, pattern: "" } })
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_global_food_migration_audit_original` ON `global_food_migration_audit` (`original_global_id`)"]
  })
  dao.saveCollection(audit)

  const snapshotFields = ["name","name_de","brand","barcode","barcode_raw","barcode_normalized","unit","serving_size","calories","carbs","protein","fat","sugar","fiber","saturated_fat","salt","is_fruit","creator","source","moderation_status","normalized_key","source_id","data_source","source_note","created","updated"]
  const candidates = dao.findRecordsByFilter("global_foods", "creator != '' && source = 'user' && moderation_status != 'approved'", "created", 0, 0)
  for (const global of candidates) {
    let existingAudit = null
    try { existingAudit = dao.findFirstRecordByFilter("global_food_migration_audit", "original_global_id = {:id}", { id: global.id }) } catch (_) {}
    if (existingAudit) continue

    const creator = String(global.get("creator") || "")
    let personal = null
    try { personal = dao.findFirstRecordByFilter("user_foods", "user = {:user} && record_type = 'saved' && global_food = {:global}", { user: creator, global: global.id }) } catch (_) {}
    const clientID = personal ? String(personal.get("client_id") || "") : ("legacy-" + global.id).slice(0, 36)

    let submission = null
    try { submission = dao.findFirstRecordByFilter("global_food_submissions", "migration_origin = {:origin}", { origin: "legacy_global:" + global.id }) } catch (_) {}
    if (!submission) submission = new Record(submissions)
    submission.set("submitted_by", creator); submission.set("source_food", global.id); submission.set("client_id", clientID)
    submission.set("personal_food_client_id", personal ? clientID : ""); submission.set("submission_kind", "create")
    submission.set("migration_origin", "legacy_global:" + global.id); submission.set("status", "pending")
    for (const field of ["name","brand","barcode","unit","serving_size","calories","carbs","protein","fat","sugar","fiber","saturated_fat","salt","is_fruit"]) submission.set(field, global.get(field))
    dao.saveRecord(submission)
    if (personal) { personal.set("global_submission", submission.id); dao.saveRecord(personal) }

    const snapshot = {}
    for (const field of snapshotFields) snapshot[field] = global.get(field)
    const log = new Record(audit)
    log.set("original_global_id", global.id); log.set("creator", creator); log.set("submission", submission.id)
    log.set("classification", "clearly_unreviewed_user_global"); log.set("snapshot", snapshot)
    log.set("rollback_note", "Original global record retained unchanged and hidden by approval-only API rules; remove the generated submission to roll back.")
    dao.saveRecord(log)
  }
}, (db) => {
  const dao = new Dao(db)
  try {
    const migrated = dao.findRecordsByFilter("global_food_submissions", "migration_origin != ''", "", 0, 0)
    for (const record of migrated) dao.deleteRecord(record)
  } catch (_) {}
  try { dao.deleteCollection(dao.findCollectionByNameOrId("global_food_migration_audit")) } catch (_) {}
  const submissions = dao.findCollectionByNameOrId("global_food_submissions")
  for (const name of ["submission_kind", "personal_food_client_id", "migration_origin"]) {
    try { submissions.schema.removeField(submissions.schema.getFieldByName(name).id) } catch (_) {}
  }
  try { submissions.schema.getFieldByName("source_food").required = true } catch (_) {}
  submissions.indexes = submissions.indexes.filter((value) => !value.includes("idx_global_submission_pending_create") && !value.includes("idx_global_submission_pending_update"))
  submissions.indexes.push("CREATE UNIQUE INDEX `idx_global_submission_pending` ON `global_food_submissions` (`submitted_by`, `source_food`) WHERE `status` = 'pending'")
  dao.saveCollection(submissions)
})
