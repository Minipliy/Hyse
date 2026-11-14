/// <reference path="../pb_data/types.d.ts" />

function hyseDayAtOffset(date, offsetMinutes) {
    return new Date(date.getTime() + offsetMinutes * 60000).toISOString().slice(0, 10)
}

function hyseRecalculateStreak(dao, userID, offsetMinutes) {
    const days = dao.findRecordsByFilter("streak_events", "user = {:user}", "day", 5000, 0, { user: userID }).map((item) => String(item.get("day"))).sort()
    let longest = 0, run = 0, previous = null
    for (const day of days) {
        const parsed = new Date(day + "T00:00:00.000Z")
        if (previous && parsed.getTime() - previous.getTime() === 86400000) run += 1
        else run = 1
        if (run > longest) longest = run
        previous = parsed
    }
    const today = hyseDayAtOffset(new Date(), offsetMinutes)
    const yesterday = hyseDayAtOffset(new Date(Date.now() - 86400000), offsetMinutes)
    let current = 0
    let cursor = days.indexOf(today) >= 0 ? today : (days.indexOf(yesterday) >= 0 ? yesterday : "")
    while (cursor && days.indexOf(cursor) >= 0) {
        current += 1
        cursor = new Date(new Date(cursor + "T00:00:00.000Z").getTime() - 86400000).toISOString().slice(0, 10)
    }
    let streak = null
    try { streak = dao.findFirstRecordByFilter("user_streaks", "user = {:user}", { user: userID }) } catch (_) {}
    if (!streak) { streak = new Record(dao.findCollectionByNameOrId("user_streaks")); streak.set("user", userID) }
    streak.set("current", current); streak.set("longest", longest); streak.set("last_day", days.length ? days[days.length - 1] : "")
    dao.saveRecord(streak)
}

onRecordAfterCreateRequest((e) => {
    try {
        if (String(e.record.get("record_type")) !== "entry") return
        const userID = String(e.record.get("user") || "")
        const offset = Math.max(-720, Math.min(840, Number(e.record.get("timezone_offset") || 0)))
        const localDay = String(e.record.get("local_day") || "")
        // Only a newly-created entry for the server's current local day earns an event.
        if (!userID || localDay !== hyseDayAtOffset(new Date(), offset)) return
        const dao = $app.dao()
        try { dao.findFirstRecordByFilter("streak_events", "user = {:user} && day = {:day}", { user: userID, day: localDay }); return } catch (_) {}
        const event = new Record(dao.findCollectionByNameOrId("streak_events"))
        event.set("user", userID); event.set("day", localDay); dao.saveRecord(event)
        hyseRecalculateStreak(dao, userID, offset)
    } catch (_) {}
}, "user_foods")
