function text(value) { return String(value || "").trim() }
function comparable(value) { return value == null ? "" : String(value) }
function slug(value) { return text(value).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 120) }

function normalizeBarcode(value) {
    const raw = text(value)
    if (!raw) return ""
    if (!/^[0-9\s.\-–—]+$/.test(raw)) throw new BadRequestError("Barcode contains invalid characters.")
    const digits = raw.replace(/[^0-9]/g, "")
    if ([8, 12, 13, 14].indexOf(digits.length) < 0) throw new BadRequestError("Unsupported EAN/UPC/GTIN length.")
    let sum = 0
    for (let i = digits.length - 2, offset = 0; i >= 0; i--, offset++) sum += Number(digits[i]) * (offset % 2 === 0 ? 3 : 1)
    if ((10 - (sum % 10)) % 10 !== Number(digits[digits.length - 1])) throw new BadRequestError("Invalid barcode check digit.")
    return digits
}

function identity(dao, entry) {
    const globalRecipe = text(entry.get("global_recipe")), userRecipe = text(entry.get("user_recipe")), recipeClient = text(entry.get("recipe_client_id"))
    if (globalRecipe) return { source: "recipe", key: "recipe:global:" + globalRecipe, id: globalRecipe }
    if (userRecipe) return { source: "recipe", key: "recipe:user:" + userRecipe, id: userRecipe }
    if (recipeClient) return { source: "recipe", key: "recipe:local:" + recipeClient, id: recipeClient }
    const globalFood = text(entry.get("global_food"))
    if (globalFood) return { source: "global_food", key: "global_food:" + globalFood, id: globalFood }
    const persisted = text(entry.get("source_key"))
    if (persisted.indexOf("global_food:") === 0 || persisted.indexOf("recipe:") === 0) return { source: text(entry.get("source_type")) || "user_food", key: persisted, id: persisted.split(":").pop() }
    const user = text(entry.get("user")), client = text(entry.get("source_food_client_id"))
    if (client) {
        try {
            const saved = dao.findFirstRecordByFilter("user_foods", "user = {:user} && record_type = 'saved' && client_id = {:client}", { user, client })
            const linkedGlobal = text(saved.get("global_food"))
            if (linkedGlobal) return { source: "global_food", key: "global_food:" + linkedGlobal, id: linkedGlobal }
            const externalID = text(saved.get("external_source_id"))
            if (externalID) { const provider = text(saved.get("external_source")) || "external"; return { source: "external_food", key: "external_food:" + provider + ":" + externalID, id: externalID } }
        } catch (_) {}
        return { source: "user_food", key: "user_food:" + client, id: client }
    }
    if (persisted) return { source: text(entry.get("source_type")) || "user_food", key: persisted, id: persisted.split(":").pop() }
    const fallback = "snapshot:" + slug(entry.get("name")) + ":" + (text(entry.get("unit")) || "g")
    return { source: "user_food", key: fallback, id: fallback }
}

function prepare(dao, record) {
    const rawBarcode = text(record.get("barcode_raw")) || text(record.get("barcode"))
    let normalizedBarcode = ""
    // Older clients may send a malformed optional barcode with an otherwise
    // valid saved food. Preserve the food and leave it unscannable.
    try { normalizedBarcode = normalizeBarcode(rawBarcode) } catch (_) {}
    record.set("barcode_raw", rawBarcode); record.set("barcode_normalized", normalizedBarcode); record.set("barcode", normalizedBarcode)
    if (text(record.get("record_type")) !== "entry") return
    const value = identity(dao, record); record.set("source_type", value.source); record.set("source_key", value.key)
}

// Nutrition and micronutrient corrections don't change the recent/frequent
// food list. In particular, a historical micronutrient backfill may update
// hundreds of diary records in one sync.
function usageChanged(record) {
    const original = record.originalCopy()
    const fields = [
        "record_type", "user", "global_recipe", "user_recipe", "recipe_client_id",
        "global_food", "source_key", "source_type", "source_food_client_id",
        "name", "amount", "unit", "portion_name", "portion_id", "portion_count",
        "meal_key", "meal", "client_id", "eaten_at"
    ]
    return fields.some((field) => comparable(record.get(field)) !== comparable(original.get(field)))
}

function rebuild(dao, userID) {
    const entries = dao.findRecordsByFilter("user_foods", "user = {:user} && record_type = 'entry'", "eaten_at,created", 0, 0, { user: userID }), grouped = {}
    for (const entry of entries) {
        const value = identity(dao, entry), usedAt = text(entry.get("eaten_at")) || text(entry.get("created"))
        if (!grouped[value.key]) grouped[value.key] = { identity: value, first: usedAt, last: usedAt, count: 0, entry }
        const aggregate = grouped[value.key]; aggregate.count += 1
        if (usedAt < aggregate.first) aggregate.first = usedAt
        if (usedAt >= aggregate.last) { aggregate.last = usedAt; aggregate.entry = entry }
    }
    const existing = dao.findRecordsByFilter("user_food_usage", "user = {:user}", "", 0, 0, { user: userID }), byKey = {}
    for (const record of existing) byKey[text(record.get("source_key"))] = record
    const collection = dao.findCollectionByNameOrId("user_food_usage"), now = new Date().toISOString()
    for (const key of Object.keys(grouped)) {
        const value = grouped[key], entry = value.entry, record = byKey[key] || new Record(collection)
        const desired = {
            user: userID, source_key: key, source: value.identity.source, food_id: value.identity.id,
            client_item_id: text(entry.get("recipe_client_id")) || text(entry.get("source_food_client_id")),
            last_name: text(entry.get("name")), usage_count: value.count,
            first_used_at: value.first, last_used_at: value.last,
            last_amount: Number(entry.get("amount") || 0), last_unit: text(entry.get("unit")) || "g",
            last_portion_name: text(entry.get("portion_name")), last_portion_id: text(entry.get("portion_id")),
            last_portion_count: Number(entry.get("portion_count") || 0),
            last_meal: text(entry.get("meal_key")) || text(entry.get("meal")),
            last_entry_client_id: text(entry.get("client_id")) || entry.id
        }
        const changed = !byKey[key] || Object.keys(desired).some((field) =>
            comparable(record.get(field)) !== comparable(desired[field]))
        if (changed) {
            for (const field of Object.keys(desired)) record.set(field, desired[field])
            record.set("server_updated_at", now)
            dao.saveRecord(record)
        }
        delete byKey[key]
    }
    for (const stale of Object.values(byKey)) dao.deleteRecord(stale)
    return Object.keys(grouped).length
}

module.exports = { text, prepare, usageChanged, rebuild }
