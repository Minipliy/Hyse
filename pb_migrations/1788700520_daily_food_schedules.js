/// PocketBase 0.22.x: account-owned schedules for automatic daily food entries.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const own = '@request.auth.id != "" && user = @request.auth.id'
  const schedules = new Collection({
    name: "daily_food_schedules",
    type: "base",
    system: false,
    listRule: own,
    viewRule: own,
    createRule: own,
    updateRule: own,
    deleteRule: own,
    schema: [
      new SchemaField({ name: "user", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "client_id", type: "text", required: true, options: { min: 36, max: 36, pattern: "" } }),
      new SchemaField({ name: "snapshot_json", type: "json", required: true }),
      new SchemaField({ name: "updated_at_local", type: "date", required: true })
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_daily_food_schedules_user_client` ON `daily_food_schedules` (`user`, `client_id`)",
      "CREATE INDEX `idx_daily_food_schedules_user_updated` ON `daily_food_schedules` (`user`, `updated_at_local`)"
    ]
  })
  dao.saveCollection(schedules)
}, (db) => {
  const dao = new Dao(db)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("daily_food_schedules")) } catch (_) {}
})
