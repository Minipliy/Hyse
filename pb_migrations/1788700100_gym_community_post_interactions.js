/// Emoji reactions for Gym Community posts. Direct collection access remains
/// closed; authenticated hook routes enforce membership and authorship.
migrate((db) => {
  const dao = new Dao(db)
  try {
    dao.findCollectionByNameOrId("gym_community_post_reactions")
    return
  } catch (_) {}
  const posts = dao.findCollectionByNameOrId("gym_community_posts")
  const users = dao.findCollectionByNameOrId("users")
  const relation = (name, collection) => new SchemaField({
    name, type: "relation", required: true,
    options: { collectionId: collection.id, cascadeDelete: true, maxSelect: 1 }
  })
  const reactions = new Collection({
    name: "gym_community_post_reactions", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      relation("post", posts), relation("user", users),
      new SchemaField({ name: "emoji", type: "select", required: true, options: { maxSelect: 1, values: ["👍", "❤️", "🔥", "👏", "💪", "😂"] } })
    ],
    indexes: [
      "CREATE UNIQUE INDEX `idx_gym_post_reactions_unique` ON `gym_community_post_reactions` (`post`, `user`, `emoji`)",
      "CREATE INDEX `idx_gym_post_reactions_post` ON `gym_community_post_reactions` (`post`, `created`)"
    ]
  })
  dao.saveCollection(reactions)
}, (db) => {
  const dao = new Dao(db)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("gym_community_post_reactions")) } catch (_) {}
})
