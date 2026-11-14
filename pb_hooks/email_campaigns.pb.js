/// <reference path="../pb_data/types.d.ts" />

routerAdd("GET", "/api/hyse/admin/email-campaigns/summary", (c) => {
    const sender = String($os.getenv("HYSE_SENDER_EMAIL") || "support@example.com"), expected = String($os.getenv("HYSE_EMAIL_ADMIN_TOKEN") || "").trim()
    let provided = ""
    try { provided = String(c.request().header.get("X-Hyse-Email-Admin-Token") || "").trim() } catch (_) {}
    if (!expected || !provided || provided !== expected) throw new UnauthorizedError("Email campaign authorization required.")
    const dao = $app.dao()
    const recipientsFor = () => {
        const result = []
        for (const user of dao.findRecordsByFilter("users", "email != '' && verified = true", "email", 5000, 0, {})) {
            let state = null
            try { state = dao.findFirstRecordByFilter("user_account_state", "user = {:user}", { user: user.id }) } catch (_) {}
            if (!state || !state.getBool("marketing_consent")) continue
            result.push(user)
        }
        return result
    }
    const campaigns = dao.findRecordsByFilter("hyse_email_campaigns", "id != ''", "-created", 30, 0, {})
    const serialize = (record) => ({ id: record.id, subject: String(record.get("subject") || ""), body: String(record.get("body") || ""), category: String(record.get("category") || "update"), status: String(record.get("status") || "draft"), recipient_count: Number(record.get("recipient_count") || 0), sent_count: Number(record.get("sent_count") || 0), failed_count: Number(record.get("failed_count") || 0), sent_at: String(record.get("sent_at") || ""), created: String(record.created || "") })
    const recipientCount = recipientsFor().length
    return c.json(200, { sender, recipients: { update: recipientCount, promo: 0, motivation: 0 }, campaigns: campaigns.map(serialize) })
})

routerAdd("GET", "/api/hyse/admin/email-campaigns/recipients", (c) => {
    const expected = String($os.getenv("HYSE_EMAIL_ADMIN_TOKEN") || "").trim()
    let provided = ""
    try { provided = String(c.request().header.get("X-Hyse-Email-Admin-Token") || "").trim() } catch (_) {}
    if (!expected || !provided || provided !== expected) throw new UnauthorizedError("Email campaign authorization required.")
    const dao = $app.dao(), recipients = []
    for (const user of dao.findRecordsByFilter("users", "email != '' && verified = true", "email", 5000, 0, {})) {
        let state = null
        try { state = dao.findFirstRecordByFilter("user_account_state", "user = {:user}", { user: user.id }) } catch (_) {}
        if (!state || !state.getBool("marketing_consent")) continue
        recipients.push({ name: String(user.get("name") || ""), username: String(user.get("username") || ""), email: String(user.email() || "").trim().toLowerCase() })
    }
    return c.json(200, { recipients })
})

