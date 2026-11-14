/// PocketBase 0.22.x: account-owned Streak on Ice balance, inventory and receipts.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  const own = '@request.auth.id != "" && user = @request.auth.id'
  const states = new Collection({
    name: "streak_reward_states",
    type: "base",
    system: false,
    listRule: own,
    viewRule: own,
    createRule: own,
    updateRule: own,
    deleteRule: own,
    schema: [
      new SchemaField({ name: "user", type: "relation", required: true, options: { collectionId: users.id, cascadeDelete: true, maxSelect: 1 } }),
      new SchemaField({ name: "snapshot_json", type: "json", required: true }),
      new SchemaField({ name: "updated_at_local", type: "date", required: true })
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_streak_reward_states_user` ON `streak_reward_states` (`user`)"
    ]
  })
  dao.saveCollection(states)
}, (db) => {
  const dao = new Dao(db)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("streak_reward_states")) } catch (_) {}
})
