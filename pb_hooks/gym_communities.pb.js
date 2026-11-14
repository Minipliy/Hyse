/// <reference path="../pb_data/types.d.ts" />

routerAdd("POST", "/api/hyse/push-devices", (c) => {
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const data = info.data || {}, token = String(data.device_token || "").toLowerCase()
    const enabled = String(data.enabled || "true") === "true"
    const environment = String(data.environment || "production")
    const dao = $app.dao()
    if (!enabled) {
        const records = token
            ? dao.findRecordsByFilter("push_devices", "user = {:user} && device_token = {:token}", "", 20, 0, { user: user.id, token })
            : dao.findRecordsByFilter("push_devices", "user = {:user}", "", 100, 0, { user: user.id })
        for (const record of records) dao.deleteRecord(record)
        return c.json(200, { enabled: false })
    }
    if (!/^[a-f0-9]{64,200}$/.test(token)) throw new BadRequestError("Invalid device token.")
    if (environment !== "sandbox" && environment !== "production") throw new BadRequestError("Invalid push environment.")
    let record = null
    try { record = dao.findFirstRecordByFilter("push_devices", "device_token = {:token}", { token }) } catch (_) {}
    if (!record) record = new Record(dao.findCollectionByNameOrId("push_devices"))
    record.set("user", user.id); record.set("device_token", token); record.set("environment", environment)
    dao.saveRecord(record)
    return c.json(200, { enabled: true })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/gym-communities/:id/news-notifications", (c) => {
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), communityID = String(c.pathParam("id") || "")
    let membership = null
    try { membership = dao.findFirstRecordByFilter("gym_community_members", "community = {:community} && user = {:user}", { community: communityID, user: user.id }) } catch (_) {}
    if (!membership) throw new ForbiddenError("Join this community before enabling notifications.")
    const enabled = String((info.data || {}).enabled || "false") === "true"
    membership.set("news_notifications_enabled", enabled); dao.saveRecord(membership)
    return c.json(200, { enabled })
}, $apis.requireRecordAuth("users"))

routerAdd("GET", "/api/hyse/gym-communities", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), query = String(c.queryParam("q") || "").trim().slice(0, 80)
    const filter = query ? "name ~ {:query} || gym_name ~ {:query} || city ~ {:query}" : "id != ''"
    const records = dao.findRecordsByFilter("gym_communities", filter, "-updated", 100, 0, query ? { query } : {})
    const ownMemberships = dao.findRecordsByFilter("gym_community_members", "user = {:user}", "", 500, 0, { user: user.id })
    const roleByCommunity = {}
    const notificationsByCommunity = {}
    for (const member of ownMemberships) {
        roleByCommunity[String(member.get("community"))] = String(member.get("role"))
        notificationsByCommunity[String(member.get("community"))] = !!member.get("news_notifications_enabled")
    }
    const items = []
    for (const community of records) {
        const ownerID = String(community.get("owner")), members = dao.findRecordsByFilter("gym_community_members", "community = {:community}", "", 1000, 0, { community: community.id })
        let owner = null
        try { owner = dao.findRecordById("users", ownerID) } catch (_) {}
        items.push({
            id: community.id, name: String(community.get("name") || ""), gym_name: String(community.get("gym_name") || ""),
            city: String(community.get("city") || ""), description: String(community.get("description") || ""),
            image: String(community.get("image") || ""),
            image_url: community.get("image") ? "/api/files/gym_communities/" + community.id + "/" + encodeURIComponent(String(community.get("image"))) + "?thumb=512x512" : "",
            owner_id: ownerID, owner_username: owner ? String(owner.get("username") || "") : "",
            member_count: members.length, joined: !!roleByCommunity[community.id], role: roleByCommunity[community.id] || "",
            news_notifications_enabled: !!notificationsByCommunity[community.id]
        })
    }
    items.sort((a, b) => Number(b.joined) - Number(a.joined) || b.member_count - a.member_count || a.name.localeCompare(b.name))
    return c.json(200, { items })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/gym-communities", (c) => {
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const data = info.data || {}, name = String(data.name || "").trim(), gymName = String(data.gym_name || "").trim()
    const city = String(data.city || "").trim(), description = String(data.description || "").trim()
    if (name.length < 3 || name.length > 100) throw new BadRequestError("Community name must contain 3–100 characters.")
    if (gymName.length < 2 || gymName.length > 120) throw new BadRequestError("Gym name must contain 2–120 characters.")
    if (city.length > 100 || description.length > 1200) throw new BadRequestError("Community details are too long.")
    const dao = $app.dao(), base = name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 90) || "gym"
    let slug = base, suffix = 1
    while (true) {
        try { dao.findFirstRecordByFilter("gym_communities", "slug = {:slug}", { slug }); slug = base + "-" + (++suffix) }
        catch (_) { break }
    }
    const community = new Record(dao.findCollectionByNameOrId("gym_communities"))
    community.set("owner", user.id); community.set("name", name); community.set("slug", slug)
    community.set("gym_name", gymName); community.set("city", city); community.set("description", description)
    const imageHeader = c.formFile("image")
    if (imageHeader) community.set("image", $filesystem.fileFromMultipart(imageHeader))
    dao.saveRecord(community)
    const membership = new Record(dao.findCollectionByNameOrId("gym_community_members"))
    membership.set("community", community.id); membership.set("user", user.id)
    membership.set("membership_key", community.id + ":" + user.id); membership.set("role", "owner")
    dao.saveRecord(membership)
    return c.json(201, {
        id: community.id, name, gym_name: gymName, city, description, owner_id: user.id,
        image: String(community.get("image") || ""),
        image_url: community.get("image") ? "/api/files/gym_communities/" + community.id + "/" + encodeURIComponent(String(community.get("image"))) + "?thumb=512x512" : "",
        owner_username: String(user.get("username") || ""), member_count: 1, joined: true, role: "owner"
    })
}, $apis.requireRecordAuth("users"))

