/// Adds an optional, public cover image to each gym community.
migrate((db) => {
  const dao = new Dao(db)
  const communities = dao.findCollectionByNameOrId("gym_communities")
  if (!communities.schema.getFieldByName("image")) {
    communities.schema.addField(new SchemaField({
      name: "image",
      type: "file",
      required: false,
      options: {
        maxSelect: 1,
        maxSize: 2097152,
        mimeTypes: ["image/jpeg", "image/png", "image/webp"],
        thumbs: ["128x128", "512x512"],
        protected: false
      }
    }))
    dao.saveCollection(communities)
  }
}, (db) => {
  const dao = new Dao(db)
  const communities = dao.findCollectionByNameOrId("gym_communities")
  const field = communities.schema.getFieldByName("image")
  if (field) {
    communities.schema.removeField(field.id)
    dao.saveCollection(communities)
  }
})
