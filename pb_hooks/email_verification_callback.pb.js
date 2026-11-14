/// <reference path="../pb_data/types.d.ts" />

// Force the final rendered message to use Hyse's callback. This extra guard is
// intentional: PocketBase's built-in template action URL can otherwise remain
// cached in an already loaded mailer configuration even after a migration.
onMailerBeforeRecordVerificationSend((e) => {
    if (!e.record || e.record.collection().name !== "users") return

    const token = String((e.meta || {}).token || "").trim()
    if (!token) return

    const actionURL = String($os.getenv("HYSE_PUBLIC_URL") || "http://localhost:8090").replace(/\/+$/, "") + "/api/hyse/verify-email/" + encodeURIComponent(token)
    const escapedToken = token.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    const tokenURL = new RegExp("https?://[^\\\"'<>\\s]*" + escapedToken, "g")
    e.message.html = String(e.message.html || "").replace(tokenURL, actionURL)
})

// The URL in a verification email is intentionally handled by the backend:
// the token is validated and consumed before the browser offers to open the
// app. This prevents the token from being passed into the custom URL scheme.
routerAdd("GET", "/api/hyse/verify-email/:token", (c) => {
    const token = String(c.pathParam("token") || "").trim()
    if (!token) throw new BadRequestError("The verification link is invalid.")

    const dao = $app.dao()
    let user = null
    try {
        user = dao.findAuthRecordByToken(token, $app.settings().recordVerificationToken.secret)
    } catch (_) {
        throw new BadRequestError("This verification link is invalid or has expired.")
    }

    if (!user || user.collection().name !== "users") {
        throw new BadRequestError("This verification link is invalid or has expired.")
    }

    // Match PocketBase's confirmation semantics. Re-opening a valid link is
    // harmless and always returns the user to the sign-in screen.
    if (!user.verified()) {
        user.setVerified(true)
        dao.saveRecord(user)
    }

    c.response().header().set(
        "Content-Security-Policy",
        "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src 'self'; base-uri 'none'; form-action 'none'"
    )
    return c.html(200, `<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="color-scheme" content="light dark">
  <title>E-Mail bestätigt · Hyse</title>
  <style>
    :root{color-scheme:light dark;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;background:#edf1f0;color:#17201f}
    *{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;padding:22px;background:#edf1f0}
    main{width:min(100%,520px);padding:34px;border:1px solid #d9e0de;border-radius:26px;background:#fff;text-align:center;box-shadow:0 18px 55px rgba(20,42,39,.12)}
    .mark{width:58px;height:58px;margin:0 auto 20px;display:grid;place-items:center;border-radius:18px;background:#0e8c82;color:#fff;font-size:30px;font-weight:800}
    h1{margin:0 0 12px;font-size:30px;letter-spacing:-.6px}p{margin:0 0 26px;color:#586462;line-height:1.6}
    a{display:block;padding:15px 20px;border-radius:14px;background:#0e8c82;color:#fff;text-decoration:none;font-weight:750}
    small{display:block;margin-top:17px;color:#73807d;line-height:1.5}
    @media(prefers-color-scheme:dark){:root,body{background:#111515;color:#f4f7f6}main{background:#1c2121;border-color:#343c3c}p,small{color:#adb7b5}}
  </style>
</head>
<body>
  <main>
    <div class="mark">✓</div>
    <h1>E-Mail-Adresse bestätigt</h1>
    <p>Dein Hyse-Konto ist aktiviert. Öffne jetzt die App und melde dich an.</p>
    <a id="open-app" href="hyseapp://login?verified=1">Hyse öffnen</a>
    <small>Falls die App nicht automatisch startet, tippe auf „Hyse öffnen“.</small>
  </main>
  <script>setTimeout(function(){location.href="hyseapp://login?verified=1"},250)</script>
</body>
</html>`)
})
