/// Public training profile details entered by the account owner.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  if (!users.schema.getFieldByName("social_bio")) {
    users.schema.addField(new SchemaField({ name: "social_bio", type: "text", options: { min: null, max: 160, pattern: "" } }))
  }
  if (!users.schema.getFieldByName("social_website")) {
    users.schema.addField(new SchemaField({ name: "social_website", type: "text", options: { min: null, max: 200, pattern: "" } }))
  }
  dao.saveCollection(users)
}, (db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  for (const name of ["social_bio", "social_website"]) {
    const field = users.schema.getFieldByName(name)
    if (field) users.schema.removeField(field.id)
  }
  dao.saveCollection(users)
})
