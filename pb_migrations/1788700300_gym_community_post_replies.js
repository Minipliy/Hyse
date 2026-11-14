/// Optional self-reference used for WhatsApp-style quoted community replies.
migrate((db) => {
  const dao = new Dao(db)
  const posts = dao.findCollectionByNameOrId("gym_community_posts")
  let existing = null
  try { existing = posts.schema.getFieldByName("reply_to") } catch (_) {}
  if (existing) return
  posts.schema.addField(new SchemaField({
    name: "reply_to", type: "relation", required: false,
    options: { collectionId: posts.id, cascadeDelete: false, maxSelect: 1 }
  }))
  posts.indexes.push("CREATE INDEX `idx_gym_community_posts_reply` ON `gym_community_posts` (`reply_to`)")
  dao.saveCollection(posts)
}, (db) => {
  const dao = new Dao(db)
  const posts = dao.findCollectionByNameOrId("gym_community_posts")
  try { posts.schema.removeField(posts.schema.getFieldByName("reply_to").id) } catch (_) {}
  posts.indexes = posts.indexes.filter((value) => value.indexOf("idx_gym_community_posts_reply") < 0)
  dao.saveCollection(posts)
})
