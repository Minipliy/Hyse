/// PocketBase 0.22.x: private, mutual training friendships.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const relation = (name) => new SchemaField({ name, type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } })
  const friendships = new Collection({
    name: "training_friendships", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      relation("requester"), relation("recipient"),
      new SchemaField({ name: "pair_key", type: "text", required: true, options: { min: 1, max: 40, pattern: "" } }),
      new SchemaField({ name: "status", type: "select", required: true, options: { maxSelect: 1, values: ["pending", "accepted"] } })
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_training_friendships_pair` ON `training_friendships` (`pair_key`)",
      "CREATE INDEX `idx_training_friendships_requester` ON `training_friendships` (`requester`, `status`)",
      "CREATE INDEX `idx_training_friendships_recipient` ON `training_friendships` (`recipient`, `status`)"
    ]
  })
  dao.saveCollection(friendships)
}, (db) => {
  const dao = new Dao(db)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("training_friendships")) } catch (_) {}
})
