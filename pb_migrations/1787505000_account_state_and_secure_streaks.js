/// PocketBase 0.22.x: private account preferences, consent receipts and server-owned streaks.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const foods = dao.findCollectionByNameOrId("user_foods")

  foods.schema.addField(new SchemaField({ name: "local_day", type: "text", options: { min: null, max: 10, pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$" } }))
  foods.schema.addField(new SchemaField({ name: "timezone_offset", type: "number", options: { min: -720, max: 840, noDecimal: true } }))
  dao.saveCollection(foods)

  const state = new Collection({
    name: "user_account_state", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      new SchemaField({ name: "user", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "terms_version", type: "text", options: { min: null, max: 80, pattern: "" } }),
      new SchemaField({ name: "privacy_version", type: "text", options: { min: null, max: 80, pattern: "" } }),
      new SchemaField({ name: "consented_at", type: "date" }),
      new SchemaField({ name: "consent_language", type: "select", options: { maxSelect: 1, values: ["en", "de"] } }),
      new SchemaField({ name: "marketing_consent", type: "bool" }),
      new SchemaField({ name: "analytics_consent", type: "bool" }),
      new SchemaField({ name: "onboarding_version", type: "number", options: { min: 0, max: 1000, noDecimal: true } }),
      new SchemaField({ name: "usage_json", type: "json" }),
      new SchemaField({ name: "settings_json", type: "json" })
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_user_account_state_user` ON `user_account_state` (`user`)"]
  })
  dao.saveCollection(state)

  const events = new Collection({
    name: "streak_events", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      new SchemaField({ name: "user", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "day", type: "text", required: true, options: { min: 10, max: 10, pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$" } })
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_streak_events_user_day` ON `streak_events` (`user`, `day`)"]
  })
  dao.saveCollection(events)

  const streaks = new Collection({
    name: "user_streaks", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      new SchemaField({ name: "user", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "current", type: "number", options: { min: 0, max: null, noDecimal: true } }),
      new SchemaField({ name: "longest", type: "number", options: { min: 0, max: null, noDecimal: true } }),
      new SchemaField({ name: "last_day", type: "text", options: { min: null, max: 10, pattern: "" } })
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_user_streaks_user` ON `user_streaks` (`user`)"]
  })
  dao.saveCollection(streaks)
}, (db) => {
  const dao = new Dao(db)
  for (const name of ["user_streaks", "streak_events", "user_account_state"]) {
    try { dao.deleteCollection(dao.findCollectionByNameOrId(name)) } catch (_) {}
  }
  const foods = dao.findCollectionByNameOrId("user_foods")
  for (const name of ["local_day", "timezone_offset"]) {
    try { foods.schema.removeField(foods.schema.getFieldByName(name).id) } catch (_) {}
  }
  dao.saveCollection(foods)
})
