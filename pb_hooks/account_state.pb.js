/// <reference path="../pb_data/types.d.ts" />

routerAdd("GET", "/api/hyse/account-state", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    return c.json(200, require(`${__hooks}/account_state_helpers.js`).response($app.dao(), user.id))
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/account-state", (c) => {
    const info = $apis.requestInfo(c)
    const user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const data = info.data || {}
    const dao = $app.dao()
    const helper = require(`${__hooks}/account_state_helpers.js`)
    const record = helper.record(dao, user.id, true)
    const supportedTerms = ["terms-2026-09-1", "terms-2026-09-2", "terms-2026-09-3", "terms-2026-09-4"]
    const supportedPrivacy = ["privacy-2026-09-1", "privacy-2026-09-2", "privacy-2026-09-3"]

    const terms = String(data.termsVersion || "")
    const privacy = String(data.privacyVersion || "")
    if (terms && supportedTerms.indexOf(terms) < 0) throw new BadRequestError("Unsupported terms version.")
    if (privacy && supportedPrivacy.indexOf(privacy) < 0) throw new BadRequestError("Unsupported privacy version.")
    if (terms && privacy && (!record.get("consented_at") || String(record.get("terms_version")) !== terms || String(record.get("privacy_version")) !== privacy)) {
        record.set("consented_at", new Date().toISOString())
        record.set("consent_language", data.language === "de" ? "de" : "en")
    }
    record.set("terms_version", terms)
    record.set("privacy_version", privacy)
    const nextMarketingConsent = !!data.marketingConsent
    if (record.getBool("marketing_consent") !== nextMarketingConsent || !record.get("marketing_updated_at")) {
        record.set("marketing_updated_at", new Date().toISOString())
        record.set("marketing_consent_language", data.language === "de" ? "de" : "en")
        record.set("marketing_privacy_version", privacy)
    }
    record.set("marketing_consent", nextMarketingConsent)
    // There is no analytics implementation in Hyse. Keep the legacy field
    // explicitly denied instead of recording a consent for a non-existent use.
    record.set("analytics_consent", false)
    record.set("onboarding_version", Math.max(0, Math.min(1000, Number(data.onboardingVersion || 0))))
    if (Array.isArray(data.usage)) record.set("usage_json", data.usage.slice(0, 500))
    if (data.settings && typeof data.settings === "object") {
        const currentSettings = record.get("settings_json")
        // Older app versions do not send meal categories. Preserve the newer
        // account value when those clients update another preference.
        if (!Array.isArray(data.settings.mealCategories) && currentSettings && Array.isArray(currentSettings.mealCategories)) {
            data.settings.mealCategories = currentSettings.mealCategories
        }
        // Settings writes can arrive out of order when the app is backgrounded
        // or when two devices are syncing. Do not let an older request replace
        // a newer complete snapshot. Legacy snapshots without a timestamp are
        // still accepted for backwards compatibility.
        const settingsTimestamp = (value) => {
            // Swift's default JSONEncoder represents Date as seconds after its
            // 2001 reference date, whereas older clients may send ISO strings.
            if (typeof value === "number" && Number.isFinite(value)) {
                return Date.UTC(2001, 0, 1) + value * 1000
            }
            return Date.parse(String(value || ""))
        }
        const incomingUpdatedAt = settingsTimestamp(data.settings.updatedAt)
        const currentUpdatedAt = currentSettings && typeof currentSettings === "object"
            ? settingsTimestamp(currentSettings.updatedAt)
            : NaN
        const isStaleSettingsWrite = Number.isFinite(incomingUpdatedAt)
            && Number.isFinite(currentUpdatedAt)
            && incomingUpdatedAt < currentUpdatedAt
        if (!isStaleSettingsWrite) record.set("settings_json", data.settings)
    }
    dao.saveRecord(record)
    return c.json(200, helper.response(dao, user.id))
}, $apis.requireRecordAuth("users"))
