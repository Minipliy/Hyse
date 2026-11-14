/// Per-community news subscriptions and APNs device registrations.
migrate((db) => {
  const dao = new Dao(db)
  const members = dao.findCollectionByNameOrId("gym_community_members")
  if (!members.schema.getFieldByName("news_notifications_enabled")) {
    members.schema.addField(new SchemaField({ name: "news_notifications_enabled", type: "bool" }))
  }
  dao.saveCollection(members)

  try { dao.findCollectionByNameOrId("push_devices"); return } catch (_) {}
  const users = dao.findCollectionByNameOrId("users")
  const devices = new Collection({
    name: "push_devices", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      new SchemaField({ name: "user", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "device_token", type: "text", required: true, options: { min: 64, max: 200, pattern: "^[a-fA-F0-9]+$" } }),
      new SchemaField({ name: "environment", type: "select", required: true, options: { maxSelect: 1, values: ["sandbox", "production"] } })
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_push_devices_token` ON `push_devices` (`device_token`)",
      "CREATE INDEX `idx_push_devices_user` ON `push_devices` (`user`, `updated`)"
    ]
  })
  dao.saveCollection(devices)
}, (db) => {
  const dao = new Dao(db)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("push_devices")) } catch (_) {}
  try {
    const members = dao.findCollectionByNameOrId("gym_community_members")
    members.schema.removeField(members.schema.getFieldByName("news_notifications_enabled").id)
    dao.saveCollection(members)
  } catch (_) {}
})
