/// <reference path="../pb_data/types.d.ts" />

// Root is the only language-negotiated URL. Concrete /en and /de routes are
// stable, directly addressable and never redirected by browser language.
routerAdd("GET", "/", (c) => {
    const requestHeader = (name) => {
        try { return String(c.request().header.get(name) || "") } catch (_) {}
        try {
            const headers = $apis.requestInfo(c).headers || {}
            return String(headers[name] || headers[name.toLowerCase()] || "")
        } catch (_) { return "" }
    }
    const cookie = requestHeader("Cookie")
    const saved = cookie.match(/(?:^|;\s*)hyse_language=(de|en)(?:;|$)/)
    if (saved) return c.redirect(302, String($os.getenv("HYSE_PUBLIC_URL") || "http://localhost:8090").replace(/\/+$/, "") + "/" + saved[1])

    const accepted = requestHeader("Accept-Language").toLowerCase()
    const firstPreference = accepted.split(",")[0].trim()
    return c.redirect(302, String($os.getenv("HYSE_PUBLIC_URL") || "http://localhost:8090").replace(/\/+$/, "") + (firstPreference === "de" || firstPreference.startsWith("de-") ? "/de" : "/en"))
})

// Shared pages stay in the browser and offer an explicit app button.
routerAdd("GET", "/.well-known/apple-app-site-association", (c) => {
    return c.json(200, {
        applinks: {
            details: [{
                appIDs: [String($os.getenv("HYSE_APPLE_APP_ID") || "ABCDE12345.com.deinname.hyse")],
                components: [
                    { "/": "/*", exclude: true, comment: "All HTTPS links stay in the browser" }
                ]
            }]
        }
    })
})

// Visitors without the app see an App Store fallback. The app button also
// covers browsers that do not dispatch Universal Links.
routerAdd("GET", "/en/workout/:id", (c) => {
    const appURL = "hyseapp://workout/" + encodeURIComponent(String(c.pathParam("id") || ""))
    const configuredStoreURL = String($os.getenv("HYSE_APP_STORE_URL") || "").trim()
    const storeURL = /^https:\/\/apps\.apple\.com\//.test(configuredStoreURL)
        ? configuredStoreURL
        : "https://apps.apple.com/de/app/hyse/id6811359623"
    return c.html(200, `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,follow"><title>Open workout in Hyse</title><style>body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;box-sizing:border-box;background:#edf4f3;color:#152522;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif}main{max-width:440px;text-align:center;padding:36px 28px;background:#fff;border:1px solid #d4e2df;border-radius:28px;box-shadow:0 18px 50px #16443a1f}.mark{width:64px;height:64px;margin:0 auto 18px;display:grid;place-items:center;border-radius:20px;background:#087c73;color:#fff;font-weight:800;font-size:24px}h1{margin:0 0 12px;font-size:28px;letter-spacing:-.5px}p{margin:0 0 24px;color:#52635f;line-height:1.55}a{display:block;padding:15px 20px;border-radius:15px;background:#087c73;color:white;text-decoration:none;font-weight:700}a.secondary{margin-top:12px;background:transparent;color:#087c73;border:1px solid #087c73}@media(prefers-color-scheme:dark){body{background:#0d1614;color:#edf7f4}main{background:#17221f;border-color:#2d403b}p{color:#b7c8c2}a.secondary{color:#8ee2d4;border-color:#8ee2d4}}</style></head><body><main><div class="mark">HY</div><h1>Open this workout in Hyse</h1><p>Open the shared workout in Hyse, or download Hyse for iPhone.</p><a href="${appURL}">Open in Hyse</a><a class="secondary" href="${storeURL}">Get Hyse</a></main></body></html>`)
})

