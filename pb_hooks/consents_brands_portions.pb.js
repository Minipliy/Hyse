/// <reference path="../pb_data/types.d.ts" />

routerAdd("POST", "/api/hyse/consents", (c) => {
    const info = $apis.requestInfo(c)
    const user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const data = info.data || {}
    const installationID = String(data.installation_id || "").trim().slice(0, 64)
    const language = data.language === "de" ? "de" : "en"
    const source = String(data.source || "app").trim().slice(0, 80) || "app"
    if (!installationID) throw new BadRequestError("Installation ID is required.")
    const allowed = { terms: true, privacy_notice: true, cloud_sync: true, marketing_email: true }
    const receipts = Array.isArray(data.receipts) ? data.receipts.slice(0, 10) : []
    const dao = $app.dao()
    const now = new Date().toISOString()
    let recorded = 0
    for (const value of receipts) {
        const category = String(value.category || "")
        const version = String(value.document_version || "").trim().slice(0, 100)
        if (!allowed[category] || !version) continue
        const granted = !!value.granted
        let latest = null
        try { latest = dao.findFirstRecordByFilter("user_consents", "user = {:user} && category = {:category}", "-recorded_at", { user: user.id, category }) } catch (_) {}
        if (latest && latest.getBool("granted") === granted && String(latest.get("document_version")) === version) continue
        const record = new Record(dao.findCollectionByNameOrId("user_consents"))
        record.set("user", user.id)
        record.set("installation_id", installationID)
        record.set("category", category)
        record.set("granted", granted)
        record.set("document_version", version)
        record.set("language", language)
        record.set("source", source)
        record.set("recorded_at", now)
        record.set("revoked_at", granted ? "" : now)
        dao.saveRecord(record)
        recorded++
    }
    return c.json(200, { recorded, server_time: now })
}, $apis.requireRecordAuth("users"))

routerAdd("GET", "/api/hyse/brands", (c) => {
    const info = $apis.requestInfo(c)
    const user = info.authRecord
    const raw = String(c.queryParam("q") || "").trim().slice(0, 100)
    const normalize = (value) => String(value || "").normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("en-US").replace(/[^a-z0-9]+/g, " ").trim().replace(/\s+/g, " ")
    const query = normalize(raw)
    // Include brand names already published on catalogue foods. Older imports
    // stored only the text snapshot, so limiting this to global_brands leaves
    // most existing brands invisible in the food editor.
    const records = user
        ? $app.dao().findRecordsByFilter("global_brands", "status = 'approved' || created_by = {:user}", "name", 0, 0, { user: user.id })
        : $app.dao().findRecordsByFilter("global_brands", "status = 'approved'", "name", 0, 0)
    const values = records.map((record) => {
        const normalized = String(record.get("normalized_name") || "")
        let score = query ? (normalized === query ? 0 : normalized.indexOf(query) === 0 ? 1 : normalized.indexOf(query) >= 0 ? 2 : 10) : 3
        const aliases = Array.isArray(record.get("aliases")) ? record.get("aliases") : []
        if (query && aliases.some((alias) => normalize(alias).indexOf(query) >= 0)) score = Math.min(score, 2)
        return { id: record.id, name: String(record.get("name")), normalized_name: normalized, slug: String(record.get("slug")), aliases, status: String(record.get("status")), created_by: user && String(record.get("created_by")) === user.id ? user.id : "", score }
    })
    const known = {}
    for (const value of values) known[value.normalized_name] = true
    const rows = arrayOf(new DynamicModel({ name: "" }))
    if (query) {
        const tokens = raw.toLocaleLowerCase("en-US").replace(/[^a-z0-9äöüßà-ž]+/g, " ").trim().split(/\s+/).filter(Boolean).slice(0, 5)
        if (tokens.length) {
            $app.dao().db().newQuery(
                "SELECT DISTINCT trim(g.brand) name FROM global_foods_fts f " +
                "JOIN global_foods g ON g.id = f.record_id " +
                "WHERE global_foods_fts MATCH {:match} AND g.moderation_status = 'approved' AND g.brand != '' " +
                "ORDER BY name COLLATE NOCASE LIMIT 500"
            ).bind({ match: tokens.map((token) => 'brand:"' + token + '"*').join(" AND ") }).all(rows)
        }
    } else {
        $app.dao().db().newQuery(
            "SELECT DISTINCT brand name FROM global_foods " +
            "WHERE moderation_status = 'approved' AND brand != '' " +
            "ORDER BY brand COLLATE NOCASE LIMIT 500"
        ).all(rows)
    }
    for (const row of rows) {
        // Open Food Facts may list several brands in one food's brand field.
        for (const part of String(row.name || "").split(/[,;]+/)) {
            const name = part.trim().replace(/\s+/g, " ").slice(0, 160)
            const normalized = normalize(name)
            if (!normalized || known[normalized]) continue
            known[normalized] = true
            values.push({ id: "catalog:" + normalized, name, normalized_name: normalized,
                slug: normalized.replace(/\s+/g, "-"), aliases: [], status: "approved", created_by: "",
                score: query ? (normalized === query ? 0 : normalized.indexOf(query) === 0 ? 1 : normalized.indexOf(query) >= 0 ? 2 : 10) : 3 })
        }
    }
    const matches = values.filter((value) => !query || value.score < 10)
        .sort((a, b) => a.score - b.score || (a.status === "approved" ? -1 : 1) || a.name.localeCompare(b.name))
        .slice(0, 30)
    return c.json(200, { items: matches })
})

