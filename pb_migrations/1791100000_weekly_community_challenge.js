/// Weekly opt-in workout challenge for each gym community.
migrate((db) => {
  const dao = new Dao(db)
  const members = dao.findCollectionByNameOrId("gym_community_members")
  if (!members.schema.getFieldByName("challenge_week")) {
    members.schema.addField(new SchemaField({ name: "challenge_week", type: "text", options: { min: null, max: 10, pattern: "" } }))
  }
  dao.saveCollection(members)
}, (db) => {
  const dao = new Dao(db)
  const members = dao.findCollectionByNameOrId("gym_community_members")
  const field = members.schema.getFieldByName("challenge_week")
  if (field) { members.schema.removeField(field.id); dao.saveCollection(members) }
})
