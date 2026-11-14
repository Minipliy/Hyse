/// In-app notification center with per-category preferences and Hyse updates.
migrate((db) => {
  const dao = new Dao(db), users = dao.findCollectionByNameOrId("users")
  const relation = (name, collection, required = false, cascadeDelete = false) => new SchemaField({
    name, type: "relation", required, options: { collectionId: collection.id, cascadeDelete, maxSelect: 1 }
  })
  const text = (name, required, max) => new SchemaField({ name, type: "text", required, options: { min: required ? 1 : null, max, pattern: "" } })

  const preferences = new Collection({
    name: "notification_preferences", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      relation("user", users, true, true),
      new SchemaField({ name: "hyse_updates", type: "bool" }),
      new SchemaField({ name: "community_news", type: "bool" }),
      new SchemaField({ name: "workout_likes", type: "bool" }),
      new SchemaField({ name: "workout_comments", type: "bool" })
    ],
    indexes: ["CREATE UNIQUE INDEX `idx_notification_preferences_user` ON `notification_preferences` (`user`)"]
  })
  dao.saveCollection(preferences)

  const communities = dao.findCollectionByNameOrId("gym_communities")
  const workouts = dao.findCollectionByNameOrId("workouts")
  const notifications = new Collection({
    name: "user_notifications", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      relation("recipient", users, true, true), relation("actor", users),
      new SchemaField({ name: "type", type: "select", required: true, options: { maxSelect: 1, values: ["hyse_update", "community_news", "workout_like", "workout_comment"] } }),
      text("title", true, 180), text("body", false, 1000),
      relation("community", communities, false, true), relation("workout", workouts, false, true),
      text("dedupe_key", true, 220), new SchemaField({ name: "is_read", type: "bool" })
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_user_notifications_dedupe` ON `user_notifications` (`recipient`, `dedupe_key`)",
      "CREATE INDEX `idx_user_notifications_feed` ON `user_notifications` (`recipient`, `is_read`, `created`)"
    ]
  })
  dao.saveCollection(notifications)

  const updates = new Collection({
    name: "hyse_updates", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [text("title", true, 180), text("body", true, 2000), new SchemaField({ name: "published", type: "bool" })],
    indexes: ["CREATE INDEX `idx_hyse_updates_published` ON `hyse_updates` (`published`, `created`)"]
  })
  dao.saveCollection(updates)
}, (db) => {
  const dao = new Dao(db)
  for (const name of ["hyse_updates", "user_notifications", "notification_preferences"]) {
    try { dao.deleteCollection(dao.findCollectionByNameOrId(name)) } catch (_) {}
  }
})
