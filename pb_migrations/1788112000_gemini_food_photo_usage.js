/// PocketBase 0.22.x: private rate-limit counters for Gemini food photos.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const usage = new Collection({
    name: "gemini_food_photo_usage", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      new SchemaField({ name: "user", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "day", type: "text", required: true, options: { min: 10, max: 10, pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$" } }),
      new SchemaField({ name: "daily_count", type: "number", options: { min: 0, max: 1000, noDecimal: true } }),
      new SchemaField({ name: "minute_bucket", type: "text", options: { min: null, max: 16, pattern: "" } }),
      new SchemaField({ name: "minute_count", type: "number", options: { min: 0, max: 100, noDecimal: true } })
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_gemini_food_photo_usage_user_day` ON `gemini_food_photo_usage` (`user`, `day`)"]
  })
  dao.saveCollection(usage)
}, (db) => {
  const dao = new Dao(db)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("gemini_food_photo_usage")) } catch (_) {}
})
