/// Extend the notification center with friend requests and acceptances.
migrate((db) => {
  const dao = new Dao(db)
  const preferences = dao.findCollectionByNameOrId("notification_preferences")
  if (!preferences.schema.getFieldByName("friend_activity")) {
    preferences.schema.addField(new SchemaField({ name: "friend_activity", type: "bool" }))
    dao.saveCollection(preferences)
  }
  const notifications = dao.findCollectionByNameOrId("user_notifications")
  const type = notifications.schema.getFieldByName("type")
  type.options.values = ["hyse_update", "community_news", "workout_like", "workout_comment", "friend_request", "friend_accepted"]
  dao.saveCollection(notifications)
}, (db) => {
  const dao = new Dao(db)
  try {
    const preferences = dao.findCollectionByNameOrId("notification_preferences")
    preferences.schema.removeField(preferences.schema.getFieldByName("friend_activity").id)
    dao.saveCollection(preferences)
  } catch (_) {}
  try {
    const notifications = dao.findCollectionByNameOrId("user_notifications")
    notifications.schema.getFieldByName("type").options.values = ["hyse_update", "community_news", "workout_like", "workout_comment"]
    dao.saveCollection(notifications)
  } catch (_) {}
})
