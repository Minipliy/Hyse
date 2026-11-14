function normalizeAudience(value) {
    switch (String(value || "").toLowerCase()) {
    case "training": return "training"
    case "nutrition": return "nutrition"
    default: return "all"
    }
}

function trackingInterestForUser(dao, userID) {
    try {
        const state = dao.findFirstRecordByFilter("user_account_state", "user = {:user}", { user: userID })
        let settings = state.get("settings_json")
        if (typeof settings === "string") {
            try { settings = JSON.parse(settings) } catch (_) { settings = null }
        }
        const interest = String((settings && settings.tracking_interest) || "both")
        return ["nutrition", "training", "both"].indexOf(interest) >= 0 ? interest : "both"
    } catch (_) {
        // Accounts without a synced settings record should continue to receive
        // editorial updates until the person has chosen a narrower audience.
        return "both"
    }
}

function matchesAudience(dao, update, userID) {
    const audience = normalizeAudience(update.get("audience"))
    if (audience === "all") return true
    const interest = trackingInterestForUser(dao, userID)
    return interest === "both" || interest === audience
}

function createNotificationCenterEntries(dao, update) {
    let users = []
    try { users = dao.findRecordsByFilter("users", "id != ''", "", 5000, 0, {}) } catch (_) { return 0 }
    let delivered = 0
    for (const user of users) {
        if (!matchesAudience(dao, update, user.id)) continue
        const dedupe = "hyse_update:" + update.id
        let existing = null
        try { existing = dao.findFirstRecordByFilter("user_notifications", "recipient = {:user} && dedupe_key = {:dedupe}", { user: user.id, dedupe }) } catch (_) {}
        if (existing) continue
        try {
            const notification = new Record(dao.findCollectionByNameOrId("user_notifications"))
            notification.set("recipient", user.id)
            notification.set("type", "hyse_update")
            notification.set("title", String(update.get("title") || "Hyse Update"))
            notification.set("body", String(update.get("body") || ""))
            notification.set("dedupe_key", dedupe)
            notification.set("is_read", false)
            dao.saveRecord(notification)
            delivered++
        } catch (_) {}
    }
    return delivered
}

function deliverHyseUpdate(dao, http, update, gatewayURL, secret) {
    if (!update || !update.get("published")) return { notificationCount: 0, pushDeviceCount: 0 }
    return {
        notificationCount: createNotificationCenterEntries(dao, update),
        pushDeviceCount: 0
    }
}

module.exports = { normalizeAudience, matchesAudience, createNotificationCenterEntries, deliverHyseUpdate }
