/// <reference path="../pb_data/types.d.ts" />

routerAdd("GET", "/api/hyse/social/profile", (c) => {
    // PocketBase 0.22 evaluates registered route callbacks in isolated JS
    // contexts. Keep every callback self-contained; module-level helpers are
    // not available once an authenticated request is executed.
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    return c.json(200, { id: user.id, username: String(user.get("username") || ""), nickname: String(user.get("name") || ""), avatar: String(user.get("avatar") || ""), bio: String(user.get("social_bio") || ""), website: String(user.get("social_website") || "") })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/social/details", (c) => {
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const bio = String((info.data || {}).bio || "").trim()
    const website = String((info.data || {}).website || "").trim()
    if (bio.length > 160) throw new BadRequestError("Bio must contain at most 160 characters.")
    if (website.length > 200 || (website && !/^https:\/\/[a-z0-9.-]+(?::[0-9]+)?(?:[/?#][^\s]*)?$/i.test(website))) {
        throw new BadRequestError("Website must be a valid HTTPS URL.")
    }
    user.set("social_bio", bio)
    user.set("social_website", website)
    $app.dao().saveRecord(user)
    return c.json(200, { bio, website })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/social/nickname", (c) => {
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const nickname = String((info.data || {}).nickname || "").trim().replace(/\s+/g, " ")
    if (nickname.length > 32) throw new BadRequestError("Nickname must contain at most 32 characters.")
    user.set("name", nickname)
    $app.dao().saveRecord(user)
    return c.json(200, { id: user.id, username: String(user.get("username") || ""), nickname })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/social/username", (c) => {
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const username = String((info.data || {}).username || "").trim().toLowerCase()
    if (!/^[a-z0-9_]{3,24}$/.test(username)) throw new BadRequestError("Username must contain 3–24 letters, numbers, or underscores.")
    const dao = $app.dao()
    let duplicate = null
    try { duplicate = dao.findFirstRecordByFilter("users", "username = {:username} && id != {:id}", { username, id: user.id }) } catch (_) {}
    if (duplicate) throw new BadRequestError("Username is already in use.")
    user.set("username", username)
    dao.saveRecord(user)
    return c.json(200, { id: user.id, username })
}, $apis.requireRecordAuth("users"))

routerAdd("GET", "/api/hyse/social/search", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const query = String(c.queryParam("q") || "").trim().toLowerCase().slice(0, 24)
    if (query.length < 2) return c.json(200, { items: [] })
    const dao = $app.dao()
    const relationships = dao.findRecordsByFilter("training_friendships", "requester = {:user} || recipient = {:user}", "-updated", 500, 0, { user: user.id })
    const stateByUser = {}
    for (const relation of relationships) {
        const requester = String(relation.get("requester")), recipient = String(relation.get("recipient"))
        const other = requester === user.id ? recipient : requester
        const status = String(relation.get("status"))
        stateByUser[other] = status === "accepted" ? "friends" : (requester === user.id ? "requested" : "incoming")
    }
    const users = dao.findRecordsByFilter("users", "username ~ {:query} && id != {:id}", "username", 20, 0, { query, id: user.id })
    return c.json(200, { items: users.map((item) => {
        const avatar = String(item.get("avatar") || "")
        return { id: item.id, username: String(item.get("username") || ""), nickname: String(item.get("name") || ""), avatar, avatar_url: avatar ? "/api/files/users/" + item.id + "/" + encodeURIComponent(avatar) + "?thumb=256x256" : "", state: stateByUser[item.id] || "none" }
    }) })
}, $apis.requireRecordAuth("users"))

routerAdd("GET", "/api/hyse/social/users/:id", (c) => {
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const targetID = String(c.pathParam("id") || "")
    if (!targetID) throw new NotFoundError("User not found.")
    const dao = $app.dao()
    let target
    try { target = dao.findRecordById("users", targetID) } catch (_) { throw new NotFoundError("User not found.") }

    let state = targetID === user.id ? "self" : "none"
    if (targetID !== user.id) {
        const pair = [String(user.id), targetID].sort().join(":")
        try {
            const relation = dao.findFirstRecordByFilter("training_friendships", "pair_key = {:pair}", { pair })
            const status = String(relation.get("status"))
            state = status === "accepted"
                ? "friends"
                : (String(relation.get("requester")) === user.id ? "requested" : "incoming")
        } catch (_) {}
    }

    const avatar = String(target.get("avatar") || "")
    const publicWorkouts = dao.findRecordsByFilter(
        "workouts",
        "user = {:user} && status = 'completed' && visibility = 'public'",
        "-completed_at",
        0,
        0,
        { user: targetID }
    )
    const workouts = publicWorkouts.slice(0, 30).map((workout) => {
        const likes = dao.findRecordsByFilter("training_workout_likes", "workout = {:workout}", "", 1000, 0, { workout: workout.id })
        const comments = dao.findRecordsByFilter("training_workout_comments", "workout = {:workout}", "", 1000, 0, { workout: workout.id })
        const snapshot = workout.get("snapshot_json") || {}
        const exercises = Array.isArray(snapshot.exercises) ? snapshot.exercises : []
        return {
            id: workout.id,
            client_id: String(workout.get("client_id") || ""),
            user_id: targetID,
            username: String(target.get("username") || ""),
            avatar,
            avatar_url: avatar ? "/api/files/users/" + targetID + "/" + encodeURIComponent(avatar) + "?thumb=256x256" : "",
            name: String(workout.get("name") || "Workout"),
            notes: String(workout.get("notes") || ""),
            media_url: workout.get("media") ? "/api/files/workouts/" + workout.id + "/" + encodeURIComponent(String(workout.get("media"))) : "",
            completed_at: String(workout.get("completed_at") || workout.get("started_at") || ""),
            duration: Number(workout.get("duration") || 0),
            total_volume: Number(workout.get("total_volume") || 0),
            exercise_preview: exercises.slice(0, 3).map((exercise) => ({
                name: String(exercise.exerciseNameSnapshot || ""),
                german_name: String(exercise.exerciseGermanNameSnapshot || ""),
                set_count: Array.isArray(exercise.sets) ? exercise.sets.filter((set) => set.completed === true).length : 0
            })),
            like_count: likes.length,
            comment_count: comments.length,
            liked_by_me: likes.some((like) => String(like.get("user")) === user.id)
        }
    })

    const monday = new Date()
    monday.setUTCHours(0, 0, 0, 0)
    monday.setUTCDate(monday.getUTCDate() - (monday.getUTCDay() + 6) % 7 - 11 * 7)
    const weeklyHours = Array.from({ length: 12 }, (_, index) => {
        const week = new Date(monday)
        week.setUTCDate(week.getUTCDate() + index * 7)
        return { week: week.toISOString(), hours: 0 }
    })
    for (const workout of publicWorkouts) {
        const rawDate = String(workout.get("completed_at") || workout.get("started_at") || "").replace(" ", "T")
        const completed = new Date(rawDate.endsWith("Z") ? rawDate : rawDate + "Z")
        if (Number.isNaN(completed.getTime())) continue
        const index = Math.floor((completed.getTime() - monday.getTime()) / 604800000)
        if (index >= 0 && index < weeklyHours.length) weeklyHours[index].hours += Math.max(0, Number(workout.get("duration") || 0)) / 3600
    }
    const friends = dao.findRecordsByFilter(
        "training_friendships",
        "status = 'accepted' && (requester = {:user} || recipient = {:user})",
        "", 0, 0, { user: targetID }
    )
    const publicRoutines = dao.findRecordsByFilter(
        "workout_routines",
        "user = {:user} && visibility = 'public'",
        "-updated", 0, 0, { user: targetID }
    )

    return c.json(200, {
        profile: {
            id: target.id,
            username: String(target.get("username") || ""),
            nickname: String(target.get("name") || ""),
            bio: String(target.get("social_bio") || ""),
            website: String(target.get("social_website") || ""),
            avatar,
            avatar_url: avatar ? "/api/files/users/" + target.id + "/" + encodeURIComponent(avatar) + "?thumb=256x256" : "",
            state
        },
        workouts,
        workout_count: publicWorkouts.length,
        friend_count: friends.length,
        weekly_hours: weeklyHours,
        routine_count: publicRoutines.length,
        routines: publicRoutines.slice(0, 30).map((routine) => ({ id: routine.id, name: String(routine.get("name") || "") }))
    })
}, $apis.requireRecordAuth("users"))

routerAdd("GET", "/api/hyse/social/connections", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao()
    const friends = [], requests = []
    const relationships = dao.findRecordsByFilter("training_friendships", "requester = {:user} || recipient = {:user}", "-updated", 500, 0, { user: user.id })
    for (const relation of relationships) {
        const requester = String(relation.get("requester")), recipient = String(relation.get("recipient"))
        const otherID = requester === user.id ? recipient : requester
        let other
        try { other = dao.findRecordById("users", otherID) } catch (_) { continue }
        const avatar = String(other.get("avatar") || "")
        const value = { relationship_id: relation.id, user_id: otherID, username: String(other.get("username") || ""), nickname: String(other.get("name") || ""), avatar, avatar_url: avatar ? "/api/files/users/" + otherID + "/" + encodeURIComponent(avatar) + "?thumb=256x256" : "" }
        if (String(relation.get("status")) === "accepted") friends.push(value)
        else if (recipient === user.id) requests.push(value)
    }
    friends.sort((a, b) => a.username.localeCompare(b.username))
    return c.json(200, { friends, requests })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/social/request", (c) => {
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao()
    const recipientID = String((info.data || {}).user_id || "")
    if (!recipientID || recipientID === user.id) throw new BadRequestError("Invalid friend request.")
    try { dao.findRecordById("users", recipientID) } catch (_) { throw new NotFoundError("User not found.") }
    const pair = [String(user.id), recipientID].sort().join(":")
    try {
        const existing = dao.findFirstRecordByFilter("training_friendships", "pair_key = {:pair}", { pair })
        return c.json(200, { relationship_id: existing.id, status: String(existing.get("status")) })
    } catch (_) {}
    const record = new Record(dao.findCollectionByNameOrId("training_friendships"))
    record.set("requester", user.id); record.set("recipient", recipientID); record.set("pair_key", pair); record.set("status", "pending")
    dao.saveRecord(record)
    let preferences = null
    try { preferences = dao.findFirstRecordByFilter("notification_preferences", "user = {:user}", { user: recipientID }) } catch (_) {}
    if (!preferences || preferences.get("friend_activity")) {
        const notification = new Record(dao.findCollectionByNameOrId("user_notifications"))
        notification.set("recipient", recipientID); notification.set("actor", user.id); notification.set("type", "friend_request")
        notification.set("title", "👋 @" + String(user.get("username") || "Hyse")); notification.set("body", "Hyse Friends")
        notification.set("dedupe_key", "friend_request:" + record.id); notification.set("is_read", false); dao.saveRecord(notification)
        const gatewayURL = String($os.getenv("PUSH_GATEWAY_URL") || ""), secret = String($os.getenv("PUSH_GATEWAY_SECRET") || "")
        if (gatewayURL && secret) {
            const devices = dao.findRecordsByFilter("push_devices", "user = {:user}", "", 20, 0, { user: recipientID }).map((device) => ({ token: String(device.get("device_token")), environment: String(device.get("environment")) }))
            if (devices.length) try { $http.send({ url: gatewayURL.replace(/\/$/, "") + "/send", method: "POST", headers: { "Content-Type": "application/json", "X-Hyse-Push-Secret": secret }, body: JSON.stringify({ devices, title: "👋 @" + String(user.get("username") || "Hyse"), body: "Hyse Friends", type: "friend_request" }), timeout: 8 }) } catch (_) {}
        }
    }
    return c.json(201, { relationship_id: record.id, status: "pending" })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/social/accept", (c) => {
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao()
    const id = String((info.data || {}).relationship_id || "")
    let relation
    try { relation = dao.findRecordById("training_friendships", id) } catch (_) { throw new NotFoundError("Request not found.") }
    if (String(relation.get("recipient")) !== user.id || String(relation.get("status")) !== "pending") throw new ForbiddenError("This request cannot be accepted.")
    relation.set("status", "accepted"); dao.saveRecord(relation)
    const requesterID = String(relation.get("requester")); let preferences = null
    try { preferences = dao.findFirstRecordByFilter("notification_preferences", "user = {:user}", { user: requesterID }) } catch (_) {}
    if (!preferences || preferences.get("friend_activity")) {
        const notification = new Record(dao.findCollectionByNameOrId("user_notifications"))
        notification.set("recipient", requesterID); notification.set("actor", user.id); notification.set("type", "friend_accepted")
        notification.set("title", "🤝 @" + String(user.get("username") || "Hyse")); notification.set("body", "Hyse Friends")
        notification.set("dedupe_key", "friend_accepted:" + relation.id); notification.set("is_read", false); dao.saveRecord(notification)
        const gatewayURL = String($os.getenv("PUSH_GATEWAY_URL") || ""), secret = String($os.getenv("PUSH_GATEWAY_SECRET") || "")
        if (gatewayURL && secret) {
            const devices = dao.findRecordsByFilter("push_devices", "user = {:user}", "", 20, 0, { user: requesterID }).map((device) => ({ token: String(device.get("device_token")), environment: String(device.get("environment")) }))
            if (devices.length) try { $http.send({ url: gatewayURL.replace(/\/$/, "") + "/send", method: "POST", headers: { "Content-Type": "application/json", "X-Hyse-Push-Secret": secret }, body: JSON.stringify({ devices, title: "🤝 @" + String(user.get("username") || "Hyse"), body: "Hyse Friends", type: "friend_accepted" }), timeout: 8 }) } catch (_) {}
        }
    }
    return c.json(200, { status: "accepted" })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/social/remove", (c) => {
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao()
    const id = String((info.data || {}).relationship_id || "")
    let relation
    try { relation = dao.findRecordById("training_friendships", id) } catch (_) { return c.json(200, { removed: true }) }
    if (String(relation.get("requester")) !== user.id && String(relation.get("recipient")) !== user.id) throw new ForbiddenError("This connection does not belong to you.")
    dao.deleteRecord(relation)
    return c.json(200, { removed: true })
}, $apis.requireRecordAuth("users"))

routerAdd("GET", "/api/hyse/social/feed", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao()
    const items = []
    const owners = [{ id: String(user.id), record: user }]
    const seenOwners = {}
    seenOwners[String(user.id)] = true
    const relationships = dao.findRecordsByFilter("training_friendships", "requester = {:user} || recipient = {:user}", "-updated", 500, 0, { user: user.id })
    for (const relation of relationships) {
        if (String(relation.get("status")) !== "accepted") continue
        const requester = String(relation.get("requester")), recipient = String(relation.get("recipient"))
        const friendID = requester === user.id ? recipient : requester
        if (seenOwners[friendID]) continue
        let friend
        try { friend = dao.findRecordById("users", friendID) } catch (_) { continue }
        seenOwners[friendID] = true
        owners.push({ id: friendID, record: friend })
    }
    for (const owner of owners) {
        const workouts = dao.findRecordsByFilter("workouts", "user = {:user} && status = 'completed' && visibility = 'public'", "-completed_at", 12, 0, { user: owner.id })
        const username = String(owner.record.get("username") || "")
        const nickname = String(owner.record.get("name") || "")
        const avatar = String(owner.record.get("avatar") || "")
        for (const workout of workouts) {
            const likes = dao.findRecordsByFilter("training_workout_likes", "workout = {:workout}", "", 1000, 0, { workout: workout.id })
            const comments = dao.findRecordsByFilter("training_workout_comments", "workout = {:workout}", "", 1000, 0, { workout: workout.id })
            items.push({
                id: workout.id,
                client_id: String(workout.get("client_id") || ""),
                user_id: owner.id,
                username,
                nickname,
                avatar,
                avatar_url: avatar ? "/api/files/users/" + owner.id + "/" + encodeURIComponent(avatar) + "?thumb=256x256" : "",
                name: String(workout.get("name") || "Workout"),
                notes: String(workout.get("notes") || ""),
                media_url: workout.get("media") ? "/api/files/workouts/" + workout.id + "/" + encodeURIComponent(String(workout.get("media"))) : "",
                completed_at: String(workout.get("completed_at") || workout.get("started_at") || ""),
                duration: Number(workout.get("duration") || 0),
                total_volume: Number(workout.get("total_volume") || 0),
                like_count: likes.length,
                comment_count: comments.length,
                liked_by_me: likes.some((like) => String(like.get("user")) === user.id)
            })
        }
    }
    items.sort((a, b) => String(b.completed_at).localeCompare(String(a.completed_at)))
    return c.json(200, { items: items.slice(0, 50) })
}, $apis.requireRecordAuth("users"))

