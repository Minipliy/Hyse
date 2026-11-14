/// One shared Hyse account avatar is used by nutrition and training profiles.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  if (!users.schema.getFieldByName("avatar")) {
    users.schema.addField(new SchemaField({
      name: "avatar",
      type: "file",
      required: false,
      options: {
        maxSelect: 1,
        maxSize: 5242880,
        mimeTypes: ["image/jpeg", "image/png", "image/webp"],
        thumbs: ["96x96", "256x256", "512x512"],
        protected: false
      }
    }))
    dao.saveCollection(users)
  }
}, (_db) => {})
