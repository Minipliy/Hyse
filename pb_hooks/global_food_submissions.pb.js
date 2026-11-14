/// <reference path="../pb_data/types.d.ts" />

routerAdd("POST", "/api/hyse/global-foods/submit-new", (c) => {
    const foods = require(`${__hooks}/global_food_submission_helpers.js`)
    const info = $apis.requestInfo(c); const account = info.authRecord
    if (!account) throw new UnauthorizedError("Authentication required.")
    const data = info.data || {}; const clientID = foods.text(data.client_id)
    if (!/^[0-9a-fA-F-]{36}$/.test(clientID)) throw new BadRequestError("A stable personal food client ID is required.")
    const dao = $app.dao()
    let submission = null
    try { submission = dao.findFirstRecordByFilter("global_food_submissions", "submitted_by = {:user} && personal_food_client_id = {:client} && submission_kind = 'create' && status = 'pending'", { user: account.id, client: clientID }) } catch (_) {}
    const created = !submission
    if (!submission) submission = new Record(dao.findCollectionByNameOrId("global_food_submissions"))
    submission.set("submitted_by", account.id); submission.set("source_food", ""); submission.set("client_id", clientID)
    submission.set("personal_food_client_id", clientID); submission.set("submission_kind", "create"); submission.set("migration_origin", "")
    foods.fillSubmission(submission, data)

    // User-created foods are published immediately. Reuse a matching global
    // row so repeated uploads and edits stay idempotent instead of creating
    // barcode or nutrition duplicates.
    const barcode = foods.barcode(submission.get("barcode")); const normalizedKey = foods.key(submission)
    let target = null
    if (barcode) {
        try { target = dao.findFirstRecordByFilter("global_foods", "barcode_normalized = {:barcode} && moderation_status = 'approved'", { barcode }) } catch (_) {}
    }
    if (!target) {
        try { target = dao.findFirstRecordByFilter("global_foods", "normalized_key = {:key} && moderation_status = 'approved'", { key: normalizedKey }) } catch (_) {}
    }
    if (!target) target = new Record(dao.findCollectionByNameOrId("global_foods"))
    const isExternalTarget = ["open_food_facts", "manufacturer"].includes(String(target.get("source") || ""))
    if (!isExternalTarget) {
        for (const key of foods.snapshotFields) target.set(key, submission.get(key))
        const brand = foods.resolveGlobalBrand(dao, data.brand_id, submission.get("brand"), account.id)
        target.set("brand_relation", brand ? brand.id : "")
        if (brand) target.set("brand", String(brand.get("name")))
        target.set("barcode_raw", submission.get("barcode")); target.set("barcode_normalized", barcode)
        if (!String(target.get("creator") || "")) target.set("creator", account.id)
        target.set("source", "user"); target.set("moderation_status", "approved"); target.set("normalized_key", normalizedKey)
        dao.saveRecord(target)
    }

    submission.set("source_food", target.id); submission.set("status", "approved"); submission.set("reviewed_by", account.id)
    submission.set("reviewed_at", new Date().toISOString()); submission.set("rejection_reason", "")
    dao.saveRecord(submission)

    // Link immediately when the personal sync won the race; otherwise the
    // client persists this relation on its next saved-food sync.
    try {
        const personal = dao.findFirstRecordByFilter("user_foods", "user = {:user} && record_type = 'saved' && client_id = {:client}", { user: account.id, client: clientID })
        personal.set("global_food", target.id); personal.set("global_submission", submission.id); dao.saveRecord(personal)
    } catch (_) {}
    return c.json(created ? 201 : 200, { id: submission.id, status: "approved", global_food: target.id, rejection_reason: "" })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/global-foods/submit-change", (c) => {
    const foods = require(`${__hooks}/global_food_submission_helpers.js`)
    const info = $apis.requestInfo(c); const account = info.authRecord
    if (!account) throw new UnauthorizedError("Authentication required.")
    const data = info.data || {}; const sourceID = foods.text(data.source_food); const clientID = foods.text(data.client_id)
    if (!sourceID || !clientID) throw new BadRequestError("Source food and client ID are required.")
    const dao = $app.dao(); const source = dao.findRecordById("global_foods", sourceID)
    if (String(source.get("moderation_status") || "approved") !== "approved") throw new BadRequestError("Only approved foods can be revised.")
    if (["open_food_facts", "manufacturer"].includes(String(source.get("source") || ""))) throw new BadRequestError("External source records cannot be republished as Hyse data.")
    let submission = null
    try { submission = dao.findFirstRecordByFilter("global_food_submissions", "submitted_by = {:user} && source_food = {:source} && submission_kind = 'update' && status = 'pending'", { user: account.id, source: sourceID }) } catch (_) {}
    const created = !submission
    if (!submission) submission = new Record(dao.findCollectionByNameOrId("global_food_submissions"))
    submission.set("submitted_by", account.id); submission.set("source_food", sourceID); submission.set("client_id", clientID)
    submission.set("personal_food_client_id", clientID); submission.set("submission_kind", "update"); submission.set("base_updated", source.get("updated"))
    foods.fillSubmission(submission, data)

    for (const key of foods.snapshotFields) source.set(key, submission.get(key))
    const brand = foods.resolveGlobalBrand(dao, data.brand_id, submission.get("brand"), account.id)
    source.set("brand_relation", brand ? brand.id : "")
    if (brand) source.set("brand", String(brand.get("name")))
    const barcode = foods.barcode(submission.get("barcode"))
    source.set("barcode_raw", submission.get("barcode")); source.set("barcode_normalized", barcode)
    source.set("source", "user"); source.set("moderation_status", "approved"); source.set("normalized_key", foods.key(submission))
    dao.saveRecord(source)

    submission.set("status", "approved"); submission.set("reviewed_by", account.id)
    submission.set("reviewed_at", new Date().toISOString()); submission.set("rejection_reason", "")
    dao.saveRecord(submission)
    try {
        const personal = dao.findFirstRecordByFilter("user_foods", "user = {:user} && record_type = 'saved' && client_id = {:client}", { user: account.id, client: clientID })
        personal.set("global_food", source.id); personal.set("global_submission", submission.id); dao.saveRecord(personal)
    } catch (_) {}
    return c.json(created ? 201 : 200, { id: submission.id, status: "approved", global_food: source.id, rejection_reason: "" })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/global-foods/submissions/:id/review", (c) => {
    const foods = require(`${__hooks}/global_food_submission_helpers.js`)
    const info = $apis.requestInfo(c); const data = info.data || {}; const action = foods.text(data.action)
    if (action !== "approve" && action !== "reject") throw new BadRequestError("Action must be approve or reject.")
    const reason = foods.text(data.reason)
    if (action === "reject" && !reason) throw new BadRequestError("A rejection reason is required.")
    const submissionID = c.pathParam("id"); const reviewerID = info.admin ? info.admin.id : "admin"
    let approvedGlobalID = ""
    $app.dao().runInTransaction((txDao) => {
        const submission = txDao.findRecordById("global_food_submissions", submissionID)
        if (String(submission.get("status")) !== "pending") throw new BadRequestError("This submission has already been reviewed.")
        const kind = String(submission.get("submission_kind") || "update")
        if (action === "approve") {
            const barcode = foods.barcode(submission.get("barcode")); const normalizedKey = foods.key(submission)
            let target = null; let duplicate = false
            const sourceID = foods.text(submission.get("source_food"))
            if (kind === "update") {
                if (!sourceID) throw new BadRequestError("Update submission has no source food.")
                target = txDao.findRecordById("global_foods", sourceID)
                if (["open_food_facts", "manufacturer"].includes(String(target.get("source") || ""))) throw new BadRequestError("External source records cannot be republished as Hyse data.")
            } else if (sourceID) {
                // Safe legacy migration: the original pending row was retained
                // as rollback data and becomes public only at this point.
                target = txDao.findRecordById("global_foods", sourceID)
            } else {
                if (barcode) {
                    try { target = txDao.findFirstRecordByFilter("global_foods", "barcode_normalized = {:barcode} && moderation_status = 'approved'", { barcode }) } catch (_) {}
                }
                if (!target) {
                    try { target = txDao.findFirstRecordByFilter("global_foods", "normalized_key = {:key} && moderation_status = 'approved'", { key: normalizedKey }) } catch (_) {}
                }
                duplicate = !!target
                if (!target) target = new Record(txDao.findCollectionByNameOrId("global_foods"))
            }
            if (!duplicate) {
                for (const key of foods.snapshotFields) target.set(key, submission.get(key))
                target.set("barcode_raw", submission.get("barcode")); target.set("barcode_normalized", barcode)
                target.set("creator", submission.get("submitted_by")); target.set("source", "user"); target.set("moderation_status", "approved"); target.set("normalized_key", normalizedKey)
                txDao.saveRecord(target)
            }
            approvedGlobalID = target.id; submission.set("source_food", target.id)
            const userID = String(submission.get("submitted_by") || ""); const clientID = String(submission.get("personal_food_client_id") || submission.get("client_id") || "")
            if (userID && clientID) {
                try {
                    const personal = txDao.findFirstRecordByFilter("user_foods", "user = {:user} && record_type = 'saved' && client_id = {:client}", { user: userID, client: clientID })
                    personal.set("global_food", target.id); personal.set("global_submission", submission.id); txDao.saveRecord(personal)
                } catch (_) {}
            }
        }
        submission.set("status", action === "approve" ? "approved" : "rejected"); submission.set("reviewed_by", reviewerID)
        submission.set("reviewed_at", new Date().toISOString()); submission.set("rejection_reason", action === "reject" ? reason : ""); txDao.saveRecord(submission)
    })
    return c.json(200, { status: action === "approve" ? "approved" : "rejected", global_food: approvedGlobalID })
}, $apis.requireAdminAuth())
