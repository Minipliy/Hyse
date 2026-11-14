/// <reference path="../pb_data/types.d.ts" />

const HYSE_PREMIUM_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

function hysePremiumNormalizeCode(value) {
    return String(value || "").toUpperCase().replace(/[^A-Z0-9]/g, "")
}

function hysePremiumDurationDays(key, customDays) {
    const fixed = {
        one_week: 7,
        one_month: 30,
        three_months: 90,
        six_months: 180,
        one_year: 365,
        forever: 0
    }
    if (key === "custom") {
        const days = Number(customDays)
        if (!Number.isInteger(days) || days < 1 || days > 3650) throw new BadRequestError("Custom duration must be between 1 and 3650 days.")
        return days
    }
    if (fixed[key] === undefined) throw new BadRequestError("Invalid premium code duration.")
    return fixed[key]
}

function hysePremiumCode() {
    let value = "HYSE"
    for (let i = 0; i < 12; i++) {
        const random = $security.randomString(1)
        const index = Math.abs(String(random).charCodeAt(0) || Date.now()) % HYSE_PREMIUM_CODE_ALPHABET.length
        value += HYSE_PREMIUM_CODE_ALPHABET[index]
        if (i === 3 || i === 7) value += "-"
    }
    return value
}

function hysePremiumCodePayload(record, rawCode) {
    const redeemedBy = String(record.get("redeemed_by") || "")
    const payload = {
        id: record.id,
        code: rawCode || null,
        preview: String(record.get("code_preview") || ""),
        kind: String(record.get("kind") || ""),
        duration_key: String(record.get("duration_key") || ""),
        duration_days: Number(record.get("duration_days") || 0),
        label: String(record.get("label") || ""),
        created: String(record.created || ""),
        status: redeemedBy ? "redeemed" : "available"
    }
    return payload
}

function hysePremiumGrantPayload(record) {
    return {
        kind: String(record.get("kind") || ""),
        starts_at: String(record.get("starts_at") || ""),
        expires_at: String(record.get("expires_at") || "") || null
    }
}

function hysePremiumEntitlements(userID) {
    const now = Date.now()
    const grants = $app.dao().findRecordsByFilter("premium_grants", "user = {:user}", "", 100, 0, { user: userID })
    let nutrition = false, training = false, nutritionUntil = null, trainingUntil = null
    const active = []
    for (const grant of grants) {
        const starts = Date.parse(String(grant.get("starts_at") || ""))
        const expiresRaw = String(grant.get("expires_at") || "")
        const expires = expiresRaw ? Date.parse(expiresRaw) : null
        if (Number.isFinite(starts) && starts > now) continue
        if (expires !== null && (!Number.isFinite(expires) || expires <= now)) continue
        const kind = String(grant.get("kind") || "")
        if (kind === "nutrition" || kind === "complete") {
            nutrition = true
            if (expiresRaw && (!nutritionUntil || expiresRaw > nutritionUntil)) nutritionUntil = expiresRaw
        }
        if (kind === "training" || kind === "complete") {
            training = true
            if (expiresRaw && (!trainingUntil || expiresRaw > trainingUntil)) trainingUntil = expiresRaw
        }
        active.push(hysePremiumGrantPayload(grant))
    }
    return {
        has_nutrition: nutrition,
        has_training: training,
        nutrition_until: nutritionUntil,
        training_until: trainingUntil,
        grants: active
    }
}

// The Studio itself is owner-private. The route intentionally mirrors the
// existing Update Studio endpoint, while the actual code is never returned by
// the list endpoint after the one-time generation response.
routerAdd("GET", "/api/hyse/admin/premium-codes", (c) => {
    const records = $app.dao().findRecordsByFilter("premium_codes", "id != ''", "-created", 250, 0, {})
    return c.json(200, { codes: records.map((record) => ({
        id: record.id,
        code: null,
        preview: String(record.get("code_preview") || ""),
        kind: String(record.get("kind") || ""),
        duration_key: String(record.get("duration_key") || ""),
        duration_days: Number(record.get("duration_days") || 0),
        label: String(record.get("label") || ""),
        created: String(record.created || ""),
        status: String(record.get("redeemed_by") || "") ? "redeemed" : "available"
    })) })
})

