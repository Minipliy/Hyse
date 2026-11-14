/// <reference path="../pb_data/types.d.ts" />

routerAdd("POST", "/api/hyse/notification-preferences", (c) => {
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), data = info.data || {}
    let preferences = null
    try { preferences = dao.findFirstRecordByFilter("notification_preferences", "user = {:user}", { user: user.id }) } catch (_) {}
    const isNew = !preferences
    if (!preferences) preferences = new Record(dao.findCollectionByNameOrId("notification_preferences"))
    preferences.set("user", user.id)
    for (const key of ["hyse_updates", "community_news", "workout_likes", "workout_comments", "friend_activity"]) {
        if (data[key] !== undefined) preferences.set(key, String(data[key]) === "true")
        else if (isNew) preferences.set(key, true)
    }
    dao.saveRecord(preferences)
    return c.json(200, { read: true })
}, $apis.requireRecordAuth("users"))

routerAdd("GET", "/api/hyse/notifications", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao()
    const hyseUpdateDelivery = require(`${__hooks}/hyse_update_push_helpers.js`)
    const updates = dao.findRecordsByFilter("hyse_updates", "published = true", "-created", 100, 0, {})
    for (const update of updates) {
        if (!hyseUpdateDelivery.matchesAudience(dao, update, user.id)) continue
        const dedupe = "hyse_update:" + update.id
        let existing = null
        try { existing = dao.findFirstRecordByFilter("user_notifications", "recipient = {:user} && dedupe_key = {:dedupe}", { user: user.id, dedupe }) } catch (_) {}
        if (!existing) {
            const notification = new Record(dao.findCollectionByNameOrId("user_notifications"))
            notification.set("recipient", user.id); notification.set("type", "hyse_update")
            notification.set("title", String(update.get("title") || "Hyse Update")); notification.set("body", String(update.get("body") || ""))
            notification.set("dedupe_key", dedupe); notification.set("is_read", false); dao.saveRecord(notification)
        }
    }
    const records = dao.findRecordsByFilter("user_notifications", "recipient = {:user}", "-created", 150, 0, { user: user.id })
    const unreadCount = records.filter((record) => !record.get("is_read")).length
    const items = records.map((record) => {
        const actorID = String(record.get("actor") || ""), communityID = String(record.get("community") || ""), workoutID = String(record.get("workout") || "")
        let actor = null, community = null, workout = null
        try { if (actorID) actor = dao.findRecordById("users", actorID) } catch (_) {}
        try { if (communityID) community = dao.findRecordById("gym_communities", communityID) } catch (_) {}
        try { if (workoutID) workout = dao.findRecordById("workouts", workoutID) } catch (_) {}
        const avatar = actor ? String(actor.get("avatar") || "") : ""
        const type = String(record.get("type") || "")
        let isReply = false
        if (type === "workout_comment") {
            const dedupe = String(record.get("dedupe_key") || "")
            if (dedupe.startsWith("workout_comment:")) {
                try {
                    const comment = dao.findRecordById("training_workout_comments", dedupe.slice("workout_comment:".length))
                    const parentID = String(comment.get("reply_to") || "")
                    if (parentID) {
                        const parent = dao.findRecordById("training_workout_comments", parentID)
                        isReply = String(parent.get("user") || "") === user.id
                    }
                } catch (_) {}
            }
        }
        return {
            id: record.id, type, title: String(record.get("title") || ""), body: String(record.get("body") || ""),
            actor_username: actor ? String(actor.get("username") || "") : "", actor_name: actor ? String(actor.get("name") || "") : "", actor_avatar: avatar,
            actor_avatar_url: actor && avatar ? "/api/files/users/" + actorID + "/" + encodeURIComponent(avatar) + "?thumb=128x128" : "",
            community_id: communityID || null, community_name: community ? String(community.get("name") || "") : null,
            workout_id: workoutID || null, workout_name: workout ? String(workout.get("name") || "") : null, is_reply: isReply,
            is_read: !!record.get("is_read"), created: String(record.created || "")
        }
    })
    return c.json(200, { items, unread_count: unreadCount })
}, $apis.requireRecordAuth("users"))

