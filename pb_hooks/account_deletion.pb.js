/// <reference path="../pb_data/types.d.ts" />

// Deletes the authenticated Hyse account together with all account-bound
// backend records. Local app data remains on the device and can be removed
// separately by the user.
routerAdd("DELETE", "/api/hyse/account", (c) => {
    const authRecord = $apis.requestInfo(c).authRecord
    if (!authRecord) {
        throw new UnauthorizedError("Authentication required.")
    }

    $app.dao().runInTransaction((txDao) => {
        const accountCollections = [
            { name: "workout_sets", field: "user" },
            { name: "workout_exercises", field: "user" },
            { name: "workouts", field: "user" },
            { name: "routine_sets", field: "user" },
            { name: "routine_exercises", field: "user" },
            { name: "workout_routines", field: "user" },
            { name: "exercise_favorites", field: "user" },
            { name: "exercises", field: "user" },
            { name: "training_streak_events", field: "user" },
            { name: "training_streaks", field: "user" },
            { name: "consumed_foods", field: "user" },
            { name: "user_foods", field: "user" },
            { name: "user_favorites", field: "user" },
            { name: "user_consents", field: "user" },
            { name: "food_portions", field: "owner" },
            { name: "user_recipes", field: "user" },
            { name: "daily_food_schedules", field: "user" },
            { name: "global_recipe_submissions", field: "submitted_by" },
            { name: "global_recipes", field: "creator" },
            { name: "user_data", field: "owner" },
            { name: "content_reports", field: "reporter" }
        ]

        for (const item of accountCollections) {
            try {
                txDao.findCollectionByNameOrId(item.name)
            } catch (error) {
                // Collections differ between existing installations.
                continue
            }

            const records = txDao.findRecordsByFilter(
                item.name,
                item.field + " = '" + authRecord.id + "'",
                "",
                0,
                0
            )
            for (const record of records) {
                txDao.deleteRecord(record)
            }
        }

        // Pending/rejected brand proposals are account-bound. Approved brands
        // stay globally reusable but are anonymised when their contributor
        // deletes the account.
        try {
            const brands = txDao.findRecordsByFilter("global_brands", "created_by = {:user}", "", 0, 0, { user: authRecord.id })
            for (const brand of brands) {
                if (String(brand.get("status")) === "approved") {
                    brand.set("created_by", "")
                    txDao.saveRecord(brand)
                } else {
                    txDao.deleteRecord(brand)
                }
            }
        } catch (_) {}

        txDao.deleteRecord(authRecord)
    })

    return c.noContent(204)
}, $apis.requireRecordAuth("users"))
