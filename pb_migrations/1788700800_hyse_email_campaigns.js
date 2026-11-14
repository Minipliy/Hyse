/// PocketBase 0.22.x: durable campaigns for the Hyse Updates workspace.
migrate((db) => {
  const dao = new Dao(db)
  const campaigns = new Collection({
    name: "hyse_email_campaigns", type: "base", system: false,
    listRule: null, viewRule: null, createRule: null, updateRule: null, deleteRule: null,
    schema: [
      new SchemaField({ name: "subject", type: "text", required: true, options: { min: 1, max: 180, pattern: "" } }),
      new SchemaField({ name: "body", type: "text", required: true, options: { min: 1, max: 10000, pattern: "" } }),
      new SchemaField({ name: "category", type: "select", required: true, options: { maxSelect: 1, values: ["update", "promo", "motivation"] } }),
      new SchemaField({ name: "status", type: "select", required: true, options: { maxSelect: 1, values: ["draft", "sending", "sent", "failed"] } }),
      new SchemaField({ name: "recipient_count", type: "number", options: { min: 0, max: null, noDecimal: true } }),
      new SchemaField({ name: "sent_count", type: "number", options: { min: 0, max: null, noDecimal: true } }),
      new SchemaField({ name: "failed_count", type: "number", options: { min: 0, max: null, noDecimal: true } }),
      new SchemaField({ name: "sent_at", type: "date" }),
      new SchemaField({ name: "error", type: "text", options: { min: null, max: 1000, pattern: "" } })
    ],
    indexes: ["CREATE INDEX `idx_hyse_email_campaigns_status` ON `hyse_email_campaigns` (`status`, `created`)"]
  })
  dao.saveCollection(campaigns)

  const settings = dao.findSettings()
  settings.meta.senderName = "Hyse"
  settings.meta.senderAddress = "hyse@minipliy.net"
  dao.saveSettings(settings)
}, (db) => {
  const dao = new Dao(db)
  try { dao.deleteCollection(dao.findCollectionByNameOrId("hyse_email_campaigns")) } catch (_) {}
})