routerAdd("POST", "/api/hyse/admin/premium-codes", (c) => {
    const data = $apis.requestInfo(c).data || {}
    const kind = String(data.kind || "")
    if (!["nutrition", "training", "complete"].includes(kind)) throw new BadRequestError("Invalid premium code kind.")
    const durationKey = String(data.duration_key || "")
    const fixedDurations = { one_week: 7, one_month: 30, three_months: 90, six_months: 180, one_year: 365, forever: 0 }
    const durationDays = durationKey === "custom" ? Number(data.duration_days) : fixedDurations[durationKey]
    if (!Number.isInteger(durationDays) || durationDays < 0 || durationDays > 3650 || (durationKey === "custom" && durationDays < 1)) {
        throw new BadRequestError("Invalid premium code duration.")
    }
    const quantity = Math.min(Math.max(Number(data.quantity || 1), 1), 100)
    if (!Number.isInteger(quantity)) throw new BadRequestError("Quantity must be a whole number.")
    const label = String(data.label || "").trim().slice(0, 120)
    const created = []
    const dao = $app.dao()
    const collection = dao.findCollectionByNameOrId("premium_codes")
    const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    const createCode = () => {
        let value = "HYSE"
        for (let position = 0; position < 12; position++) {
            const random = $security.randomString(1)
            value += alphabet[Math.abs(String(random).charCodeAt(0) || Date.now()) % alphabet.length]
            if (position === 3 || position === 7) value += "-"
        }
        return value
    }
    for (let i = 0; i < quantity; i++) {
        let saved = false
        for (let attempt = 0; attempt < 8 && !saved; attempt++) {
            const raw = createCode()
            const hash = String($security.sha256(raw.replace(/[^A-Z0-9]/g, "")))
            try { dao.findFirstRecordByFilter("premium_codes", "code_hash = {:hash}", { hash }); continue } catch (_) {}
            const record = new Record(collection)
            record.set("code_hash", hash)
            record.set("code_preview", raw.slice(-4))
            record.set("kind", kind)
            record.set("duration_key", durationKey)
            record.set("duration_days", durationDays)
            record.set("label", label)
            try {
                dao.saveRecord(record)
                created.push({
                    id: record.id, code: raw, preview: String(record.get("code_preview") || ""), kind,
                    duration_key: durationKey, duration_days: durationDays, label,
                    created: String(record.created || ""), status: "available"
                })
                saved = true
            } catch (_) {
                // A concurrent request can claim the same unique hash. Generate
                // a new code and retry instead of leaking a generic 500 error.
            }
        }
        if (!saved) throw new BadRequestError("A premium code could not be generated. Please try again.")
    }
    return c.json(201, { codes: created })
})

routerAdd("GET", "/api/hyse/premium/entitlements", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const now = Date.now(), grants = $app.dao().findRecordsByFilter("premium_grants", "user = {:user}", "", 100, 0, { user: user.id })
    let nutrition = false, training = false, nutritionUntil = null, trainingUntil = null
    const active = []
    for (const grant of grants) {
        const startsAt = String(grant.get("starts_at") || ""), expiresAt = String(grant.get("expires_at") || "")
        if (Date.parse(startsAt) > now || (expiresAt && Date.parse(expiresAt) <= now)) continue
        const grantKind = String(grant.get("kind") || "")
        if (grantKind === "nutrition" || grantKind === "complete") { nutrition = true; if (expiresAt && (!nutritionUntil || expiresAt > nutritionUntil)) nutritionUntil = expiresAt }
        if (grantKind === "training" || grantKind === "complete") { training = true; if (expiresAt && (!trainingUntil || expiresAt > trainingUntil)) trainingUntil = expiresAt }
        active.push({ kind: grantKind, starts_at: startsAt, expires_at: expiresAt || null })
    }
    return c.json(200, { has_nutrition: nutrition, has_training: training, nutrition_until: nutritionUntil, training_until: trainingUntil, grants: active })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/premium/redeem", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const input = $apis.requestInfo(c).data || {}
    const normalized = String(input.code || "").toUpperCase().replace(/[^A-Z0-9]/g, "")
    if (normalized.length < 8) throw new BadRequestError("Enter a valid Hyse premium code.")
    const hash = $security.sha256(normalized)
    let result = null
    $app.dao().runInTransaction((dao) => {
        let code
        try { code = dao.findFirstRecordByFilter("premium_codes", "code_hash = {:hash}", { hash }) } catch (_) { throw new BadRequestError("This premium code is invalid or has already been used.") }
        if (String(code.get("redeemed_by") || "")) throw new BadRequestError("This premium code has already been used.")
        const kind = String(code.get("kind") || "")
        const days = Number(code.get("duration_days") || 0)
        const startsAt = new Date()
        const expiresAt = days > 0 ? new Date(startsAt.getTime() + days * 86400000) : null
        const grant = new Record(dao.findCollectionByNameOrId("premium_grants"))
        grant.set("user", user.id)
        grant.set("code", code.id)
        grant.set("kind", kind)
        grant.set("starts_at", startsAt.toISOString())
        if (expiresAt) grant.set("expires_at", expiresAt.toISOString())
        dao.saveRecord(grant)
        code.set("redeemed_by", user.id)
        code.set("redeemed_at", startsAt.toISOString())
        dao.saveRecord(code)
        result = { kind, expires_at: expiresAt ? expiresAt.toISOString() : null }
    })
    const grants = $app.dao().findRecordsByFilter("premium_grants", "user = {:user}", "", 100, 0, { user: user.id })
    const now = Date.now(); let nutrition = false, training = false, nutritionUntil = null, trainingUntil = null
    const active = []
    for (const grant of grants) {
        const startsAt = String(grant.get("starts_at") || ""), expiresAt = String(grant.get("expires_at") || "")
        if (Date.parse(startsAt) > now || (expiresAt && Date.parse(expiresAt) <= now)) continue
        const grantKind = String(grant.get("kind") || "")
        if (grantKind === "nutrition" || grantKind === "complete") { nutrition = true; if (expiresAt && (!nutritionUntil || expiresAt > nutritionUntil)) nutritionUntil = expiresAt }
        if (grantKind === "training" || grantKind === "complete") { training = true; if (expiresAt && (!trainingUntil || expiresAt > trainingUntil)) trainingUntil = expiresAt }
        active.push({ kind: grantKind, starts_at: startsAt, expires_at: expiresAt || null })
    }
    return c.json(200, { redeemed: result, entitlements: { has_nutrition: nutrition, has_training: training, nutrition_until: nutritionUntil, training_until: trainingUntil, grants: active } })
}, $apis.requireRecordAuth("users"))
