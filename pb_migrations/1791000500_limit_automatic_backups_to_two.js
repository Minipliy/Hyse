/// Keep two nightly PocketBase backups on the server.
migrate((db) => {
  const dao = new Dao(db)
  const settings = dao.findSettings()

  settings.backups.cron = "15 3 * * *"
  settings.backups.cronMaxKeep = 2

  dao.saveSettings(settings)
}, () => {
  // Keep the two-backup limit even if this migration is rolled back.
})