function hyseUpdateBool(value, fallback) {
    if (value === undefined || value === null || value === "") return fallback
    return value === true || String(value).toLowerCase() === "true" || String(value) === "1"
}

function hyseUpdatePayload(update) {
    return {
        id: update.id,
        title: String(update.get("title") || "Hyse Update"),
        body: String(update.get("body") || ""),
        cta: String(update.get("cta") || "Mehr erfahren"),
        audience: String(update.get("audience") || "all"),
        created: String(update.created || "")
    }
}

// This route is deliberately exposed only through Caddy's password-protected
// /hyse-update path. PocketBase itself must remain bound to localhost.
cronAdd("hyse_publish_scheduled_updates", "* * * * *", () => {
    const dao = $app.dao(), now = Date.now()
    let records = []
    try { records = dao.findRecordsByFilter("hyse_updates", "status = 'scheduled'", "", 500, 0, {}) } catch (_) { return }
    for (const update of records) {
        const scheduledFor = Date.parse(String(update.get("scheduled_for") || ""))
        if (!isNaN(scheduledFor) && scheduledFor <= now) {
            update.set("status", "published")
            update.set("published", true)
            update.set("scheduled_for", "")
            dao.saveRecord(update)
            const hyseUpdateDelivery = require(`${__hooks}/hyse_update_push_helpers.js`)
            hyseUpdateDelivery.deliverHyseUpdate(
                dao,
                $http,
                update,
                String($os.getenv("PUSH_GATEWAY_URL") || ""),
                String($os.getenv("PUSH_GATEWAY_SECRET") || "")
            )
        }
    }
})

routerAdd("GET", "/api/hyse/admin/updates", (c) => {
    const dao = $app.dao(), records = dao.findRecordsByFilter("hyse_updates", "id != ''", "-created", 200, 0, {})
    const updates = records.map((update) => ({
        id: update.id, title: String(update.get("title") || "Hyse Update"), body: String(update.get("body") || ""),
        cta: String(update.get("cta") || "Mehr erfahren"), published: !!update.get("published"),
        status: String(update.get("status") || (update.get("published") ? "published" : "draft")),
        scheduled_for: String(update.get("scheduled_for") || ""), show_popup: false,
        show_notification_center: true, audience: String(update.get("audience") || "all"), created: String(update.created || ""), updated: String(update.updated || "")
    }))
    return c.json(200, { updates })
})

routerAdd("POST", "/api/hyse/admin/updates", (c) => {
    const data = $apis.requestInfo(c).data || {}, title = String(data.title || "").trim(), body = String(data.body || "").trim()
    if (!title || !body) throw new BadRequestError("Title and message are required.")
    const status = ["draft", "scheduled", "published"].indexOf(String(data.status || "published")) >= 0 ? String(data.status || "published") : "published"
    const scheduledFor = String(data.scheduled_for || "")
    if (status === "scheduled" && isNaN(Date.parse(scheduledFor))) throw new BadRequestError("A valid publication date is required.")
    const dao = $app.dao(), update = new Record(dao.findCollectionByNameOrId("hyse_updates"))
    update.set("title", title.slice(0, 180)); update.set("body", body.slice(0, 2000)); update.set("cta", String(data.cta || "Mehr erfahren").trim().slice(0, 80))
    update.set("status", status); update.set("published", status === "published"); update.set("scheduled_for", status === "scheduled" ? scheduledFor : "")
    update.set("show_popup", false)
    update.set("show_notification_center", true)
    update.set("audience", require(`${__hooks}/hyse_update_push_helpers.js`).normalizeAudience(data.audience))
    dao.saveRecord(update)
    if (status === "published") {
        const hyseUpdateDelivery = require(`${__hooks}/hyse_update_push_helpers.js`)
        hyseUpdateDelivery.deliverHyseUpdate(
            dao,
            $http,
            update,
            String($os.getenv("PUSH_GATEWAY_URL") || ""),
            String($os.getenv("PUSH_GATEWAY_SECRET") || "")
        )
    }
    return c.json(201, { update: { id: update.id, title: String(update.get("title") || "Hyse Update"), body: String(update.get("body") || ""), cta: String(update.get("cta") || "Mehr erfahren"), status: String(update.get("status") || status), scheduled_for: String(update.get("scheduled_for") || ""), show_popup: false, show_notification_center: true, audience: String(update.get("audience") || "all"), created: String(update.created || ""), updated: String(update.updated || "") } })
})

