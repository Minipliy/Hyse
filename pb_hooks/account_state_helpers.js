function record(dao, userID, create) {
    try { return dao.findFirstRecordByFilter("user_account_state", "user = {:user}", { user: userID }) }
    catch (_) { if (!create) return null; const value = new Record(dao.findCollectionByNameOrId("user_account_state")); value.set("user", userID); return value }
}

function response(dao, userID) {
    const value = record(dao, userID, false)
    let streakDays = []
    try { streakDays = dao.findRecordsByFilter("streak_events", "user = {:user}", "day", 5000, 0, { user: userID }).map((item) => String(item.get("day"))) } catch (_) {}
    if (!value) return { streakDays }
    return {
        termsVersion: String(value.get("terms_version") || ""), privacyVersion: String(value.get("privacy_version") || ""), consentTimestamp: String(value.get("consented_at") || ""),
        consentLanguage: String(value.get("consent_language") || "en"), marketingConsent: value.getBool("marketing_consent"), marketingConsentUpdatedAt: String(value.get("marketing_updated_at") || ""),
        marketingConsentLanguage: String(value.get("marketing_consent_language") || "en"), marketingConsentPrivacyVersion: String(value.get("marketing_privacy_version") || ""),
        onboardingVersion: Number(value.get("onboarding_version") || 0), usage: value.get("usage_json") || [], settings: value.get("settings_json") || null, streakDays
    }
}

module.exports = { record, response }
