/// PocketBase 0.22.x: adds an auditable timestamp for the optional email choice.
migrate((db) => {
  const dao = new Dao(db)
  const state = dao.findCollectionByNameOrId("user_account_state")
  try {
    state.schema.addField(new SchemaField({ name: "marketing_updated_at", type: "date" }))
  } catch (_) {}
  dao.saveCollection(state)
}, (db) => {
  const dao = new Dao(db)
  const state = dao.findCollectionByNameOrId("user_account_state")
  try { state.schema.removeField(state.schema.getFieldByName("marketing_updated_at").id) } catch (_) {}
  dao.saveCollection(state)
})