routerAdd("GET", "/api/hyse/gym-communities/:id", (c) => {
    function postImages(post) {
        const images = post.getStringSlice("images")
        return { images, image_urls: images.map((name) => "/api/files/gym_community_posts/" + post.id + "/" + encodeURIComponent(name)) }
    }
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), communityID = String(c.pathParam("id") || "")
    let community
    try { community = dao.findRecordById("gym_communities", communityID) } catch (_) { throw new NotFoundError("Community not found.") }
    let membership = null
    try { membership = dao.findFirstRecordByFilter("gym_community_members", "community = {:community} && user = {:user}", { community: communityID, user: user.id }) } catch (_) {}
    const members = dao.findRecordsByFilter("gym_community_members", "community = {:community}", "created", 1000, 0, { community: communityID })
    const ownerID = String(community.get("owner")); let owner = null
    try { owner = dao.findRecordById("users", ownerID) } catch (_) {}
    const memberItems = []
    if (membership) {
        for (const member of members) {
            const memberUserID = String(member.get("user")); let memberUser = null
            try { memberUser = dao.findRecordById("users", memberUserID) } catch (_) {}
            if (!memberUser) continue
            const memberAvatar = String(memberUser.get("avatar") || "")
            memberItems.push({
                user_id: memberUserID,
                username: String(memberUser.get("username") || ""),
                nickname: String(memberUser.get("name") || ""),
                avatar: memberAvatar,
                avatar_url: memberAvatar ? "/api/files/users/" + memberUserID + "/" + encodeURIComponent(memberAvatar) + "?thumb=128x128" : "",
                role: String(member.get("role") || "member"),
                joined_at: String(member.created || "")
            })
        }
        memberItems.sort((a, b) => {
            const rankA = a.role === "owner" ? 0 : (a.role === "admin" ? 1 : 2)
            const rankB = b.role === "owner" ? 0 : (b.role === "admin" ? 1 : 2)
            return rankA - rankB || a.username.localeCompare(b.username)
        })
    }
    const posts = []
    if (membership) {
        const records = dao.findRecordsByFilter("gym_community_posts", "community = {:community}", "created", 250, 0, { community: communityID })
        for (const post of records) {
            const authorID = String(post.get("author")); let author = null
            try { author = dao.findRecordById("users", authorID) } catch (_) {}
            const avatar = author ? String(author.get("avatar") || "") : ""
            let replyPreview = null
            const replyID = String(post.get("reply_to") || "")
            if (replyID) {
                let repliedPost = null
                try { repliedPost = dao.findRecordById("gym_community_posts", replyID) } catch (_) {}
                if (repliedPost && String(repliedPost.get("community")) === communityID) {
                    let replyAuthor = null
                    try { replyAuthor = dao.findRecordById("users", String(repliedPost.get("author"))) } catch (_) {}
                    replyPreview = {
                        id: repliedPost.id,
                        author_id: String(repliedPost.get("author") || ""),
                        author_username: replyAuthor ? String(replyAuthor.get("username") || "") : "",
                        author_nickname: replyAuthor ? String(replyAuthor.get("name") || "") : "",
                        body: String(repliedPost.get("body") || "").slice(0, 500)
                    }
                }
            }
            const reactionCounts = {}, ownReactions = {}
            const reactions = dao.findRecordsByFilter("gym_community_post_reactions", "post = {:post}", "created", 1000, 0, { post: post.id })
            for (const reaction of reactions) {
                const emoji = String(reaction.get("emoji") || "")
                reactionCounts[emoji] = Number(reactionCounts[emoji] || 0) + 1
                if (String(reaction.get("user")) === user.id) ownReactions[emoji] = true
            }
            const reactionItems = Object.keys(reactionCounts).map((emoji) => ({ emoji, count: reactionCounts[emoji], reacted: !!ownReactions[emoji] }))
            posts.push({
                id: post.id, client_id: String(post.get("client_id") || ""), community_id: communityID, author_id: authorID,
                author_username: author ? String(author.get("username") || "") : "",
                author_nickname: author ? String(author.get("name") || "") : "",
                avatar, avatar_url: avatar ? "/api/files/users/" + authorID + "/" + encodeURIComponent(avatar) + "?thumb=128x128" : "",
                channel: String(post.get("channel")), body: String(post.get("body") || ""), pinned: !!post.get("pinned"),
                images: postImages(post).images, image_urls: postImages(post).image_urls,
                reply: replyPreview, reactions: reactionItems,
                created: String(post.created || ""), updated: String(post.updated || "")
            })
        }
    }
    return c.json(200, { community: {
        id: community.id, name: String(community.get("name") || ""), gym_name: String(community.get("gym_name") || ""),
        city: String(community.get("city") || ""), description: String(community.get("description") || ""),
        image: String(community.get("image") || ""),
        image_url: community.get("image") ? "/api/files/gym_communities/" + community.id + "/" + encodeURIComponent(String(community.get("image"))) + "?thumb=512x512" : "",
        owner_id: ownerID, owner_username: owner ? String(owner.get("username") || "") : "",
        member_count: members.length, joined: !!membership, role: membership ? String(membership.get("role")) : "",
        news_notifications_enabled: membership ? !!membership.get("news_notifications_enabled") : false
    }, posts, members: memberItems, supportsMessageOutbox: true })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/gym-communities/:id/join", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), communityID = String(c.pathParam("id") || "")
    try { dao.findRecordById("gym_communities", communityID) } catch (_) { throw new NotFoundError("Community not found.") }
    let existing = null
    try { existing = dao.findFirstRecordByFilter("gym_community_members", "membership_key = {:key}", { key: communityID + ":" + user.id }) } catch (_) {}
    if (!existing) {
        existing = new Record(dao.findCollectionByNameOrId("gym_community_members"))
        existing.set("community", communityID); existing.set("user", user.id)
        existing.set("membership_key", communityID + ":" + user.id); existing.set("role", "member")
        existing.set("news_notifications_enabled", false)
        dao.saveRecord(existing)
    }
    return c.json(200, { joined: true, role: String(existing.get("role")) })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/gym-communities/:id/leave", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), communityID = String(c.pathParam("id") || "")
    let membership = null
    try { membership = dao.findFirstRecordByFilter("gym_community_members", "community = {:community} && user = {:user}", { community: communityID, user: user.id }) } catch (_) {}
    if (!membership) return c.json(200, { joined: false })
    if (String(membership.get("role")) === "owner") throw new BadRequestError("The community owner cannot leave the community.")
    dao.deleteRecord(membership)
    return c.json(200, { joined: false })
}, $apis.requireRecordAuth("users"))

