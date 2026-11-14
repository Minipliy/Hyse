function utcDate(date) { return date.toISOString().slice(0, 10) }

function recalculate(dao, userID) {
    const days = dao.findRecordsByFilter("training_streak_events", "user = {:user}", "day", 5000, 0, { user: userID })
        .map((item) => String(item.get("day"))).sort()
    let longest = 0, run = 0, previous = null
    for (const day of days) {
        const parsed = new Date(day + "T00:00:00.000Z")
        run = previous && parsed.getTime() - previous.getTime() === 86400000 ? run + 1 : 1
        longest = Math.max(longest, run); previous = parsed
    }
    const today = utcDate(new Date()), yesterday = utcDate(new Date(Date.now() - 86400000))
    let cursor = days.indexOf(today) >= 0 ? today : (days.indexOf(yesterday) >= 0 ? yesterday : ""), current = 0
    while (cursor && days.indexOf(cursor) >= 0) {
        current += 1
        cursor = utcDate(new Date(new Date(cursor + "T00:00:00.000Z").getTime() - 86400000))
    }
    let streak = null
    try { streak = dao.findFirstRecordByFilter("training_streaks", "user = {:user}", { user: userID }) } catch (_) {}
    if (!streak) { streak = new Record(dao.findCollectionByNameOrId("training_streaks")); streak.set("user", userID) }
    streak.set("current_streak", current); streak.set("longest_streak", longest)
    streak.set("last_valid_training_day", days.length ? days[days.length - 1] : ""); streak.set("timezone", "UTC")
    dao.saveRecord(streak)
}

function registerCompleted(dao, record) {
    const userID = String(record.get("user") || "")
    if (!userID) return
    if (String(record.get("status")) === "completed") {
        const day = utcDate(new Date())
        try { dao.findFirstRecordByFilter("training_streak_events", "user = {:user} && day = {:day}", { user: userID, day }) }
        catch (_) {
            const event = new Record(dao.findCollectionByNameOrId("training_streak_events"))
            event.set("user", userID); event.set("workout", record.id); event.set("day", day); dao.saveRecord(event)
        }
    } else {
        const events = dao.findRecordsByFilter("training_streak_events", "workout = {:workout}", "", 100, 0, { workout: record.id })
        for (const event of events) dao.deleteRecord(event)
    }
    recalculate(dao, userID)
}

module.exports = { recalculate, registerCompleted }
