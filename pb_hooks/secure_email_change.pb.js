/// <reference path="../pb_data/types.d.ts" />

const hyseEmailChangeLifetimeMs = 30 * 60 * 1000
const hyseReauthLifetimeMs = 5 * 60 * 1000

// Disable PocketBase's password-based confirmation endpoint for app requests. Hyse uses the
// reauthentication + one-time-token flow below for password and OAuth accounts alike.
onRecordBeforeRequestEmailChangeRequest(() => {
    throw new ForbiddenError("Use the Hyse secure email change flow.")
}, "users")

function hyseExpiry(milliseconds) {
    return new Date(Date.now() + milliseconds).toISOString()
}

function hyseEscape(value) {
    return String(value || "").replace(/[&<>\"']/g, (character) => ({
        "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"
    })[character])
}

function hyseAccountEmail(options) {
    const actionURL = options.actionURL ? hyseEscape(options.actionURL) : ""
    const action = actionURL ? `
        <tr><td class="hyse-content" style="padding:14px 32px 24px;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"><tr><td class="hyse-button-cell" align="center" style="border-radius:14px;background:#0e8c82;"><a class="hyse-button" href="${actionURL}" style="display:block;padding:15px 22px;border-radius:14px;color:#ffffff;text-decoration:none;font-size:16px;line-height:1.25;font-weight:750;">${options.button}</a></td></tr></table>
        </td></tr>
        <tr><td class="hyse-content" style="padding:0 32px 30px;">
          <table class="hyse-panel" role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;background:#f3f6f5;border:1px solid #dfe6e4;border-radius:15px;"><tr><td style="padding:16px 17px;"><div class="hyse-strong" style="margin-bottom:5px;font-size:13px;line-height:1.4;font-weight:800;color:#27312f;">Secure one-time link</div><div class="hyse-muted" style="font-size:13px;line-height:1.55;color:#687371;">This confirmation link expires after 30 minutes and can only be used once.</div></td></tr></table>
          <div class="hyse-muted" style="margin:18px 0 7px;font-size:12px;line-height:1.55;color:#73807d;">If the button does not open, copy this link into your browser:</div><div style="word-break:break-all;font-size:11px;line-height:1.55;"><a class="hyse-link" href="${actionURL}" style="color:#08766e;text-decoration:underline;">${actionURL}</a></div>
        </td></tr>` : ""

    return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark"><title>${options.title}</title><style>
      :root{color-scheme:light dark;supported-color-schemes:light dark}
      @media(prefers-color-scheme:dark){.hyse-page,.hyse-shell{background:#111515!important}.hyse-card{background:#1c2121!important;border-color:#343c3c!important}.hyse-brand{background:#171c1c!important;border-color:#343c3c!important}.hyse-title,.hyse-strong{color:#f4f7f6!important}.hyse-copy,.hyse-muted{color:#adb7b5!important}.hyse-panel{background:#151a1a!important;border-color:#343c3c!important}.hyse-link{color:#69d4ca!important}.hyse-rule{background:#343c3c!important}}
      @media only screen and (max-width:620px){.hyse-shell-cell{padding:18px 10px!important}.hyse-content{padding-left:22px!important;padding-right:22px!important}.hyse-title{font-size:28px!important}.hyse-button-cell,.hyse-button{display:block!important;width:100%!important;box-sizing:border-box!important;text-align:center!important}}
    </style></head><body class="hyse-page" style="margin:0;padding:0;background:#edf1f0;color:#17201f;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Segoe UI',Roboto,Helvetica,Arial,sans-serif;-webkit-text-size-adjust:100%;"><div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;mso-hide:all;">${options.preheader}</div><table class="hyse-shell" role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;background:#edf1f0;"><tr><td class="hyse-shell-cell" align="center" style="padding:38px 12px;"><table class="hyse-card" role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;max-width:600px;background:#ffffff;border:1px solid #d9e0de;border-radius:26px;overflow:hidden;"><tr><td class="hyse-brand hyse-content" style="padding:22px 30px;background:#17201f;border-bottom:1px solid #303938;"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"><tr><td><table role="presentation" cellspacing="0" cellpadding="0" border="0"><tr><td width="40" height="40" align="center" valign="middle" style="width:40px;height:40px;border-radius:12px;background:#19a99b;color:#ffffff;font-size:18px;line-height:40px;font-weight:800;">H</td><td style="padding-left:12px;color:#ffffff;font-size:20px;line-height:1.2;font-weight:800;">Hyse</td></tr></table></td><td align="right"><span style="display:inline-block;padding:7px 10px;border:1px solid #42504e;border-radius:999px;color:#cbd5d3;font-size:10px;line-height:1;font-weight:800;letter-spacing:1px;text-transform:uppercase;">Security</span></td></tr></table></td></tr><tr><td class="hyse-content" style="padding:37px 32px 16px;"><div style="font-size:11px;line-height:1.4;font-weight:800;letter-spacing:1.4px;text-transform:uppercase;color:#0e857b;">${options.eyebrow}</div><h1 class="hyse-title" style="margin:9px 0 14px;font-size:32px;line-height:1.15;letter-spacing:-.8px;color:#17201f;">${options.title}</h1><p class="hyse-copy" style="margin:0;font-size:16px;line-height:1.65;color:#586462;">${options.message}</p></td></tr>${action}<tr><td class="hyse-content" style="padding:${actionURL ? "0" : "8px"} 32px 32px;"><div class="hyse-rule" style="height:1px;background:#e1e7e5;margin:0 0 18px;"></div><p class="hyse-muted" style="margin:0;font-size:13px;line-height:1.58;color:#687371;">${options.note}</p></td></tr></table><p class="hyse-muted" style="max-width:600px;margin:17px auto 0;font-size:12px;line-height:1.65;color:#687371;">Hyse · Nutrition, training and health<br><a class="hyse-link" href="${String($os.getenv("HYSE_PUBLIC_URL") || "http://localhost:8090").replace(/\/+$/, "")}" style="color:#08766e;text-decoration:none;">Website</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a class="hyse-link" href="mailto:${String($os.getenv("HYSE_CONTACT_EMAIL") || "support@example.com")}" style="color:#08766e;text-decoration:none;">Support</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a class="hyse-link" href="${String($os.getenv("HYSE_PUBLIC_URL") || "http://localhost:8090").replace(/\/+$/, "")}/privacy" style="color:#08766e;text-decoration:none;">Privacy</a></p></td></tr></table></body></html>`
}

function hyseAuthorizationToken(c) {
    const info = $apis.requestInfo(c)
    const header = String((info.headers || {}).authorization || (info.headers || {}).Authorization || "")
    return header.replace(/^Bearer\s+/i, "").trim()
}

function hyseRememberReauthentication(record, token, method) {
    if (!record || !token || ["password", "google", "apple"].indexOf(method) < 0) return
    const dao = $app.dao()
    const collection = dao.findCollectionByNameOrId("hyse_reauth_sessions")
    const session = new Record(collection)
    session.set("user", record.id)
    session.set("token_hash", $security.sha256(token))
    session.set("method", method)
    session.set("expires_at", hyseExpiry(hyseReauthLifetimeMs))
    session.set("used", false)
    try { dao.saveRecord(session) } catch (_) {}
}

// PocketBase 0.22 calls the provider/password-specific "after" hook before
// creating the common auth response. Mark that request context, then bind the
// freshly issued token in onRecordAuthRequest. Refresh requests never receive
// such a marker and therefore cannot substitute for reauthentication.
onRecordAfterAuthWithPasswordRequest((e) => {
    try { e.httpContext.set("hyse_reauth_method", "password") } catch (_) {}
}, "users")

onRecordAfterAuthWithOAuth2Request((e) => {
    try {
        const provider = String(e.providerName || "").toLowerCase()
        if (provider === "google" || provider === "apple") e.httpContext.set("hyse_reauth_method", provider)
    } catch (_) {}
}, "users")

onRecordAuthRequest((e) => {
    // Reauthentication tracking is supplementary account-management state.
    // It must never turn an otherwise successful login into a failed OAuth
    // response when a PocketBase context API differs between patch versions.
    try {
        const method = String(e.httpContext.get("hyse_reauth_method") || "").toLowerCase()
        hyseRememberReauthentication(e.record, e.token, method)
    } catch (_) {}
}, "users")

onRecordAfterConfirmPasswordResetRequest((e) => {
    try {
        e.record.set("has_local_password", true)
        $app.dao().saveRecord(e.record)
    } catch (_) {}
}, "users")

routerAdd("POST", "/api/hyse/request-email-change", (c) => {
    const info = $apis.requestInfo(c)
    const user = info.authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")

    const newEmail = String((info.data || {}).newEmail || "").trim().toLowerCase()
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(newEmail) || newEmail === String(user.email()).toLowerCase()) {
        throw new BadRequestError("Enter a valid, different email address.")
    }

    const dao = $app.dao()
    let existing = null
    try { existing = dao.findAuthRecordByEmail("users", newEmail) } catch (_) {}
    if (existing && existing.id !== user.id) throw new BadRequestError("This email address is already in use.")

    const authToken = hyseAuthorizationToken(c)
    if (!authToken) throw new UnauthorizedError("Recent authentication required.")
    let reauth = null
    try {
        reauth = dao.findFirstRecordByFilter("hyse_reauth_sessions", "user = {:user} && token_hash = {:hash} && used = false", {
            user: user.id, hash: $security.sha256(authToken)
        })
    } catch (_) {}
    if (!reauth || Date.parse(String(reauth.get("expires_at"))) <= Date.now()) {
        throw new ForbiddenError("Please confirm your identity again before changing your email address.")
    }

    const rawToken = $security.randomString(48)
    const requestCollection = dao.findCollectionByNameOrId("hyse_email_change_requests")
    const request = new Record(requestCollection)
    request.set("user", user.id)
    request.set("old_email", user.email())
    request.set("new_email", newEmail)
    request.set("token_hash", $security.sha256(rawToken))
    request.set("expires_at", hyseExpiry(hyseEmailChangeLifetimeMs))
    request.set("used", false)

    reauth.set("used", true)
    dao.runInTransaction((txDao) => {
        txDao.saveRecord(reauth)
        const older = txDao.findRecordsByFilter("hyse_email_change_requests", "user = {:user} && used = false", "", 50, 0, { user: user.id })
        for (const item of older) txDao.deleteRecord(item)
        txDao.saveRecord(request)
    })

    const actionURL = String($os.getenv("HYSE_PUBLIC_URL") || "http://localhost:8090").replace(/\/+$/, "") + "/email-change/#token=" + encodeURIComponent(rawToken)
    const message = new MailerMessage({
        from: { address: $app.settings().meta.senderAddress, name: "Hyse" },
        to: [{ address: newEmail }],
        subject: "Confirm your new email · Hyse",
        html: hyseAccountEmail({
            preheader: "Confirm the new email address for your Hyse account.",
            eyebrow: "Email change",
            title: "Confirm your new email",
            message: `Use this one-time link within 30 minutes to confirm <strong class="hyse-strong">${hyseEscape(newEmail)}</strong> for your Hyse account.`,
            button: "Confirm new email",
            actionURL: actionURL,
            note: "If you did not request this change, do not open the link and contact Hyse support."
        })
    })
    try {
        $app.newMailClient().send(message)
    } catch (error) {
        try { dao.deleteRecord(request) } catch (_) {}
        throw error
    }
    return c.noContent(204)
}, $apis.requireRecordAuth("users"))

routerAdd("POST", "/api/hyse/confirm-email-change", (c) => {
    const token = String(($apis.requestInfo(c).data || {}).token || "").trim()
    if (!token) throw new BadRequestError("The confirmation link is invalid.")

    const dao = $app.dao()
    let pending = null
    try { pending = dao.findFirstRecordByFilter("hyse_email_change_requests", "token_hash = {:hash}", { hash: $security.sha256(token) }) } catch (_) {}
    if (!pending || pending.getBool("used") || Date.parse(String(pending.get("expires_at"))) <= Date.now()) {
        throw new BadRequestError("This confirmation link is invalid, expired, or has already been used.")
    }

    const user = dao.findRecordById("users", String(pending.get("user")))
    const oldEmail = String(user.email())
    const newEmail = String(pending.get("new_email"))
    dao.runInTransaction((txDao) => {
        const current = txDao.findRecordById("hyse_email_change_requests", pending.id)
        if (current.getBool("used") || Date.parse(String(current.get("expires_at"))) <= Date.now()) {
            throw new BadRequestError("This confirmation link is invalid, expired, or has already been used.")
        }
        const account = txDao.findRecordById("users", String(current.get("user")))
        account.setEmail(newEmail)
        account.setVerified(true)
        account.refreshTokenKey()
        current.set("used", true)
        txDao.saveRecord(account)
        txDao.saveRecord(current)
    })

    if (oldEmail && oldEmail.toLowerCase() !== newEmail.toLowerCase()) {
        try {
            $app.newMailClient().send(new MailerMessage({
                from: { address: $app.settings().meta.senderAddress, name: "Hyse" },
                to: [{ address: oldEmail }],
                subject: "Your email address was changed · Hyse",
                html: hyseAccountEmail({
                    preheader: "The email address for your Hyse account was changed.",
                    eyebrow: "Security notice",
                    title: "Email address changed",
                    message: `The email address for your Hyse account was changed to <strong class="hyse-strong">${hyseEscape(newEmail)}</strong>.`,
                    button: "",
                    actionURL: "",
                    note: "If this was not you, contact Hyse support immediately so the account can be secured."
                })
            }))
        } catch (_) {}
    }
    return c.json(200, { success: true })
})
