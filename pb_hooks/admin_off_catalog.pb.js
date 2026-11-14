/// <reference path="../pb_data/types.d.ts" />

// Administrative bulk import for the OFF catalogue. One authenticated request
// becomes one SQLite transaction, avoiding tens of thousands of API log rows.
routerAdd("POST", "/api/hyse/admin/off-catalog/import", (c) => {
    const data = $apis.requestInfo(c).data || {}
    const items = Array.isArray(data.items) ? data.items : []
    if (items.length < 1 || items.length > 250) throw new BadRequestError("A batch must contain 1–250 products.")

    let created = 0
    let skipped = 0
    const importedFields = [
        "name", "source_name_en", "name_de", "brand", "barcode", "barcode_raw", "barcode_normalized",
        "unit", "serving_size", "calories", "carbs", "protein", "fat", "sugar", "fiber",
        "saturated_fat", "salt", "creator", "source", "moderation_status", "source_id", "data_source",
        "source_note", "data_date", "reference_amount", "reference_unit", "average_values", "normalized_key",
        "off_de_catalog_rank", "off_unique_scans", "off_popularity_period", "is_fruit"
    ]
    $app.dao().runInTransaction((dao) => {
        const collection = dao.findCollectionByNameOrId("global_foods")
        for (const item of items) {
            if (String(item.source || "") !== "open_food_facts") throw new BadRequestError("Invalid Open Food Facts source.")
            const barcode = String(item.barcode_normalized || "").replace(/\D/g, "")
            const normalizedKey = String(item.normalized_key || "").trim()
            const sourceID = String(item.source_id || "").trim()
            // Curated composition databases and calculated recipes don't have
            // GTINs. They are identified by a stable, source-owned key instead.
            const isReferenceFood = barcode === "" && (
                normalizedKey.startsWith("open_food_facts_category|") ||
                normalizedKey.startsWith("bls_4_0|") ||
                normalizedKey.startsWith("usda_fndds|") ||
                normalizedKey.startsWith("usda_sr_legacy|") ||
                normalizedKey.startsWith("recipe_calculation|")
            )
            if (!isReferenceFood && !/^(?:\d{8}|\d{12,14})$/.test(barcode)) throw new BadRequestError("Invalid barcode in batch.")
            if (!normalizedKey || !sourceID) throw new BadRequestError("Missing catalogue identity.")
            const numericFields = ["calories", "carbs", "protein", "fat", "sugar", "fiber", "saturated_fat", "salt"]
            for (const field of numericFields) {
                const value = Number(item[field])
                const maximum = field === "calories" ? 900 : 100
                if (!isFinite(value) || value < 0 || value > maximum) throw new BadRequestError("Invalid nutrition value.")
            }
            let duplicate = null
            try {
                duplicate = barcode
                    ? dao.findFirstRecordByFilter(collection.id, "barcode_normalized = {:barcode}", { barcode })
                    : dao.findFirstRecordByFilter(collection.id, "normalized_key = {:key}", { key: normalizedKey })
            } catch (_) {}
            if (duplicate) {
                // Stable reference catalogues are also our correction path:
                // re-importing refreshes names and nutrients without creating
                // another food. Barcode products stay immutable here.
                if (isReferenceFood) {
                    for (const field of importedFields) duplicate.set(field, item[field])
                    dao.saveRecord(duplicate)
                }
                skipped++
                continue
            }
            const record = new Record(collection)
            for (const field of importedFields) record.set(field, item[field])
            record.set("source", "open_food_facts")
            record.set("source_id", sourceID)
            record.set("data_source", "Open Food Facts (ODbL 1.0)")
            dao.saveRecord(record)
            created++
        }
    })
    return c.json(200, { created, skipped })
}, $apis.requireAdminAuth())
