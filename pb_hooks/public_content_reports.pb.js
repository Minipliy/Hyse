/// <reference path="../pb_data/types.d.ts" />

// This route receives notices from the in-app report screen, including guests.
// Direct collection API access stays closed. Staff review this private queue.
routerAdd("POST", "/api/hyse/reports/public", (c) => {
    const data = $apis.requestInfo(c).data || {}
    const location = String(data.target_location || "").trim()
    const email = String(data.contact_email || "").trim().toLowerCase()
    const reason = String(data.reason || "")
    const details = String(data.details || "").trim()
    const goodFaith = data.good_faith === true || String(data.good_faith || "") === "true"
    const reasons = ["illegal", "harassment", "hate", "sexual", "violence", "privacy", "spam", "intellectual_property", "other"]

    const validID = /^[a-zA-Z0-9_-]{8,64}$/.test(location)
    const validURL = /^https?:\/\/[^\s]+$/i.test(location) && location.length <= 2048
    if (!validID && !validURL) throw new BadRequestError("Enter a content link or ID.")
    if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new BadRequestError("Enter a valid contact email.")
    if (reasons.indexOf(reason) < 0) throw new BadRequestError("Choose a valid report reason.")
    if (details.length < 10 || details.length > 2000) throw new BadRequestError("Please explain the report in 10–2000 characters.")
    if (!goodFaith) throw new BadRequestError("Confirm that the report is submitted in good faith.")

    const dao = $app.dao()
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()
    // Hash the network address for short-lived abuse control; never expose it.
    const rateKey = $security.sha256(String(c.realIP() || "unknown") + "|hyse-report-v1")
    const recent = dao.findRecordsByFilter("public_content_reports", "rate_key = {:key} && created >= {:since}", "", 11, 0, { key: rateKey, since })
    if (recent.length >= 10) throw new ApiError(429, "Daily report limit reached. Please try again later.")

    const report = new Record(dao.findCollectionByNameOrId("public_content_reports"))
    report.set("target_location", location)
    report.set("contact_email", email)
    report.set("reason", reason)
    report.set("details", details)
    report.set("good_faith", true)
    report.set("status", "pending")
    report.set("decision_reason", "")
    report.set("rate_key", rateKey)
    dao.saveRecord(report)
    return c.json(201, { id: report.id, status: "pending" })
}, $apis.bodyLimit(12000))

// The abuse-control key is needed only for a rolling 24-hour limit.
cronAdd("hyse_clear_public_report_rate_keys", "17 * * * *", () => {
    const dao = $app.dao()
    // Hourly execution with a 47-hour cutoff clears keys within 48 hours.
    const before = new Date(Date.now() - 47 * 60 * 60 * 1000).toISOString()
    let records = []
    try { records = dao.findRecordsByFilter("public_content_reports", "rate_key != '' && created < {:before}", "", 500, 0, { before }) } catch (_) { return }
    for (const report of records) {
        report.set("rate_key", "")
        dao.saveRecord(report)
    }
})