routerAdd("GET", "/de/training/:id", (c) => {
    const appURL = "hyseapp://workout/" + encodeURIComponent(String(c.pathParam("id") || ""))
    const configuredStoreURL = String($os.getenv("HYSE_APP_STORE_URL") || "").trim()
    const storeURL = /^https:\/\/apps\.apple\.com\//.test(configuredStoreURL)
        ? configuredStoreURL
        : "https://apps.apple.com/de/app/hyse/id6811359623"
    return c.html(200, `<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,follow"><title>Training in Hyse öffnen</title><style>body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;box-sizing:border-box;background:#edf4f3;color:#152522;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif}main{max-width:440px;text-align:center;padding:36px 28px;background:#fff;border:1px solid #d4e2df;border-radius:28px;box-shadow:0 18px 50px #16443a1f}.mark{width:64px;height:64px;margin:0 auto 18px;display:grid;place-items:center;border-radius:20px;background:#087c73;color:#fff;font-weight:800;font-size:24px}h1{margin:0 0 12px;font-size:28px;letter-spacing:-.5px}p{margin:0 0 24px;color:#52635f;line-height:1.55}a{display:block;padding:15px 20px;border-radius:15px;background:#087c73;color:white;text-decoration:none;font-weight:700}a.secondary{margin-top:12px;background:transparent;color:#087c73;border:1px solid #087c73}@media(prefers-color-scheme:dark){body{background:#0d1614;color:#edf7f4}main{background:#17221f;border-color:#2d403b}p{color:#b7c8c2}a.secondary{color:#8ee2d4;border-color:#8ee2d4}}</style></head><body><main><div class="mark">HY</div><h1>Öffne dieses Training in Hyse</h1><p>Öffne das geteilte Training in Hyse oder lade Hyse für iPhone herunter.</p><a href="${appURL}">In Hyse öffnen</a><a class="secondary" href="${storeURL}">Hyse laden</a></main></body></html>`)
})

routerAdd("GET", "/privacy", (c) => c.redirect(308, String($os.getenv("HYSE_PUBLIC_URL") || "http://localhost:8090").replace(/\/+$/, "") + "/en/privacy"))
routerAdd("GET", "/terms", (c) => c.redirect(308, String($os.getenv("HYSE_PUBLIC_URL") || "http://localhost:8090").replace(/\/+$/, "") + "/en/terms"))
routerAdd("GET", "/datenschutz", (c) => c.redirect(308, String($os.getenv("HYSE_PUBLIC_URL") || "http://localhost:8090").replace(/\/+$/, "") + "/de/datenschutz"))
routerAdd("GET", "/nutzungsbedingungen", (c) => c.redirect(308, String($os.getenv("HYSE_PUBLIC_URL") || "http://localhost:8090").replace(/\/+$/, "") + "/de/agb"))
routerAdd("GET", "/support", (c) => {
    let language = "en"
    try {
        const headers = $apis.requestInfo(c).headers || {}
        const cookie = String(headers.Cookie || headers.cookie || "")
        const saved = cookie.match(/(?:^|;\s*)hyse_language=(de|en)(?:;|$)/)
        if (saved) language = saved[1]
        else {
            const accepted = String(headers["Accept-Language"] || headers["accept-language"] || "").toLowerCase()
            if (accepted.split(",")[0].trim().startsWith("de")) language = "de"
        }
    } catch (_) {}
    return c.redirect(302, String($os.getenv("HYSE_PUBLIC_URL") || "http://localhost:8090").replace(/\/+$/, "") + "/" + language + "/support")
})

routerAdd("GET", "/marketing", (c) => {
    let language = "en"
    try {
        const headers = $apis.requestInfo(c).headers || {}
        const cookie = String(headers.Cookie || headers.cookie || "")
        const saved = cookie.match(/(?:^|;\s*)hyse_language=(de|en)(?:;|$)/)
        if (saved) language = saved[1]
        else {
            const accepted = String(headers["Accept-Language"] || headers["accept-language"] || "").toLowerCase()
            if (accepted.split(",")[0].trim().startsWith("de")) language = "de"
        }
    } catch (_) {}
    return c.redirect(302, String($os.getenv("HYSE_PUBLIC_URL") || "http://localhost:8090").replace(/\/+$/, "") + "/" + language + "/marketing")
})