routerAdd("PATCH", "/api/hyse/gym-communities/:id/members/:userId/role", (c) => {
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), communityID = String(c.pathParam("id") || "")
    const memberUserID = String(c.pathParam("userId") || ""), role = String((info.data || {}).role || "")
    if (role !== "admin" && role !== "member") throw new BadRequestError("Invalid community role.")
    let community
    try { community = dao.findRecordById("gym_communities", communityID) } catch (_) { throw new NotFoundError("Community not found.") }
    if (String(community.get("owner")) !== user.id) throw new ForbiddenError("Only the gym owner can manage member roles.")
    if (memberUserID === user.id) throw new BadRequestError("The gym owner role cannot be changed.")
    let member = null
    try { member = dao.findFirstRecordByFilter("gym_community_members", "community = {:community} && user = {:user}", { community: communityID, user: memberUserID }) } catch (_) {}
    if (!member) throw new NotFoundError("Community member not found.")
    member.set("role", role); dao.saveRecord(member)
    let memberUser = null
    try { memberUser = dao.findRecordById("users", memberUserID) } catch (_) {}
    const avatar = memberUser ? String(memberUser.get("avatar") || "") : ""
    return c.json(200, { member: {
        user_id: memberUserID,
        username: memberUser ? String(memberUser.get("username") || "") : "",
        nickname: memberUser ? String(memberUser.get("name") || "") : "",
        avatar,
        avatar_url: avatar ? "/api/files/users/" + memberUserID + "/" + encodeURIComponent(avatar) + "?thumb=128x128" : "",
        role,
        joined_at: String(member.created || "")
    } })
}, $apis.requireRecordAuth("users"))

