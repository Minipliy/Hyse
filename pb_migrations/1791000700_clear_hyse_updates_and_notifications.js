/// Clear the existing update archive and notification feed. New notifications
/// created after this migration continue to work normally.
migrate((db) => {
  const dao = new Dao(db)
  for (const collection of ["hyse_updates", "user_notifications"]) {
    while (true) {
      const records = dao.findRecordsByFilter(collection, "id != ''", "", 500, 0, {})
      if (!records.length) break
      for (const record of records) dao.deleteRecord(record)
    }
  }
}, () => {
  // Deleted user messages cannot be recreated by a rollback.
})
