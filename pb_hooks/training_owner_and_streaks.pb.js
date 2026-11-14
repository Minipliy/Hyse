/// <reference path="../pb_data/types.d.ts" />

// Ownership is derived from the authenticated request instead of trusting a
// client supplied relation. API rules still provide an independent boundary.
onRecordBeforeCreateRequest((e) => {
    const account = e.httpContext.get("authRecord")
    if (!account) throw new UnauthorizedError("Authentication required.")
    const collection = e.record.collection().name
    e.record.set("user", account.id)
    if (collection === "exercises") e.record.set("created_by", account.id)
}, "exercises", "workout_routines", "routine_exercises", "routine_sets", "workouts", "workout_exercises", "workout_sets", "exercise_favorites")

onRecordBeforeUpdateRequest((e) => {
    const account = e.httpContext.get("authRecord")
    if (!account) throw new UnauthorizedError("Authentication required.")
    const collection = e.record.collection().name
    if (String(e.record.get("user") || "") !== account.id) {
        throw new ForbiddenError("You can only update your own training data.")
    }
    e.record.set("user", account.id)
    if (collection === "exercises") e.record.set("created_by", account.id)

    // A delayed request must never replace a newer offline snapshot.
    if (collection === "exercises" || collection === "workout_routines" || collection === "workouts") {
        const persisted = $app.dao().findRecordById(collection, e.record.id)
        const previous = String(persisted.get("client_updated_at") || "")
        const incoming = String(e.record.get("client_updated_at") || "")
        if (previous && incoming && new Date(incoming).getTime() < new Date(previous).getTime()) {
            throw new BadRequestError("A newer training version is already stored.")
        }
    }
}, "exercises", "workout_routines", "routine_exercises", "routine_sets", "workouts", "workout_exercises", "workout_sets", "exercise_favorites")

function hyseTrainingUTCDate(date) {
    return date.toISOString().slice(0, 10)
}

function hyseRecalculateTrainingStreak(dao, userID) {
    const days = dao.findRecordsByFilter("training_streak_events", "user = {:user}", "day", 5000, 0, { user: userID })
        .map((item) => String(item.get("day"))).sort()
    let longest = 0, run = 0, previous = null
    for (const day of days) {
        const parsed = new Date(day + "T00:00:00.000Z")
        run = previous && parsed.getTime() - previous.getTime() === 86400000 ? run + 1 : 1
        longest = Math.max(longest, run)
        previous = parsed
    }
    const today = hyseTrainingUTCDate(new Date())
    const yesterday = hyseTrainingUTCDate(new Date(Date.now() - 86400000))
    let cursor = days.indexOf(today) >= 0 ? today : (days.indexOf(yesterday) >= 0 ? yesterday : "")
    let current = 0
    while (cursor && days.indexOf(cursor) >= 0) {
        current += 1
        cursor = hyseTrainingUTCDate(new Date(new Date(cursor + "T00:00:00.000Z").getTime() - 86400000))
    }
    let streak = null
    try { streak = dao.findFirstRecordByFilter("training_streaks", "user = {:user}", { user: userID }) } catch (_) {}
    if (!streak) {
        streak = new Record(dao.findCollectionByNameOrId("training_streaks"))
        streak.set("user", userID)
    }
    streak.set("current_streak", current)
    streak.set("longest_streak", longest)
    streak.set("last_valid_training_day", days.length ? days[days.length - 1] : "")
    streak.set("timezone", "UTC")
    dao.saveRecord(streak)
}

function hyseRegisterCompletedWorkout(e) {
    try {
        const userID = String(e.record.get("user") || "")
        if (!userID) return
        const dao = $app.dao()
        if (String(e.record.get("status")) === "completed") {
            const day = hyseTrainingUTCDate(new Date())
            try {
                dao.findFirstRecordByFilter("training_streak_events", "user = {:user} && day = {:day}", { user: userID, day })
            } catch (_) {
                const event = new Record(dao.findCollectionByNameOrId("training_streak_events"))
                event.set("user", userID)
                event.set("workout", e.record.id)
                event.set("day", day)
                dao.saveRecord(event)
            }
        } else {
            const events = dao.findRecordsByFilter("training_streak_events", "workout = {:workout}", "", 100, 0, { workout: e.record.id })
            for (const event of events) dao.deleteRecord(event)
        }
        hyseRecalculateTrainingStreak(dao, userID)
    } catch (_) {}
}

onRecordAfterCreateRequest((e) => {
    require(`${__hooks}/training_streak_helpers.js`).registerCompleted($app.dao(), e.record)
}, "workouts")
onRecordAfterUpdateRequest((e) => {
    require(`${__hooks}/training_streak_helpers.js`).registerCompleted($app.dao(), e.record)
}, "workouts")
onRecordAfterDeleteRequest((e) => {
    const userID = String(e.record.get("user") || "")
    if (userID) require(`${__hooks}/training_streak_helpers.js`).recalculate($app.dao(), userID)
}, "workouts")
