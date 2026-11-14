/// PocketBase 0.22.x: distinguish user-configured passwords from OAuth internals.
migrate((db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  users.schema.addField(new SchemaField({ name: "has_local_password", type: "bool" }))
  dao.saveCollection(users)

  const records = dao.findRecordsByFilter("users", "id != ''", "", 0, 0)
  for (const record of records) {
    let external = []
    try { external = dao.findAllExternalAuthsByRecord(record) || [] } catch (_) {}
    // A non-empty lastLoginAlertSentAt on an OAuth-linked record proves that
    // password authentication succeeded at least once (PocketBase sets it for
    // exactly that event). Accounts without OAuth are classic local accounts.
    const usedPasswordWithOAuth = String(record.get("lastLoginAlertSentAt") || "") !== ""
    record.set("has_local_password", external.length === 0 || usedPasswordWithOAuth)
    dao.saveRecord(record)
  }
}, (db) => {
  const dao = new Dao(db)
  const users = dao.findCollectionByNameOrId("users")
  try { users.schema.removeField(users.schema.getFieldByName("has_local_password").id) } catch (_) {}
  dao.saveCollection(users)
})