routerAdd("PATCH", "/api/hyse/admin/updates/:id", (c) => {
    const dao = $app.dao(), data = $apis.requestInfo(c).data || {}, id = String(c.pathParam("id") || "")
    let update; try { update = dao.findRecordById("hyse_updates", id) } catch (_) { throw new NotFoundError("Update not found.") }
    const wasPublished = !!update.get("published")
    const title = String(data.title || "").trim(), body = String(data.body || "").trim(), status = String(data.status || "draft")
    if (!title || !body || ["draft", "scheduled", "published", "archived"].indexOf(status) < 0) throw new BadRequestError("Invalid update data.")
    const scheduledFor = String(data.scheduled_for || "")
    if (status === "scheduled" && isNaN(Date.parse(scheduledFor))) throw new BadRequestError("A valid publication date is required.")
    update.set("title", title.slice(0, 180)); update.set("body", body.slice(0, 2000)); update.set("cta", String(data.cta || "Mehr erfahren").trim().slice(0, 80))
    update.set("status", status); update.set("published", status === "published"); update.set("scheduled_for", status === "scheduled" ? scheduledFor : "")
    update.set("show_popup", false)
    update.set("show_notification_center", true)
    update.set("audience", require(`${__hooks}/hyse_update_push_helpers.js`).normalizeAudience(data.audience))
    dao.saveRecord(update)
    if (!wasPublished && status === "published") {
        const hyseUpdateDelivery = require(`${__hooks}/hyse_update_push_helpers.js`)
        hyseUpdateDelivery.deliverHyseUpdate(
            dao,
            $http,
            update,
            String($os.getenv("PUSH_GATEWAY_URL") || ""),
            String($os.getenv("PUSH_GATEWAY_SECRET") || "")
        )
    }
    return c.json(200, { update: { id: update.id, title: String(update.get("title") || "Hyse Update"), body: String(update.get("body") || ""), cta: String(update.get("cta") || "Mehr erfahren"), status: String(update.get("status") || status), scheduled_for: String(update.get("scheduled_for") || ""), show_popup: false, show_notification_center: true, audience: String(update.get("audience") || "all"), created: String(update.created || ""), updated: String(update.updated || "") } })
})

routerAdd("GET", "/api/hyse/latest-popup", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    return c.json(200, { update: null })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/notifications/read-all", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), records = dao.findRecordsByFilter("user_notifications", "recipient = {:user} && is_read = false", "", 1000, 0, { user: user.id })
    for (const record of records) { record.set("is_read", true); dao.saveRecord(record) }
    return c.json(200, { read: true })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/notifications/:id/read", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), id = String(c.pathParam("id") || "")
    let record
    try { record = dao.findRecordById("user_notifications", id) } catch (_) { throw new NotFoundError("Notification not found.") }
    if (String(record.get("recipient")) !== user.id) throw new ForbiddenError("This notification does not belong to you.")
    record.set("is_read", true); dao.saveRecord(record)
    return c.json(200, { read: true })
}, $apis.requireRecordAuth("users"))

// Publishing from the PocketBase dashboard uses the same reliable delivery
// path as the protected Update Studio.
onRecordAfterCreateRequest((event) => {
    const update = event.record
    if (!update || !update.get("published")) return
    const gatewayURL = String($os.getenv("PUSH_GATEWAY_URL") || ""), secret = String($os.getenv("PUSH_GATEWAY_SECRET") || "")
    const hyseUpdateDelivery = require(`${__hooks}/hyse_update_push_helpers.js`)
    hyseUpdateDelivery.deliverHyseUpdate($app.dao(), $http, update, gatewayURL, secret)
}, "hyse_updates")