routerAdd("GET", "/api/hyse/social/workouts/:id", (c) => {
    const user = $apis.requestInfo(c).authRecord
    const dao = $app.dao(), workoutID = String(c.pathParam("id") || "")
    let workout
    try {
        workout = dao.findRecordById("workouts", workoutID)
    } catch (_) {
        try {
            workout = dao.findFirstRecordByFilter("workouts", "client_id = {:clientID}", { clientID: workoutID.toLowerCase() })
        } catch (_) {
            throw new NotFoundError("Workout not found.")
        }
    }
    const ownerID = String(workout.get("user"))
    if ((!user || ownerID !== user.id) && String(workout.get("visibility") || "private") !== "public") {
        throw new NotFoundError("Workout not found.")
    }
    let owner
    try { owner = dao.findRecordById("users", ownerID) } catch (_) { throw new NotFoundError("User not found.") }
    const avatar = String(owner.get("avatar") || "")
    const likes = dao.findRecordsByFilter("training_workout_likes", "workout = {:workout}", "-created", 1000, 0, { workout: workout.id })
    const likedBy = []
    for (const like of likes) {
        const likerID = String(like.get("user"))
        let liker
        try { liker = dao.findRecordById("users", likerID) } catch (_) { continue }
        const likerAvatar = String(liker.get("avatar") || "")
        likedBy.push({
            id: likerID,
            username: String(liker.get("username") || ""),
            nickname: String(liker.get("name") || ""),
            avatar: likerAvatar,
            avatar_url: likerAvatar ? "/api/files/users/" + likerID + "/" + encodeURIComponent(likerAvatar) + "?thumb=256x256" : ""
        })
    }
    const commentRecords = dao.findRecordsByFilter("training_workout_comments", "workout = {:workout}", "created", 100, 0, { workout: workout.id })
    const comments = []
    for (const comment of commentRecords) {
        const authorID = String(comment.get("user"))
        let author
        try { author = dao.findRecordById("users", authorID) } catch (_) { continue }
        const authorAvatar = String(author.get("avatar") || "")
        comments.push({ id: comment.id, user_id: authorID, username: String(author.get("username") || ""), nickname: String(author.get("name") || ""), avatar: authorAvatar, avatar_url: authorAvatar ? "/api/files/users/" + authorID + "/" + encodeURIComponent(authorAvatar) + "?thumb=256x256" : "", body: String(comment.get("body") || ""), reply_to: String(comment.get("reply_to") || ""), created: String(comment.created || "") })
    }
    return c.json(200, {
        id: workout.id, client_id: String(workout.get("client_id") || ""), user_id: ownerID, username: String(owner.get("username") || ""), nickname: String(owner.get("name") || ""), avatar,
        avatar_url: avatar ? "/api/files/users/" + ownerID + "/" + encodeURIComponent(avatar) + "?thumb=256x256" : "",
        name: String(workout.get("name") || "Workout"), completed_at: String(workout.get("completed_at") || workout.get("started_at") || ""),
        duration: Number(workout.get("duration") || 0), total_volume: Number(workout.get("total_volume") || 0), notes: String(workout.get("notes") || ""),
        media_url: workout.get("media") ? "/api/files/workouts/" + workout.id + "/" + encodeURIComponent(String(workout.get("media"))) : "",
        like_count: likes.length, comment_count: comments.length, liked_by_me: !!user && likes.some((like) => String(like.get("user")) === user.id),
        snapshot: workout.get("snapshot_json") || null, comments, likes: likedBy
    })
})

