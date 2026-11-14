/// PocketBase 0.22.x: retain enough request history for recent diagnostics
/// without allowing high-volume sync logs to consume the small server disk.
migrate((db) => {
  const dao = new Dao(db)
  const settings = dao.findSettings()
  settings.logs.maxDays = 2
  dao.saveSettings(settings)
}, (db) => {
  const dao = new Dao(db)
  const settings = dao.findSettings()
  settings.logs.maxDays = 5
  dao.saveSettings(settings)
})