routerAdd("DELETE", "/api/hyse/gym-communities/:id", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), communityID = String(c.pathParam("id") || "")
    let community
    try { community = dao.findRecordById("gym_communities", communityID) } catch (_) { throw new NotFoundError("Community not found.") }
    if (String(community.get("owner")) !== user.id) throw new ForbiddenError("Only the community owner can delete it.")
    dao.deleteRecord(community)
    return c.json(200, { deleted: true, id: communityID })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/gym-communities/:id/posts", (c) => {
    function postImages(post) {
        const images = post.getStringSlice("images")
        return { images, image_urls: images.map((name) => "/api/files/gym_community_posts/" + post.id + "/" + encodeURIComponent(name)) }
    }
    function sendNewsPush(dao, community, post, author) {
        const gatewayURL = String($os.getenv("PUSH_GATEWAY_URL") || "")
        const secret = String($os.getenv("PUSH_GATEWAY_SECRET") || "")
        const memberships = dao.findRecordsByFilter(
            "gym_community_members",
            "community = {:community} && news_notifications_enabled = true && user != {:author}",
            "", 2000, 0, { community: community.id, author: author.id }
        )
        const devices = []
        for (const membership of memberships) {
            const recipientID = String(membership.get("user"))
            let preferences = null
            try { preferences = dao.findFirstRecordByFilter("notification_preferences", "user = {:user}", { user: recipientID }) } catch (_) {}
            if (preferences && !preferences.get("community_news")) continue
            const dedupe = "community_news:" + post.id
            let existingNotification = null
            try { existingNotification = dao.findFirstRecordByFilter("user_notifications", "recipient = {:recipient} && dedupe_key = {:dedupe}", { recipient: recipientID, dedupe }) } catch (_) {}
            if (!existingNotification) {
                const notification = new Record(dao.findCollectionByNameOrId("user_notifications"))
                notification.set("recipient", recipientID); notification.set("actor", author.id); notification.set("type", "community_news")
                notification.set("title", "📣 " + String(community.get("name") || "Gym Community")); notification.set("body", String(post.get("body") || "").slice(0, 500))
                notification.set("community", community.id); notification.set("dedupe_key", dedupe); notification.set("is_read", false)
                dao.saveRecord(notification)
            }
            const records = dao.findRecordsByFilter("push_devices", "user = {:user}", "", 20, 0, { user: recipientID })
            for (const device of records) devices.push({ token: String(device.get("device_token")), environment: String(device.get("environment")) })
        }
        if (!gatewayURL || !secret || !devices.length) return
        try {
            $http.send({
                url: gatewayURL.replace(/\/$/, "") + "/send", method: "POST",
                headers: { "Content-Type": "application/json", "X-Hyse-Push-Secret": secret },
                body: JSON.stringify({
                    devices, title: String(community.get("name") || "Hyse"), body: String(post.get("body") || "").slice(0, 180),
                    type: "community_news", community_id: community.id, post_id: post.id
                }),
                timeout: 8
            })
        } catch (_) {}
    }

    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), communityID = String(c.pathParam("id") || ""), data = info.data || {}
    const body = String(data.body || "").trim(), channel = String(data.channel || "members")
    const replyToID = String(data.reply_to || "")
    const clientID = String(data.client_id || "").toLowerCase()
    if (clientID && !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(clientID)) {
        throw new BadRequestError("Invalid message ID.")
    }
    if (!body || body.length > 2000) throw new BadRequestError("Post must contain 1–2000 characters.")
    if (channel !== "news" && channel !== "members") throw new BadRequestError("Invalid channel.")
    let membership = null
    try { membership = dao.findFirstRecordByFilter("gym_community_members", "community = {:community} && user = {:user}", { community: communityID, user: user.id }) } catch (_) {}
    if (!membership) throw new ForbiddenError("Join this community before posting.")
    const role = String(membership.get("role"))
    if (channel === "news" && role !== "owner" && role !== "admin") throw new ForbiddenError("Only gym administrators can publish news.")
    let imageHeaders = []
    if (channel === "news" && String(c.request().header.get("Content-Type") || "").includes("multipart/form-data")) {
        imageHeaders = c.multipartForm().file["images"] || []
    }
    if (imageHeaders.length > 4) throw new BadRequestError("A news post can contain up to four images.")
    function findExisting() {
        if (!clientID) return null
        try {
            return dao.findFirstRecordByFilter("gym_community_posts", "author = {:author} && client_id = {:client}", { author: user.id, client: clientID })
        } catch (_) { return null }
    }
    function acknowledgeExisting(existing) {
        if (String(existing.get("community")) !== communityID || String(existing.get("channel")) !== channel) {
            throw new BadRequestError("Message ID already used.")
        }
        const avatar = String(user.get("avatar") || "")
        let replyPreview = null
        try {
            const replied = dao.findRecordById("gym_community_posts", String(existing.get("reply_to") || ""))
            const author = dao.findRecordById("users", String(replied.get("author")))
            replyPreview = { id: replied.id, author_id: String(replied.get("author") || ""), author_username: String(author.get("username") || ""), author_nickname: String(author.get("name") || ""), body: String(replied.get("body") || "").slice(0, 500) }
        } catch (_) {}
        return c.json(200, { post: {
            id: existing.id, client_id: clientID, community_id: communityID, author_id: user.id,
            author_username: String(user.get("username") || ""), author_nickname: String(user.get("name") || ""), avatar,
            avatar_url: avatar ? "/api/files/users/" + user.id + "/" + encodeURIComponent(avatar) + "?thumb=128x128" : "",
            channel, body: String(existing.get("body") || ""), pinned: !!existing.get("pinned"),
            images: postImages(existing).images, image_urls: postImages(existing).image_urls,
            reply: replyPreview, reactions: [], created: String(existing.created || ""), updated: String(existing.updated || "")
        } })
    }
    const existing = findExisting()
    if (existing) return acknowledgeExisting(existing)
    let reply = null
    if (replyToID) {
        try { reply = dao.findRecordById("gym_community_posts", replyToID) } catch (_) { throw new BadRequestError("The message being replied to no longer exists.") }
        if (String(reply.get("community")) !== communityID) throw new BadRequestError("Replies must stay inside the same community.")
    }
    const post = new Record(dao.findCollectionByNameOrId("gym_community_posts"))
    post.set("community", communityID); post.set("author", user.id); post.set("channel", channel); post.set("body", body); post.set("pinned", false)
    if (clientID) post.set("client_id", clientID)
    if (reply) post.set("reply_to", reply.id)
    try {
        if (imageHeaders.length) {
            const form = new RecordUpsertForm($app, post)
            const formData = { community: communityID, author: user.id, channel, body, pinned: false }
            if (clientID) formData.client_id = clientID
            if (reply) formData.reply_to = reply.id
            form.loadData(formData)
            for (const header of imageHeaders) form.addFiles("images", $filesystem.fileFromMultipart(header))
            form.submit()
        } else {
            dao.saveRecord(post)
        }
    } catch (error) {
        // A parallel retry may have won the unique author/client-ID insert.
        const saved = findExisting()
        if (saved) return acknowledgeExisting(saved)
        throw error
    }
    const savedPost = dao.findRecordById("gym_community_posts", post.id)
    if (channel === "news") {
        let community = null
        try { community = dao.findRecordById("gym_communities", communityID) } catch (_) {}
        if (community) sendNewsPush(dao, community, post, user)
    }
    const avatar = String(user.get("avatar") || "")
    let replyPreview = null
    if (reply) {
        let replyAuthor = null
        try { replyAuthor = dao.findRecordById("users", String(reply.get("author"))) } catch (_) {}
        replyPreview = {
            id: reply.id,
            author_id: String(reply.get("author") || ""),
            author_username: replyAuthor ? String(replyAuthor.get("username") || "") : "",
            author_nickname: replyAuthor ? String(replyAuthor.get("name") || "") : "",
            body: String(reply.get("body") || "").slice(0, 500)
        }
    }
    return c.json(201, { post: {
        id: post.id, client_id: clientID, community_id: communityID, author_id: user.id, author_username: String(user.get("username") || ""), author_nickname: String(user.get("name") || ""),
        avatar, avatar_url: avatar ? "/api/files/users/" + user.id + "/" + encodeURIComponent(avatar) + "?thumb=128x128" : "",
        channel, body, pinned: false, reply: replyPreview,
        images: postImages(savedPost).images, image_urls: postImages(savedPost).image_urls,
        reactions: [], created: String(post.created || ""), updated: String(post.updated || "")
    } })
}, $apis.requireRecordAuth("users"))

