/// Repairs PocketBase versions where getFieldByName returns null for a missing
/// field instead of throwing, causing the initial reply migration to exit.
migrate((db) => {
  const dao = new Dao(db)
  const posts = dao.findCollectionByNameOrId("gym_community_posts")
  let field = null
  try { field = posts.schema.getFieldByName("reply_to") } catch (_) {}
  if (!field) {
    posts.schema.addField(new SchemaField({
      name: "reply_to", type: "relation", required: false,
      options: { collectionId: posts.id, cascadeDelete: false, maxSelect: 1 }
    }))
  }
  if (!posts.indexes.some((value) => value.indexOf("idx_gym_community_posts_reply") >= 0)) {
    posts.indexes.push("CREATE INDEX `idx_gym_community_posts_reply` ON `gym_community_posts` (`reply_to`)")
  }
  dao.saveCollection(posts)
}, (_db) => {})