routerAdd("POST", "/api/hyse/admin/email-campaigns", (c) => {
    const sender = String($os.getenv("HYSE_SENDER_EMAIL") || "support@example.com"), expected = String($os.getenv("HYSE_EMAIL_ADMIN_TOKEN") || "").trim()
    let provided = ""
    try { provided = String(c.request().header.get("X-Hyse-Email-Admin-Token") || "").trim() } catch (_) {}
    if (!expected || !provided || provided !== expected) throw new UnauthorizedError("Email campaign authorization required.")
    const data = $apis.requestInfo(c).data || {}, subject = String(data.subject || "").trim(), body = String(data.body || "").trim(), category = String(data.category || "update").trim()
    const send = data.send === true || String(data.send || "").toLowerCase() === "true"
    if (!subject || subject.length > 180) throw new BadRequestError("A subject between 1 and 180 characters is required.")
    if (!body || body.length > 10000) throw new BadRequestError("A message between 1 and 10000 characters is required.")
    if (["update", "promo", "motivation"].indexOf(category) < 0) throw new BadRequestError("Invalid campaign category.")
    if (send && category !== "update") throw new BadRequestError("This email category requires a separate, explicit opt-in before sending.")
    const dao = $app.dao(), recipients = []
    for (const user of dao.findRecordsByFilter("users", "email != '' && verified = true", "email", 5000, 0, {})) {
        let state = null
        try { state = dao.findFirstRecordByFilter("user_account_state", "user = {:user}", { user: user.id }) } catch (_) {}
        if (!state || !state.getBool("marketing_consent")) continue
        const address = String(user.email() || "").trim().toLowerCase()
        if (address) recipients.push({ userID: user.id, address, language: String(state.get("marketing_consent_language") || "de") })
    }
    const campaign = new Record(dao.findCollectionByNameOrId("hyse_email_campaigns"))
    campaign.set("subject", subject); campaign.set("body", body); campaign.set("category", category); campaign.set("status", send ? "sending" : "draft")
    campaign.set("recipient_count", recipients.length); campaign.set("sent_count", 0); campaign.set("failed_count", 0); dao.saveRecord(campaign)
    const payload = () => ({ id: campaign.id, subject, body, category, status: String(campaign.get("status") || "draft"), recipient_count: Number(campaign.get("recipient_count") || 0), sent_count: Number(campaign.get("sent_count") || 0), failed_count: Number(campaign.get("failed_count") || 0), sent_at: String(campaign.get("sent_at") || ""), created: String(campaign.created || "") })
    if (!send) return c.json(201, { campaign: payload(), sender })
    const escape = (value) => String(value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\"/g, "&quot;").replace(/'/g, "&#039;")
    const labels = { update: "Hyse Update", promo: "Hyse Special", motivation: "Dein Hyse Moment" }
    let sent = 0, failed = 0, firstError = ""
    for (const recipient of recipients) {
        try {
            const rawToken = $security.randomString(48)
            const tokenRecord = new Record(dao.findCollectionByNameOrId("hyse_email_unsubscribe_tokens"))
            tokenRecord.set("user", recipient.userID)
            tokenRecord.set("token_hash", $security.sha256(rawToken))
            dao.saveRecord(tokenRecord)
            const unsubscribeURL = String($os.getenv("HYSE_PUBLIC_URL") || "http://localhost:8090").replace(/\/+$/, "") + "/api/hyse/email/unsubscribe/" + encodeURIComponent(rawToken)
            const isGerman = recipient.language !== "en"
            const reason = isGerman ? "Du erhältst diese E-Mail, weil du Produktneuigkeiten und hilfreiche Tipps in Hyse aktiviert hast." : "You are receiving this email because product news and helpful tips are enabled in Hyse."
            const unsubscribeLabel = isGerman ? "E-Mails abbestellen" : "Unsubscribe from emails"
            const html = `<!doctype html><html lang="${isGerman ? "de" : "en"}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escape(subject)}</title></head><body style="margin:0;padding:0;background:#ffffff;color:#172624;font-family:Arial,Helvetica,sans-serif"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#ffffff;padding:28px 12px"><tr><td align="center"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;background:#ffffff;border:1px solid #dce4e2;border-radius:10px;overflow:hidden"><tr><td style="padding:22px 30px;background:#123b39;color:#ffffff"><span style="font-size:25px;font-weight:800;letter-spacing:-1px">hyse</span><span style="float:right;color:#a5fa78;font-size:10px;font-weight:800;letter-spacing:1.5px;line-height:30px">NEWS</span></td></tr><tr><td style="padding:36px 32px 30px"><div style="margin:0 0 10px;color:#18796f;font-size:11px;font-weight:800;letter-spacing:1.4px">${escape(labels[category])}</div><h1 style="margin:0 0 16px;color:#172624;font-size:31px;line-height:1.16;letter-spacing:-1px">${escape(subject)}</h1><p style="margin:0;color:#536563;font-size:16px;line-height:1.7">${escape(body).replace(/\r?\n/g, "<br>")}</p></td></tr><tr><td align="center" style="padding:22px 32px 8px;border-top:1px solid #e3e8e7"><a href="${unsubscribeURL}" style="display:inline-block;padding:11px 18px;border:1px solid #18796f;border-radius:8px;color:#18796f;font-size:13px;font-weight:700;text-decoration:none">${unsubscribeLabel}</a></td></tr><tr><td style="padding:10px 32px 24px;color:#71817f;font-size:12px;line-height:1.6;text-align:center">${reason}<br><a href="mailto:${sender}" style="color:#18796f;font-weight:700;text-decoration:none">${sender}</a></td></tr></table></td></tr></table></body></html>`
            $app.newMailClient().send(new MailerMessage({ from: { address: sender, name: "Hyse" }, to: [{ address: recipient.address }], subject, html }))
            sent++
        }
        catch (error) { failed++; if (!firstError) firstError = String(error || "Mail delivery failed").slice(0, 1000) }
    }
    campaign.set("sent_count", sent); campaign.set("failed_count", failed); campaign.set("status", failed ? (sent ? "sent" : "failed") : "sent"); campaign.set("sent_at", new Date().toISOString()); campaign.set("error", firstError); dao.saveRecord(campaign)
    return c.json(failed && !sent ? 502 : 200, { campaign: payload(), sender })
})

routerAdd("GET", "/api/hyse/email/unsubscribe/:token", (c) => {
    const token = String(c.pathParam("token") || "").trim()
    if (!token) throw new BadRequestError("The unsubscribe link is invalid.")

    const dao = $app.dao()
    let unsubscribe = null
    try { unsubscribe = dao.findFirstRecordByFilter("hyse_email_unsubscribe_tokens", "token_hash = {:hash}", { hash: $security.sha256(token) }) } catch (_) {}
    if (!unsubscribe) throw new BadRequestError("The unsubscribe link is invalid.")

    const userID = String(unsubscribe.get("user") || "")
    const now = new Date().toISOString()
    dao.runInTransaction((txDao) => {
        const currentToken = txDao.findRecordById("hyse_email_unsubscribe_tokens", unsubscribe.id)
        let state = null
        try { state = txDao.findFirstRecordByFilter("user_account_state", "user = {:user}", { user: userID }) } catch (_) {}
        if (!state) {
            state = new Record(txDao.findCollectionByNameOrId("user_account_state"))
            state.set("user", userID)
        }
        const language = String(state.get("marketing_consent_language") || "de") === "en" ? "en" : "de"
        state.set("marketing_consent", false)
        state.set("marketing_updated_at", now)
        state.set("marketing_consent_language", language)
        if (!state.get("marketing_privacy_version")) state.set("marketing_privacy_version", "privacy-2026-09-1")
        currentToken.set("used_at", now)
        txDao.saveRecord(state)
        txDao.saveRecord(currentToken)

        let latest = null
        try { latest = txDao.findFirstRecordByFilter("user_consents", "user = {:user} && category = 'marketing_email'", "-recorded_at", { user: userID }) } catch (_) {}
        if (!latest || latest.getBool("granted")) {
            const receipt = new Record(txDao.findCollectionByNameOrId("user_consents"))
            receipt.set("user", userID)
            receipt.set("installation_id", "email_unsubscribe")
            receipt.set("category", "marketing_email")
            receipt.set("granted", false)
            receipt.set("document_version", String(state.get("marketing_privacy_version") || "privacy-2026-09-1"))
            receipt.set("language", language)
            receipt.set("source", "email_unsubscribe")
            receipt.set("recorded_at", now)
            receipt.set("revoked_at", now)
            txDao.saveRecord(receipt)
        }
    })

    c.response().header().set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'")
    return c.html(200, `<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark"><title>E-Mails abbestellt · Hyse</title><style>:root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;background:#edf1f0;color:#17201f}*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;padding:22px;background:#edf1f0}main{width:min(100%,520px);padding:34px;border:1px solid #d9e0de;border-radius:26px;background:#fff;text-align:center;box-shadow:0 18px 55px rgba(20,42,39,.12)}.mark{width:58px;height:58px;margin:0 auto 20px;display:grid;place-items:center;border-radius:18px;background:#0e8c82;color:#fff;font-size:30px;font-weight:800}h1{margin:0 0 12px;font-size:30px;letter-spacing:-.6px}p{margin:0;color:#586462;line-height:1.6}@media(prefers-color-scheme:dark){:root,body{background:#111515;color:#f4f7f6}main{background:#1c2121;border-color:#343c3c}p{color:#adb7b5}}</style></head><body><main><div class="mark">✓</div><h1>E-Mails abbestellt</h1><p>„Produktneuigkeiten und hilfreiche Tipps“ ist jetzt ausgeschaltet. Du erhältst keine weiteren Hyse-Update-E-Mails. Beim nächsten Öffnen der App wird die Einstellung automatisch aktualisiert.</p></main></body></html>`)
})
