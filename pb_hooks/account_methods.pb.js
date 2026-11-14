/// <reference path="../pb_data/types.d.ts" />

routerAdd("GET", "/api/hyse/account-methods", (c) => {
    const authRecord = $apis.requestInfo(c).authRecord
    if (!authRecord) throw new UnauthorizedError("Authentication required.")

    const providers = []
    try {
        const external = $app.dao().findAllExternalAuthsByRecord(authRecord)
        for (const item of external) {
            const provider = String(item.provider || "").toLowerCase()
            if (provider && providers.indexOf(provider) < 0) providers.push(provider)
        }
    } catch (_) {}

    // PocketBase stores an internal random password hash for OAuth-created
    // records too. Only this explicit field represents a password the user
    // actually configured and can enter.
    let hasPassword = false
    try { hasPassword = authRecord.getBool("has_local_password") } catch (_) {}

    return c.json(200, { hasPassword, providers })
}, $apis.requireRecordAuth("users"))
