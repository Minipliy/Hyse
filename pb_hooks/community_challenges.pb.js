/// An opt-in community goal: complete three workouts during the current UTC week.
/// PocketBase runs each route callback in isolation, so each route owns its helpers.
routerAdd("GET", "/api/hyse/gym-communities/:id/challenge", (c) => {
    function currentWeek() {
        const now = new Date()
        const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()))
        start.setUTCDate(start.getUTCDate() - (start.getUTCDay() + 6) % 7)
        return { key: start.toISOString().slice(0, 10), start: start.toISOString(), end: new Date(start.getTime() + 7 * 86400000).toISOString() }
    }
    function member(dao, communityID, userID) {
        try { return dao.findFirstRecordByFilter("gym_community_members", "community = {:community} && user = {:user}", { community: communityID, user: userID }) }
        catch (_) { throw new ForbiddenError("Join this community first.") }
    }
    function status(dao, communityID, userID, membership) {
        const week = currentWeek()
        const participants = dao.findRecordsByFilter("gym_community_members", "community = {:community} && challenge_week = {:week}", "", 1000, 0, { community: communityID, week: week.key })
        let completed = 0, myCount = 0
        for (const participant of participants) {
            const count = dao.findRecordsByFilter("workouts", "user = {:user} && status = 'completed' && completed_at >= {:start} && completed_at < {:end}", "", 3, 0,
                { user: String(participant.get("user")), start: week.start, end: week.end }).length
            if (count >= 3) completed++
            if (String(participant.get("user")) === userID) myCount = count
        }
        return { week: week.key, goal: 3, joined: String(membership.get("challenge_week")) === week.key,
            participants: participants.length, completed, my_count: myCount }
    }
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), communityID = String(c.pathParam("id") || "")
    const membership = member(dao, communityID, user.id)
    return c.json(200, status(dao, communityID, user.id, membership))
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/gym-communities/:id/challenge", (c) => {
    function currentWeek() {
        const now = new Date()
        const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()))
        start.setUTCDate(start.getUTCDate() - (start.getUTCDay() + 6) % 7)
        return { key: start.toISOString().slice(0, 10), start: start.toISOString(), end: new Date(start.getTime() + 7 * 86400000).toISOString() }
    }
    function member(dao, communityID, userID) {
        try { return dao.findFirstRecordByFilter("gym_community_members", "community = {:community} && user = {:user}", { community: communityID, user: userID }) }
        catch (_) { throw new ForbiddenError("Join this community first.") }
    }
    function status(dao, communityID, userID, membership, week) {
        const participants = dao.findRecordsByFilter("gym_community_members", "community = {:community} && challenge_week = {:week}", "", 1000, 0, { community: communityID, week: week.key })
        let completed = 0, myCount = 0
        for (const participant of participants) {
            const count = dao.findRecordsByFilter("workouts", "user = {:user} && status = 'completed' && completed_at >= {:start} && completed_at < {:end}", "", 3, 0,
                { user: String(participant.get("user")), start: week.start, end: week.end }).length
            if (count >= 3) completed++
            if (String(participant.get("user")) === userID) myCount = count
        }
        return { week: week.key, goal: 3, joined: String(membership.get("challenge_week")) === week.key,
            participants: participants.length, completed, my_count: myCount }
    }
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), communityID = String(c.pathParam("id") || "")
    const membership = member(dao, communityID, user.id), week = currentWeek()
    const enabled = (info.data || {}).enabled === true || String((info.data || {}).enabled) === "true"
    membership.set("challenge_week", enabled ? week.key : "")
    dao.saveRecord(membership)
    return c.json(200, status(dao, communityID, user.id, membership, week))
}, $apis.requireRecordAuth("users"))