routerAdd("PATCH", "/api/hyse/gym-community-posts/:id", (c) => {
    function postImages(post) {
        const images = post.getStringSlice("images")
        return { images, image_urls: images.map((name) => "/api/files/gym_community_posts/" + post.id + "/" + encodeURIComponent(name)) }
    }
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), postID = String(c.pathParam("id") || "")
    const body = String((info.data || {}).body || "").trim()
    if (!body || body.length > 2000) throw new BadRequestError("Post must contain 1–2000 characters.")
    let post
    try { post = dao.findRecordById("gym_community_posts", postID) } catch (_) { throw new NotFoundError("Post not found.") }
    const postCommunityID = String(post.get("community")); let membership = null
    try { membership = dao.findFirstRecordByFilter("gym_community_members", "community = {:community} && user = {:user}", { community: postCommunityID, user: user.id }) } catch (_) {}
    if (!membership) throw new ForbiddenError("Join this community before editing.")
    if (String(post.get("author")) !== user.id) throw new ForbiddenError("Only the author can edit this post.")
    let imageHeaders = []
    let keepImages = null
    if (String(c.request().header.get("Content-Type") || "").includes("multipart/form-data")) {
        if (String(post.get("channel")) !== "news") throw new BadRequestError("Images are available only for news posts.")
        const multipart = c.multipartForm()
        imageHeaders = multipart.file["images"] || []
        try { keepImages = JSON.parse(String((info.data || {}).keep_images || "[]")) }
        catch (_) { throw new BadRequestError("Invalid image selection.") }
        const existing = postImages(post).images
        if (!Array.isArray(keepImages) ||
            keepImages.some((name) => !existing.includes(name)) ||
            keepImages.filter((name, index) => keepImages.indexOf(name) === index).length !== keepImages.length ||
            keepImages.length + imageHeaders.length > 4) {
            throw new BadRequestError("Invalid image selection.")
        }
        const removed = existing.filter((name) => !keepImages.includes(name))
        const form = new RecordUpsertForm($app, post)
        form.loadData({ body })
        if (removed.length) form.removeFiles("images", ...removed)
        for (const header of imageHeaders) form.addFiles("images", $filesystem.fileFromMultipart(header))
        form.submit()
        post = dao.findRecordById("gym_community_posts", post.id)
    } else {
        post.set("body", body); dao.saveRecord(post)
    }

    const communityID = postCommunityID, authorID = String(post.get("author"))
    let author = null
    try { author = dao.findRecordById("users", authorID) } catch (_) {}
    const avatar = author ? String(author.get("avatar") || "") : ""
    const reactionCounts = {}, ownReactions = {}
    const reactions = dao.findRecordsByFilter("gym_community_post_reactions", "post = {:post}", "created", 1000, 0, { post: postID })
    for (const reaction of reactions) {
        const emoji = String(reaction.get("emoji") || "")
        reactionCounts[emoji] = Number(reactionCounts[emoji] || 0) + 1
        if (String(reaction.get("user")) === user.id) ownReactions[emoji] = true
    }
    const reactionItems = Object.keys(reactionCounts).map((emoji) => ({ emoji, count: reactionCounts[emoji], reacted: !!ownReactions[emoji] }))
    let replyPreview = null
    const replyID = String(post.get("reply_to") || "")
    if (replyID) {
        let repliedPost = null
        try { repliedPost = dao.findRecordById("gym_community_posts", replyID) } catch (_) {}
        if (repliedPost && String(repliedPost.get("community")) === communityID) {
            let replyAuthor = null
            try { replyAuthor = dao.findRecordById("users", String(repliedPost.get("author"))) } catch (_) {}
            replyPreview = {
                id: repliedPost.id,
                author_id: String(repliedPost.get("author") || ""),
                author_username: replyAuthor ? String(replyAuthor.get("username") || "") : "",
                author_nickname: replyAuthor ? String(replyAuthor.get("name") || "") : "",
                body: String(repliedPost.get("body") || "").slice(0, 500)
            }
        }
    }
    return c.json(200, { post: {
        id: post.id, community_id: communityID, author_id: authorID,
        author_username: author ? String(author.get("username") || "") : "",
        author_nickname: author ? String(author.get("name") || "") : "",
        avatar, avatar_url: avatar ? "/api/files/users/" + authorID + "/" + encodeURIComponent(avatar) + "?thumb=128x128" : "",
        channel: String(post.get("channel")), body, pinned: !!post.get("pinned"),
        images: postImages(post).images, image_urls: postImages(post).image_urls,
        reply: replyPreview, reactions: reactionItems,
        created: String(post.created || ""), updated: String(post.updated || "")
    } })
}, $apis.requireRecordAuth("users"))