routerAdd("POST", "/api/hyse/social/workouts/:id/like", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), workoutID = String(c.pathParam("id") || "")
    let workout
    try { workout = dao.findRecordById("workouts", workoutID) } catch (_) { throw new NotFoundError("Workout not found.") }
    const ownerID = String(workout.get("user"))
    if (ownerID !== user.id) {
        if (String(workout.get("visibility") || "private") !== "public") throw new ForbiddenError("This workout is private.")
    }
    let existing = null
    try { existing = dao.findFirstRecordByFilter("training_workout_likes", "user = {:user} && workout = {:workout}", { user: user.id, workout: workoutID }) } catch (_) {}
    let liked = true
    if (existing) { dao.deleteRecord(existing); liked = false }
    else {
        const like = new Record(dao.findCollectionByNameOrId("training_workout_likes"))
        like.set("user", user.id); like.set("workout", workoutID); dao.saveRecord(like)
        if (ownerID !== user.id) {
            let preferences = null
            try { preferences = dao.findFirstRecordByFilter("notification_preferences", "user = {:user}", { user: ownerID }) } catch (_) {}
            if (!preferences || preferences.get("workout_likes")) {
                const dedupe = "workout_like:" + like.id
                const notification = new Record(dao.findCollectionByNameOrId("user_notifications"))
                notification.set("recipient", ownerID); notification.set("actor", user.id); notification.set("type", "workout_like")
                notification.set("title", "❤️ @" + String(user.get("username") || "Hyse")); notification.set("body", String(workout.get("name") || "Workout"))
                notification.set("workout", workoutID); notification.set("dedupe_key", dedupe); notification.set("is_read", false); dao.saveRecord(notification)
                const gatewayURL = String($os.getenv("PUSH_GATEWAY_URL") || ""), secret = String($os.getenv("PUSH_GATEWAY_SECRET") || "")
                if (gatewayURL && secret) {
                    const devices = dao.findRecordsByFilter("push_devices", "user = {:user}", "", 20, 0, { user: ownerID }).map((device) => ({ token: String(device.get("device_token")), environment: String(device.get("environment")) }))
                    if (devices.length) try { $http.send({ url: gatewayURL.replace(/\/$/, "") + "/send", method: "POST", headers: { "Content-Type": "application/json", "X-Hyse-Push-Secret": secret }, body: JSON.stringify({ devices, title: "❤️ @" + String(user.get("username") || "Hyse"), body: String(workout.get("name") || "Workout"), type: "workout_like", workout_id: workoutID }), timeout: 8 }) } catch (_) {}
                }
            }
        }
    }
    const count = dao.findRecordsByFilter("training_workout_likes", "workout = {:workout}", "", 1000, 0, { workout: workoutID }).length
    return c.json(200, { liked, like_count: count })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/social/workouts/:id/comments", (c) => {
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), workoutID = String(c.pathParam("id") || ""), body = String((info.data || {}).body || "").trim()
    const replyToID = String((info.data || {}).reply_to || "")
    if (!body || body.length > 1000) throw new BadRequestError("Comment must contain 1–1000 characters.")
    let workout
    try { workout = dao.findRecordById("workouts", workoutID) } catch (_) { throw new NotFoundError("Workout not found.") }
    const ownerID = String(workout.get("user"))
    if (ownerID !== user.id) {
        if (String(workout.get("visibility") || "private") !== "public") throw new ForbiddenError("This workout is private.")
    }
    let replyAuthorID = ""
    if (replyToID) {
        let replied
        try { replied = dao.findRecordById("training_workout_comments", replyToID) } catch (_) { throw new BadRequestError("The comment being replied to no longer exists.") }
        if (String(replied.get("workout")) !== workoutID) throw new BadRequestError("Replies must stay inside the same workout.")
        replyAuthorID = String(replied.get("user") || "")
    }
    const comment = new Record(dao.findCollectionByNameOrId("training_workout_comments"))
    comment.set("user", user.id); comment.set("workout", workoutID); comment.set("body", body)
    if (replyToID) comment.set("reply_to", replyToID)
    dao.saveRecord(comment)
    const recipients = [ownerID, replyAuthorID].filter((id, index, all) => id && id !== user.id && all.indexOf(id) === index)
    for (const recipientID of recipients) {
        let preferences = null
        try { preferences = dao.findFirstRecordByFilter("notification_preferences", "user = {:user}", { user: recipientID }) } catch (_) {}
        if (!preferences || preferences.get("workout_comments")) {
            const notification = new Record(dao.findCollectionByNameOrId("user_notifications"))
            notification.set("recipient", recipientID); notification.set("actor", user.id); notification.set("type", "workout_comment")
            notification.set("title", "💬 @" + String(user.get("username") || "Hyse")); notification.set("body", body.slice(0, 500))
            notification.set("workout", workoutID); notification.set("dedupe_key", "workout_comment:" + comment.id); notification.set("is_read", false); dao.saveRecord(notification)
            const gatewayURL = String($os.getenv("PUSH_GATEWAY_URL") || ""), secret = String($os.getenv("PUSH_GATEWAY_SECRET") || "")
            if (gatewayURL && secret) {
                const devices = dao.findRecordsByFilter("push_devices", "user = {:user}", "", 20, 0, { user: recipientID }).map((device) => ({ token: String(device.get("device_token")), environment: String(device.get("environment")) }))
                if (devices.length) try { $http.send({ url: gatewayURL.replace(/\/$/, "") + "/send", method: "POST", headers: { "Content-Type": "application/json", "X-Hyse-Push-Secret": secret }, body: JSON.stringify({ devices, title: "💬 @" + String(user.get("username") || "Hyse"), body: body.slice(0, 180), type: "workout_comment", workout_id: workoutID }), timeout: 8 }) } catch (_) {}
            }
        }
    }
    const avatar = String(user.get("avatar") || "")
    const value = { id: comment.id, user_id: user.id, username: String(user.get("username") || ""), nickname: String(user.get("name") || ""), avatar, avatar_url: avatar ? "/api/files/users/" + user.id + "/" + encodeURIComponent(avatar) + "?thumb=256x256" : "", body, reply_to: replyToID, created: String(comment.created || "") }
    const count = dao.findRecordsByFilter("training_workout_comments", "workout = {:workout}", "", 1000, 0, { workout: workoutID }).length
    return c.json(201, { comment: value, comment_count: count })
}, $apis.requireRecordAuth("users"))
