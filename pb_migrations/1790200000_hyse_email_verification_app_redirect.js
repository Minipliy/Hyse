/// <reference path="../pb_data/types.d.ts" />

// Send account-verification links to Hyse's server callback instead of the
// PocketBase dashboard page, which only renders a generic "successful" text.
migrate((db) => {
  const dao = new Dao(db)
  const settings = dao.findSettings()
  settings.meta.verificationTemplate.actionUrl = "{APP_URL}/api/hyse/verify-email/{TOKEN}"
  dao.saveSettings(settings)
}, (db) => {
  const dao = new Dao(db)
  const settings = dao.findSettings()
  settings.meta.verificationTemplate.actionUrl = "{APP_URL}/_/#/auth/confirm-verification/{TOKEN}"
  dao.saveSettings(settings)
})