routerAdd("POST", "/api/hyse/brands", (c) => {
    const info = $apis.requestInfo(c)
    const user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const data = info.data || {}
    const cleanName = String(data.name || "").trim().replace(/\s+/g, " ").slice(0, 160)
    const normalize = (value) => String(value || "").normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("en-US").replace(/[^a-z0-9]+/g, " ").trim().replace(/\s+/g, " ")
    const normalized = normalize(cleanName)
    if (!cleanName || !normalized) throw new BadRequestError("A valid brand name is required.")
    const dao = $app.dao()
    let duplicate = null
    try { duplicate = dao.findFirstRecordByFilter("global_brands", "normalized_name = {:name}", { name: normalized }) } catch (_) {}
    if (duplicate) {
        const status = String(duplicate.get("status"))
        if (status === "merged") {
            const targetID = String(duplicate.get("merged_into") || "")
            if (targetID) {
                const target = dao.findRecordById("global_brands", targetID)
                return c.json(200, { id: target.id, name: String(target.get("name")), normalized_name: String(target.get("normalized_name")), slug: String(target.get("slug")), aliases: target.get("aliases") || [], status: "approved", created_by: String(target.get("created_by")), duplicate: true })
            }
        }
        // Brands are shared catalogue metadata, so an existing legacy proposal
        // becomes globally usable as soon as it is selected again.
        if (status !== "approved") {
            duplicate.set("status", "approved")
            duplicate.set("reviewed_by", user.id)
            duplicate.set("reviewed_at", new Date().toISOString())
            dao.saveRecord(duplicate)
        }
        return c.json(200, { id: duplicate.id, name: String(duplicate.get("name")), normalized_name: normalized, slug: String(duplicate.get("slug")), aliases: duplicate.get("aliases") || [], status: "approved", created_by: String(duplicate.get("created_by")), duplicate: true })
    }
    const record = new Record(dao.findCollectionByNameOrId("global_brands"))
    record.set("name", cleanName)
    record.set("normalized_name", normalized)
    record.set("slug", normalized.replace(/\s+/g, "-"))
    record.set("aliases", [])
    record.set("status", "approved")
    record.set("created_by", user.id)
    record.set("reviewed_by", user.id)
    record.set("reviewed_at", new Date().toISOString())
    dao.saveRecord(record)
    return c.json(201, { id: record.id, name: cleanName, normalized_name: normalized, slug: String(record.get("slug")), aliases: [], status: "approved", created_by: user.id, duplicate: false })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/brands/:id/review", (c) => {
    const info = $apis.requestInfo(c)
    const action = String((info.data || {}).action || "")
    if (["approve", "reject", "merge"].indexOf(action) < 0) throw new BadRequestError("Invalid review action.")
    const targetID = String((info.data || {}).target_id || "")
    const dao = $app.dao()
    dao.runInTransaction((txDao) => {
        const brand = txDao.findRecordById("global_brands", c.pathParam("id"))
        if (action === "merge") {
            if (!targetID || targetID === brand.id) throw new BadRequestError("A different merge target is required.")
            const target = txDao.findRecordById("global_brands", targetID)
            if (String(target.get("status")) !== "approved") throw new BadRequestError("Merge target must be approved.")
            for (const collection of ["global_foods", "user_foods"]) {
                const records = txDao.findRecordsByFilter(collection, "brand_relation = {:brand}", "", 0, 0, { brand: brand.id })
                for (const record of records) { record.set("brand_relation", target.id); record.set("brand", String(target.get("name"))); txDao.saveRecord(record) }
            }
            brand.set("merged_into", target.id)
            brand.set("status", "merged")
        } else {
            brand.set("status", action === "approve" ? "approved" : "rejected")
        }
        brand.set("reviewed_by", info.admin ? info.admin.id : "admin")
        brand.set("reviewed_at", new Date().toISOString())
        txDao.saveRecord(brand)
    })
    return c.json(200, { status: action === "approve" ? "approved" : action === "reject" ? "rejected" : "merged" })
}, $apis.requireAdminAuth())

