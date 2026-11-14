/// <reference path="../pb_data/types.d.ts" />

const hyseAppleProducts = {
    "com.hyse.HyseApp.premium.nutrition.monthly": "nutrition",
    "com.hyse.HyseApp.premium.training.monthly": "training",
    "com.hyse.HyseApp.premium.complete.monthly": "complete",
    "hyse.nutrition.lifetimenew": "nutrition",
    "hyse.training.lifetime": "training",
    "hyse.complete.lifetime": "complete"
}

function hyseAppleVerifyReceipt(receipt, preferredEnvironment) {
    const secret = String($os.getenv("APPLE_IAP_SHARED_SECRET") || "").trim()
    if (!secret) throw new InternalServerError("Apple purchase linking is not configured.")
    const body = JSON.stringify({ "receipt-data": receipt, password: secret, "exclude-old-transactions": false })
    const send = (environment) => $http.send({
        url: environment === "Sandbox" ? "https://sandbox.itunes.apple.com/verifyReceipt" : "https://buy.itunes.apple.com/verifyReceipt",
        method: "POST", headers: { "Content-Type": "application/json" }, body, timeout: 15
    })
    let environment = preferredEnvironment === "Sandbox" ? "Sandbox" : "Production"
    let result = send(environment)
    if (result.statusCode !== 200) throw new InternalServerError("Apple purchase verification is unavailable.")
    if (Number(result.json.status) === 21007 && environment !== "Sandbox") {
        environment = "Sandbox"; result = send(environment)
    } else if (Number(result.json.status) === 21008 && environment !== "Production") {
        environment = "Production"; result = send(environment)
    }
    if (result.statusCode !== 200 || Number(result.json.status) !== 0 ||
        String((result.json.receipt || {}).bundle_id || "") !== "com.hyse.HyseApp") {
        throw new BadRequestError("Apple could not verify this Hyse purchase.")
    }
    const transactions = [].concat(result.json.receipt.in_app || [], result.json.latest_receipt_info || [])
    const latest = {}
    for (const transaction of transactions) {
        const product = String(transaction.product_id || "")
        const originalID = String(transaction.original_transaction_id || "")
        if (!hyseAppleProducts[product] || !/^\d{6,30}$/.test(originalID)) continue
        const expiryMs = Number(transaction.expires_date_ms || 0)
        const revoked = Boolean(transaction.cancellation_date_ms || transaction.cancellation_date)
        const active = !revoked && (!product.endsWith(".monthly") || expiryMs > Date.now())
        const prior = latest[originalID]
        const purchaseMs = Number(transaction.purchase_date_ms || 0)
        if (!prior || purchaseMs >= prior.purchaseMs) latest[originalID] = { originalID, product, expiryMs, purchaseMs, active }
    }
    return { environment, transactions: Object.values(latest).filter((item) => item.active) }
}

function hyseAppleStoreClaims(user, receipt, preferredEnvironment) {
    const verified = hyseAppleVerifyReceipt(receipt, preferredEnvironment)
    const dao = $app.dao()
    dao.runInTransaction((tx) => {
        // A purchase may be linked once. A second Hyse account must not be able
        // to claim it by presenting the same Apple receipt.
        for (const item of verified.transactions) {
            let existing = null
            try { existing = tx.findFirstRecordByFilter("premium_apple_claims", "original_transaction_id = {:id}", { id: item.originalID }) } catch (_) {}
            if (existing && String(existing.get("user")) !== user.id) throw new BadRequestError("This Apple purchase is already linked to another Hyse account.")
        }
        let savedReceipt = null
        try { savedReceipt = tx.findFirstRecordByFilter("premium_apple_receipts", "user = {:user}", { user: user.id }) } catch (_) {}
        if (!savedReceipt) savedReceipt = new Record(tx.findCollectionByNameOrId("premium_apple_receipts"))
        savedReceipt.set("user", user.id)
        savedReceipt.set("receipt_data", receipt)
        savedReceipt.set("environment", verified.environment)
        tx.saveRecord(savedReceipt)
        for (const item of verified.transactions) {
            let claim = null
            try { claim = tx.findFirstRecordByFilter("premium_apple_claims", "original_transaction_id = {:id}", { id: item.originalID }) } catch (_) {}
            if (!claim) claim = new Record(tx.findCollectionByNameOrId("premium_apple_claims"))
            claim.set("user", user.id)
            claim.set("original_transaction_id", item.originalID)
            claim.set("product_id", item.product)
            claim.set("expires_at", item.expiryMs ? new Date(item.expiryMs).toISOString() : "")
            tx.saveRecord(claim)
        }
    })
    return verified
}

function hyseAppleEntitlementResponse(verified) {
    const products = verified.transactions.map((item) => item.product)
    const kinds = products.map((product) => hyseAppleProducts[product])
    return { product_ids: products, has_nutrition: kinds.includes("nutrition") || kinds.includes("complete"),
        has_training: kinds.includes("training") || kinds.includes("complete") }
}

routerAdd("POST", "/api/hyse/premium/apple", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    const receipt = String(($apis.requestInfo(c).data || {}).receipt || "")
    if (receipt.length < 100 || receipt.length > 2000000 || !/^[A-Za-z0-9+/=]+$/.test(receipt)) {
        throw new BadRequestError("Invalid Apple receipt.")
    }
    return c.json(200, hyseAppleEntitlementResponse(hyseAppleStoreClaims(user, receipt, "Production")))
}, $apis.requireRecordAuth("users"))

routerAdd("GET", "/api/hyse/premium/apple", (c) => {
    const user = $apis.requestInfo(c).authRecord
    if (!user) throw new UnauthorizedError("Authentication required.")
    let saved = null
    try { saved = $app.dao().findFirstRecordByFilter("premium_apple_receipts", "user = {:user}", { user: user.id }) } catch (_) {}
    if (!saved) return c.json(200, { product_ids: [], has_nutrition: false, has_training: false })
    const verified = hyseAppleStoreClaims(user, String(saved.get("receipt_data")), String(saved.get("environment")))
    // Old purchases in the receipt may have expired or been revoked; the
    // current Apple response alone determines access.
    return c.json(200, hyseAppleEntitlementResponse(verified))
}, $apis.requireRecordAuth("users"))
