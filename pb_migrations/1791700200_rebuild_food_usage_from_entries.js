/// Recreate the derived usage cache from authoritative diary entries after a
/// damaged user_food_usage B-tree has been recovered. No diary rows are changed.
migrate((db) => {
  const dao = new Dao(db)
  const text = (value) => String(value || "").trim()
  const slug = (value) => text(value).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 120)
  const identity = (entry) => {
    const globalRecipe = text(entry.get("global_recipe"))
    const userRecipe = text(entry.get("user_recipe"))
    const recipeClient = text(entry.get("recipe_client_id"))
    if (globalRecipe) return { source: "recipe", key: "recipe:global:" + globalRecipe, id: globalRecipe }
    if (userRecipe) return { source: "recipe", key: "recipe:user:" + userRecipe, id: userRecipe }
    if (recipeClient) return { source: "recipe", key: "recipe:local:" + recipeClient, id: recipeClient }
    const globalFood = text(entry.get("global_food"))
    if (globalFood) return { source: "global_food", key: "global_food:" + globalFood, id: globalFood }
    const persisted = text(entry.get("source_key"))
    if (persisted.indexOf("global_food:") === 0 || persisted.indexOf("recipe:") === 0) {
      return { source: text(entry.get("source_type")) || "user_food", key: persisted, id: persisted.split(":").pop() }
    }
    const user = text(entry.get("user"))
    const client = text(entry.get("source_food_client_id"))
    if (client) {
      try {
        const saved = dao.findFirstRecordByFilter("user_foods", "user = {:user} && record_type = 'saved' && client_id = {:client}", { user, client })
        const linkedGlobal = text(saved.get("global_food"))
        if (linkedGlobal) return { source: "global_food", key: "global_food:" + linkedGlobal, id: linkedGlobal }
        const externalID = text(saved.get("external_source_id"))
        if (externalID) {
          const provider = text(saved.get("external_source")) || "external"
          return { source: "external_food", key: "external_food:" + provider + ":" + externalID, id: externalID }
        }
      } catch (_) {}
      return { source: "user_food", key: "user_food:" + client, id: client }
    }
    if (persisted) return { source: text(entry.get("source_type")) || "user_food", key: persisted, id: persisted.split(":").pop() }
    const fallback = "snapshot:" + slug(entry.get("name")) + ":" + (text(entry.get("unit")) || "g")
    return { source: "user_food", key: fallback, id: fallback }
  }
  const collection = dao.findCollectionByNameOrId("user_food_usage")
  const users = dao.findRecordsByFilter("users", "id != ''", "", 0, 0)
  for (const user of users) {
    const userID = user.id
    const entries = dao.findRecordsByFilter("user_foods", "user = {:user} && record_type = 'entry'", "eaten_at,created", 0, 0, { user: userID })
    const grouped = {}
    for (const entry of entries) {
      const value = identity(entry)
      const usedAt = text(entry.get("eaten_at")) || text(entry.get("created"))
      if (!grouped[value.key]) grouped[value.key] = { identity: value, first: usedAt, last: usedAt, count: 0, entry }
      const aggregate = grouped[value.key]
      aggregate.count += 1
      if (usedAt < aggregate.first) aggregate.first = usedAt
      if (usedAt >= aggregate.last) { aggregate.last = usedAt; aggregate.entry = entry }
    }
    const existing = dao.findRecordsByFilter("user_food_usage", "user = {:user}", "", 0, 0, { user: userID })
    const byKey = {}
    for (const record of existing) byKey[text(record.get("source_key"))] = record
    const now = new Date().toISOString()
    for (const key of Object.keys(grouped)) {
      const value = grouped[key], entry = value.entry, record = byKey[key] || new Record(collection)
      record.set("user", userID); record.set("source_key", key); record.set("source", value.identity.source); record.set("food_id", value.identity.id)
      record.set("client_item_id", text(entry.get("recipe_client_id")) || text(entry.get("source_food_client_id"))); record.set("last_name", text(entry.get("name")))
      record.set("usage_count", value.count); record.set("first_used_at", value.first); record.set("last_used_at", value.last)
      record.set("last_amount", Number(entry.get("amount") || 0)); record.set("last_unit", text(entry.get("unit")) || "g")
      record.set("last_portion_name", text(entry.get("portion_name"))); record.set("last_portion_id", text(entry.get("portion_id"))); record.set("last_portion_count", Number(entry.get("portion_count") || 0))
      record.set("last_meal", text(entry.get("meal_key")) || text(entry.get("meal"))); record.set("last_entry_client_id", text(entry.get("client_id")) || entry.id); record.set("server_updated_at", now)
      dao.saveRecord(record); delete byKey[key]
    }
    for (const stale of Object.values(byKey)) dao.deleteRecord(stale)
  }
}, (db) => {
  // Usage is a cache; reverting this migration must not remove user data.
})