const hyseApplyPortionOwner = (e) => {
    const account = e.httpContext.get("authRecord")
    if (!account) throw new UnauthorizedError("Authentication required.")
    const foodID = String(e.record.get("user_food") || "")
    if (!foodID) throw new BadRequestError("A personal food is required.")
    const food = $app.dao().findRecordById("user_foods", foodID)
    if (String(food.get("user")) !== account.id || String(food.get("record_type")) !== "saved") throw new ForbiddenError("You can only manage portions for your own saved foods.")
    const requestedStatus = String(e.record.get("status") || "private")
    let storedStatus = "private"
    if (requestedStatus === "pending") {
        storedStatus = "pending"
    } else if (requestedStatus === "approved" || requestedStatus === "rejected") {
        // Approval is server-owned. A client may preserve an existing review
        // result, but can never grant that result to itself.
        try {
            const current = $app.dao().findRecordById("food_portions", e.record.id)
            const currentStatus = String(current.get("status") || "private")
            if (currentStatus === requestedStatus) storedStatus = currentStatus
        } catch (_) {}
    }
    e.record.set("owner", account.id)
    e.record.set("global_food", "")
    e.record.set("status", storedStatus)
}
onRecordBeforeCreateRequest(hyseApplyPortionOwner, "food_portions")
onRecordBeforeUpdateRequest(hyseApplyPortionOwner, "food_portions")

routerAdd("POST", "/api/hyse/food-portions/submit-global", (c) => {
    const info = $apis.requestInfo(c)
    const account = info.authRecord
    if (!account) throw new UnauthorizedError("Authentication required.")
    const data = info.data || {}
    const userFoodID = String(data.user_food || "").trim()
    const clientID = String(data.client_id || "").trim().toLowerCase()
    if (!userFoodID || !/^[0-9a-f-]{36}$/.test(clientID)) throw new BadRequestError("A personal food and stable portion ID are required.")

    let approvedGlobalID = ""
    $app.dao().runInTransaction((txDao) => {
        const food = txDao.findRecordById("user_foods", userFoodID)
        if (String(food.get("user")) !== account.id || String(food.get("record_type")) !== "saved") throw new ForbiddenError("You can only submit portions from your own saved foods.")
        const source = txDao.findFirstRecordByFilter(
            "food_portions",
            "owner = {:user} && user_food = {:food} && client_id = {:client}",
            { user: account.id, food: food.id, client: clientID }
        )
        if (String(source.get("status")) !== "pending") throw new BadRequestError("This portion has not been submitted.")

        let globalID = String(food.get("global_food") || "")
        if (!globalID) {
            // A newly-created food can finish its global publication just
            // before the personal relation has been written back.
            try {
                const matches = txDao.findRecordsByFilter(
                    "global_food_submissions",
                    "submitted_by = {:user} && personal_food_client_id = {:client} && status = 'approved'",
                    "-reviewed_at", 1, 0,
                    { user: account.id, client: String(food.get("client_id") || "") }
                )
                const submission = matches[0]
                globalID = String(submission.get("source_food") || "")
                if (globalID) { food.set("global_food", globalID); txDao.saveRecord(food) }
            } catch (_) {}
        }
        if (!globalID) throw new BadRequestError("Publish the food before sharing one of its portions.")
        const globalFood = txDao.findRecordById("global_foods", globalID)
        if (String(globalFood.get("moderation_status") || "approved") !== "approved") throw new BadRequestError("The linked global food is not available.")

        let shared = null
        try {
            shared = txDao.findFirstRecordByFilter(
                "food_portions",
                "global_food = {:food} && client_id = {:client} && owner = ''",
                { food: globalID, client: clientID }
            )
        } catch (_) {}
        if (!shared) shared = new Record(txDao.findCollectionByNameOrId("food_portions"))
        for (const key of ["client_id", "name_key", "custom_name", "amount", "unit", "gram_equivalent", "sort_order", "is_default"]) {
            shared.set(key, source.get(key))
        }
        shared.set("owner", "")
        shared.set("user_food", "")
        shared.set("global_food", globalID)
        shared.set("status", "approved")
        txDao.saveRecord(shared)

        // The private source remains owned by the user; only its submission
        // state changes. Public clients receive the separate shared copy.
        source.set("status", "approved")
        txDao.saveRecord(source)
        approvedGlobalID = globalID
    })
    return c.json(200, { status: "approved", global_food: approvedGlobalID })
}, $apis.requireRecordAuth("users"))