routerAdd("DELETE", "/api/hyse/gym-community-posts/:id", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), postID = String(c.pathParam("id") || "")
    let post
    try { post = dao.findRecordById("gym_community_posts", postID) } catch (_) { throw new NotFoundError("Post not found.") }
    const communityID = String(post.get("community")); let membership = null
    try { membership = dao.findFirstRecordByFilter("gym_community_members", "community = {:community} && user = {:user}", { community: communityID, user: user.id }) } catch (_) {}
    const role = membership ? String(membership.get("role")) : ""
    const isAuthor = String(post.get("author")) === user.id
    if (!isAuthor && role !== "owner" && role !== "admin") throw new ForbiddenError("You cannot delete this post.")
    dao.deleteRecord(post)
    return c.json(200, { deleted: true, id: postID })
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/gym-community-posts/:id/reactions", (c) => {
    const info = $apis.requestInfo(c), user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const dao = $app.dao(), postID = String(c.pathParam("id") || "")
    const emoji = String((info.data || {}).emoji || "")
    const allowed = ["👍", "❤️", "🔥", "👏", "💪", "😂"]
    if (allowed.indexOf(emoji) < 0) throw new BadRequestError("Unsupported reaction.")
    let post
    try { post = dao.findRecordById("gym_community_posts", postID) } catch (_) { throw new NotFoundError("Post not found.") }
    const communityID = String(post.get("community")); let membership = null
    try { membership = dao.findFirstRecordByFilter("gym_community_members", "community = {:community} && user = {:user}", { community: communityID, user: user.id }) } catch (_) {}
    if (!membership) throw new ForbiddenError("Join this community before reacting.")

    let existing = null
    try { existing = dao.findFirstRecordByFilter("gym_community_post_reactions", "post = {:post} && user = {:user} && emoji = {:emoji}", { post: postID, user: user.id, emoji }) } catch (_) {}
    if (existing) dao.deleteRecord(existing)
    else {
        const reaction = new Record(dao.findCollectionByNameOrId("gym_community_post_reactions"))
        reaction.set("post", postID); reaction.set("user", user.id); reaction.set("emoji", emoji); dao.saveRecord(reaction)
    }

    const reactionCounts = {}, ownReactions = {}
    const reactions = dao.findRecordsByFilter("gym_community_post_reactions", "post = {:post}", "created", 1000, 0, { post: postID })
    for (const reaction of reactions) {
        const value = String(reaction.get("emoji") || "")
        reactionCounts[value] = Number(reactionCounts[value] || 0) + 1
        if (String(reaction.get("user")) === user.id) ownReactions[value] = true
    }
    const items = Object.keys(reactionCounts).map((value) => ({ emoji: value, count: reactionCounts[value], reacted: !!ownReactions[value] }))
    return c.json(200, { reactions: items })
}, $apis.requireRecordAuth("users"))
