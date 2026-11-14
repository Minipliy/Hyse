/// PocketBase 0.22.x: records language and policy version for the optional email choice.
migrate((db) => {
  const dao = new Dao(db)
  const state = dao.findCollectionByNameOrId("user_account_state")
  state.schema.addField(new SchemaField({ name: "marketing_consent_language", type: "select", options: { maxSelect: 1, values: ["en", "de"] } }))
  state.schema.addField(new SchemaField({ name: "marketing_privacy_version", type: "text", options: { min: null, max: 80, pattern: "" } }))
  dao.saveCollection(state)
}, (db) => {
  const dao = new Dao(db)
  const state = dao.findCollectionByNameOrId("user_account_state")
  for (const name of ["marketing_consent_language", "marketing_privacy_version"]) {
    try { state.schema.removeField(state.schema.getFieldByName(name).id) } catch (_) {}
  }
  dao.saveCollection(state)
})
