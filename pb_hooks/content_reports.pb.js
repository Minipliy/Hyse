/// <reference path="../pb_data/types.d.ts" />

// DSA Article 16 notice-and-action endpoint plus an Article 20-style internal
// complaint/appeal path. Direct collection rules stay closed so a client can
// never alter a report or its moderation decision by talking to PocketBase.
routerAdd("POST", "/api/hyse/reports", (c) => {
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const reportReasons = ["illegal", "harassment", "hate", "sexual", "violence", "privacy", "spam", "intellectual_property", "other"]
    const targetTypes = ["user", "avatar", "community", "community_post", "workout", "workout_comment"]
    const data = info.data || {}
    const targetType = String(data.target_type || "")
    const targetID = String(data.target_id || "").trim()
    const reason = String(data.reason || "")
    const details = String(data.details || "").trim()
    const goodFaith = data.good_faith === true || String(data.good_faith || "") === "true"
    if (targetTypes.indexOf(targetType) < 0 || !targetID) throw new BadRequestError("Choose a valid item to report.")
    if (reportReasons.indexOf(reason) < 0) throw new BadRequestError("Choose a valid report reason.")
    if (details.length < 10 || details.length > 2000) throw new BadRequestError("Please explain the report in 10–2000 characters.")
    if (!goodFaith) throw new BadRequestError("Confirm that the report is submitted in good faith.")

    const dao = $app.dao()
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
    const recent = dao.findRecordsByFilter("content_reports", "reporter = {:reporter} && created >= {:since}", "", 51, 0, { reporter: user.id, since })
    if (recent.length >= 50) throw new BadRequestError("Daily report limit reached. Please try again later.")

    let label = "", excerpt = ""
    const find = (name, id) => { try { return dao.findRecordById(name, id) } catch (_) { return null } }
    if (targetType === "user" || targetType === "avatar") {
        const target = find("users", targetID)
        if (!target) throw new NotFoundError("User not found.")
        if (targetType === "avatar" && !String(target.get("avatar") || "")) throw new BadRequestError("This profile has no profile picture.")
        label = "@" + String(target.get("username") || "Hyse user")
    } else if (targetType === "community") {
        const target = find("gym_communities", targetID)
        if (!target) throw new NotFoundError("Community not found.")
        label = String(target.get("name") || "Gym Community")
        excerpt = String(target.get("description") || "").slice(0, 1000)
    } else if (targetType === "community_post") {
        const target = find("gym_community_posts", targetID)
        if (!target) throw new NotFoundError("Message not found.")
        label = "Community message"
        excerpt = String(target.get("body") || "").slice(0, 1000)
    } else if (targetType === "workout") {
        const target = find("workouts", targetID)
        if (!target) throw new NotFoundError("Workout not found.")
        if (String(target.get("user") || "") !== user.id && String(target.get("visibility") || "private") !== "public") throw new ForbiddenError("This workout is private.")
        label = String(target.get("name") || "Workout")
    } else if (targetType === "workout_comment") {
        const target = find("training_workout_comments", targetID)
        if (!target) throw new NotFoundError("Comment not found.")
        const workout = find("workouts", String(target.get("workout") || ""))
        if (!workout) throw new NotFoundError("Workout not found.")
        if (String(workout.get("user") || "") !== user.id && String(workout.get("visibility") || "private") !== "public") throw new ForbiddenError("This workout is private.")
        label = "Training comment"; excerpt = String(target.get("body") || "").slice(0, 1000)
    }

    let duplicate = null
    try { duplicate = dao.findFirstRecordByFilter("content_reports", "reporter = {:reporter} && target_type = {:target_type} && target_id = {:target_id} && status != 'closed'", { reporter: user.id, target_type: targetType, target_id: targetID }) } catch (_) {}
    if (duplicate) return c.json(200, {
        report: { id: duplicate.id, target_type: targetType, target_id: targetID, target_label: String(duplicate.get("target_label") || label), reason: String(duplicate.get("reason") || reason), status: String(duplicate.get("status")), decision_code: String(duplicate.get("decision_code") || ""), decision_reason: String(duplicate.get("decision_reason") || ""), appeal_details: String(duplicate.get("appeal_details") || ""), created: String(duplicate.created || ""), updated: String(duplicate.updated || "") },
        duplicate: true
    })

    const report = new Record(dao.findCollectionByNameOrId("content_reports"))
    report.set("reporter", user.id); report.set("target_type", targetType); report.set("target_id", targetID)
    report.set("target_label", label); report.set("target_excerpt", excerpt); report.set("reason", reason)
    report.set("details", details); report.set("good_faith", true); report.set("status", "pending")
    report.set("decision_code", ""); report.set("decision_reason", ""); report.set("appeal_details", "")
    dao.saveRecord(report)
    return c.json(201, {
        report: { id: report.id, target_type: targetType, target_id: targetID, target_label: label, reason, status: "pending", decision_code: "", decision_reason: "", appeal_details: "", created: String(report.created || ""), updated: String(report.updated || "") },
        duplicate: false
    })
}, $apis.requireRecordAuth("users"))

routerAdd("GET", "/api/hyse/reports", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao()
    const records = dao.findRecordsByFilter("content_reports", "reporter = {:reporter}", "-created", 100, 0, { reporter: user.id })
    return c.json(200, { reports: records.map((record) => ({
        id: record.id, target_type: String(record.get("target_type") || ""), target_id: String(record.get("target_id") || ""),
        target_label: String(record.get("target_label") || ""), reason: String(record.get("reason") || ""), status: String(record.get("status") || "pending"),
        decision_code: String(record.get("decision_code") || ""), decision_reason: String(record.get("decision_reason") || ""),
        appeal_details: String(record.get("appeal_details") || ""), created: String(record.created || ""), updated: String(record.updated || "")
    })) })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/reports/:id/appeal", (c) => {
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), reportID = String(c.pathParam("id") || ""), details = String((info.data || {}).details || "").trim()
    if (details.length < 10 || details.length > 2000) throw new BadRequestError("Please explain the appeal in 10–2000 characters.")
    let report
    try { report = dao.findRecordById("content_reports", reportID) } catch (_) { throw new NotFoundError("Report not found.") }
    if (String(report.get("reporter")) !== user.id) throw new ForbiddenError("This report does not belong to you.")
    const status = String(report.get("status") || "pending")
    if (["pending", "under_review", "appealed"].indexOf(status) >= 0) throw new BadRequestError("This report is still being reviewed.")
    report.set("appeal_details", details); report.set("appealed_at", new Date().toISOString()); report.set("status", "appealed")
    dao.saveRecord(report)
    return c.json(200, { report: {
        id: report.id, target_type: String(report.get("target_type") || ""), target_id: String(report.get("target_id") || ""), target_label: String(report.get("target_label") || ""),
        reason: String(report.get("reason") || "other"), status: "appealed", decision_code: String(report.get("decision_code") || ""), decision_reason: String(report.get("decision_reason") || ""),
        appeal_details: details, created: String(report.created || ""), updated: String(report.updated || "")
    } })
}, $apis.requireRecordAuth("users"))
