/// <reference path="../pb_data/types.d.ts" />

onRecordBeforeCreateRequest((e) => {
    const account = e.httpContext.get("authRecord")
    if (!account) throw new UnauthorizedError("Authentication required.")
    e.record.set("user", account.id)
}, "user_recipes")

onRecordBeforeUpdateRequest((e) => {
    const account = e.httpContext.get("authRecord")
    if (!account) throw new UnauthorizedError("Authentication required.")
    if (String(e.record.get("user") || "") !== account.id) throw new ForbiddenError("You can only update your own recipes.")
    e.record.set("user", account.id)
}, "user_recipes")

// Resolve stable recipe client IDs to relations without trusting a client-owned
// user field. The stable ID still restores the meal if either relation is gone.
const hyseResolveMealRecipe = (e) => {
    // PocketBase 0.22 may execute named record hooks in an isolated JS
    // context. Keep this hook self-contained instead of depending on the
    // module-level helpers used by the HTTP routes.
    const text = (value) => String(value || "").trim().replace(/\s+/g, " ")
    const account = e.httpContext.get("authRecord")
    if (!account) return
    const clientID = text(e.record.get("recipe_client_id"))
    if (!clientID || text(e.record.get("user_recipe"))) return
    try {
        const recipe = $app.dao().findFirstRecordByFilter("user_recipes", "user = {:user} && client_id = {:client}", { user: account.id, client: clientID })
        e.record.set("user_recipe", recipe.id)
    } catch (_) {}
}
onRecordBeforeCreateRequest(hyseResolveMealRecipe, "user_foods")
onRecordBeforeUpdateRequest(hyseResolveMealRecipe, "user_foods")

const hyseBackfillRecipeMeals = (e) => {
    // See hyseResolveMealRecipe: record hooks must not rely on captured
    // module-level constants with the PocketBase 0.22 JS runtime.
    const text = (value) => String(value || "").trim().replace(/\s+/g, " ")
    const userID = text(e.record.get("user"))
    const clientID = text(e.record.get("client_id"))
    if (!userID || !clientID) return
    const meals = $app.dao().findRecordsByFilter("user_foods", "user = {:user} && recipe_client_id = {:client} && user_recipe = ''", "", 0, 0, { user: userID, client: clientID })
    for (const meal of meals) {
        meal.set("user_recipe", e.record.id)
        $app.dao().saveRecord(meal)
    }
}
onRecordAfterCreateRequest(hyseBackfillRecipeMeals, "user_recipes")

routerAdd("POST", "/api/hyse/global-recipes/submit", (c) => {
    const recipes = require(`${__hooks}/recipe_helpers.js`)
    const info = $apis.requestInfo(c)
    const account = info.authRecord
    if (!account) throw new UnauthorizedError("Authentication required.")
    const data = info.data || {}
    const clientID = recipes.text(data.client_id)
    const snapshot = recipes.snapshot(data.snapshot_json)
    const name = recipes.text(snapshot.name)
    if (!clientID || !name || !Array.isArray(snapshot.ingredients) || snapshot.ingredients.length === 0) throw new BadRequestError("A complete recipe is required.")
    const key = recipes.key(snapshot)
    const sourceID = recipes.text(data.source_recipe)
    const dao = $app.dao()

    if (!sourceID) {
        try {
            const duplicate = dao.findFirstRecordByFilter("global_recipes", "normalized_key = {:key} && moderation_status = 'approved'", { key })
            return c.json(200, { submission_id: null, global_recipe_id: duplicate.id, status: "approved", rejection_reason: null })
        } catch (_) {}
    } else {
        const source = dao.findRecordById("global_recipes", sourceID)
        if (String(source.get("moderation_status")) !== "approved") throw new BadRequestError("Only an approved recipe can be revised.")
    }

    let submission = null
    try { submission = dao.findFirstRecordByFilter("global_recipe_submissions", "submitted_by = {:user} && client_id = {:client} && status = 'pending'", { user: account.id, client: clientID }) } catch (_) {}
    if (!submission) submission = new Record(dao.findCollectionByNameOrId("global_recipe_submissions"))
    submission.set("submitted_by", account.id)
    submission.set("source_recipe", sourceID)
    submission.set("client_id", clientID)
    submission.set("normalized_key", key)
    submission.set("status", "pending")
    submission.set("snapshot_json", snapshot)
    submission.set("reviewed_by", "")
    submission.set("reviewed_at", "")
    submission.set("rejection_reason", "")
    dao.saveRecord(submission)
    return c.json(submission.isNew ? 201 : 200, { submission_id: submission.id, global_recipe_id: null, status: "pending", rejection_reason: null })
}, $apis.requireRecordAuth("users"))

// Approval is intentionally admin-only. The approved catalogue record changes
// atomically; until then its previous snapshot remains untouched.
routerAdd("POST", "/api/hyse/global-recipes/submissions/:id/review", (c) => {
    const recipes = require(`${__hooks}/recipe_helpers.js`)
    const info = $apis.requestInfo(c)
    const data = info.data || {}
    const action = recipes.text(data.action)
    if (action !== "approve" && action !== "reject") throw new BadRequestError("Action must be approve or reject.")
    const reason = recipes.text(data.reason)
    if (action === "reject" && !reason) throw new BadRequestError("A rejection reason is required.")
    const submissionID = c.pathParam("id")
    const reviewerID = info.admin ? info.admin.id : "admin"

    $app.dao().runInTransaction((txDao) => {
        const submission = txDao.findRecordById("global_recipe_submissions", submissionID)
        if (String(submission.get("status")) !== "pending") throw new BadRequestError("This submission has already been reviewed.")
        if (action === "approve") {
            const snapshot = recipes.snapshot(submission.get("snapshot_json"))
            const key = recipes.key(snapshot)
            let global = null
            const sourceID = recipes.text(submission.get("source_recipe"))
            if (sourceID) global = txDao.findRecordById("global_recipes", sourceID)
            if (!global) {
                try { global = txDao.findFirstRecordByFilter("global_recipes", "normalized_key = {:key} && moderation_status = 'approved'", { key }) } catch (_) {}
            }
            if (!global) global = new Record(txDao.findCollectionByNameOrId("global_recipes"))
            global.set("creator", submission.get("submitted_by"))
            global.set("client_id", submission.get("client_id"))
            global.set("name", recipes.text(snapshot.name))
            global.set("normalized_key", key)
            global.set("moderation_status", "approved")
            global.set("snapshot_json", snapshot)
            const nutrients = recipes.nutrients(snapshot)
            for (const key in nutrients) global.set(key, nutrients[key])
            txDao.saveRecord(global)
            submission.set("global_recipe", global.id)
        }
        submission.set("status", action === "approve" ? "approved" : "rejected")
        submission.set("reviewed_by", reviewerID)
        submission.set("reviewed_at", new Date().toISOString())
        submission.set("rejection_reason", action === "reject" ? reason : "")
        txDao.saveRecord(submission)
    })
    return c.json(200, { status: action === "approve" ? "approved" : "rejected" })
}, $apis.requireAdminAuth())
