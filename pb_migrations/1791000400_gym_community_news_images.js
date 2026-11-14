/// Allows gym administrators to attach up to four images to a news post.
migrate((db) => {
  const dao = new Dao(db)
  const posts = dao.findCollectionByNameOrId("gym_community_posts")
  if (posts.schema.getFieldByName("images")) return
  posts.schema.addField(new SchemaField({
    name: "images",
    type: "file",
    required: false,
    options: {
      maxSelect: 4,
      maxSize: 2097152,
      mimeTypes: ["image/jpeg", "image/png", "image/webp"],
      thumbs: ["480x480", "1200x0"],
      protected: false
    }
  }))
  dao.saveCollection(posts)
}, (db) => {
  const dao = new Dao(db)
  const posts = dao.findCollectionByNameOrId("gym_community_posts")
  const field = posts.schema.getFieldByName("images")
  if (field) {
    posts.schema.removeField(field.id)
    dao.saveCollection(posts)
  }
})
