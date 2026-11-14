/// PocketBase 0.22.x: create one automatic backup every night and retain two backups.
migrate((db) => {
  const dao = new Dao(db)
  const settings = dao.findSettings()

  // PocketBase runs this with the server timezone. Backups are written to
  // pb_data/backups (or to the separately configured backup S3 storage).
  settings.backups.cron = "15 3 * * *"
  settings.backups.cronMaxKeep = 2

  dao.saveSettings(settings)
}, (db) => {
  const dao = new Dao(db)
  const settings = dao.findSettings()
  settings.backups.cron = ""
  settings.backups.cronMaxKeep = 2
  dao.saveSettings(settings)
})
