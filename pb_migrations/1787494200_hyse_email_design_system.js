migrate((db) => {
  const dao = new Dao(db)
  const settings = dao.findSettings()

  const layout = (preheader, eyebrow, title, message, button, footerNote) => `
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="color-scheme" content="light dark">
  <meta name="supported-color-schemes" content="light dark">
  <title>${title}</title>
  <style>
    :root { color-scheme: light dark; supported-color-schemes: light dark; }
    @media (prefers-color-scheme: dark) {
      .hyse-page { background:#000000 !important; }
      .hyse-card { background:#1c1c1e !important; border-color:#38383a !important; }
      .hyse-title { color:#f5f5f7 !important; }
      .hyse-copy, .hyse-muted { color:#a1a1a6 !important; }
      .hyse-rule { background:#38383a !important; }
      .hyse-link { color:#55caca !important; }
    }
    @media only screen and (max-width:620px) {
      .hyse-shell { padding:16px 12px !important; }
      .hyse-content { padding-left:20px !important; padding-right:20px !important; }
      .hyse-title { font-size:26px !important; }
      .hyse-button-cell, .hyse-button { display:block !important; width:100% !important; box-sizing:border-box !important; text-align:center !important; }
    }
  </style>
</head>
<body class="hyse-page" style="margin:0;padding:0;background:#f2f2f7;color:#111114;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">${preheader}</div>
  <table class="hyse-page" role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;background:#f2f2f7;">
    <tr><td class="hyse-shell" align="center" style="padding:32px 12px;">
      <table class="hyse-card" role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;max-width:600px;background:#ffffff;border:1px solid rgba(17,17,20,.10);border-radius:24px;overflow:hidden;box-shadow:0 16px 44px rgba(0,0,0,.10);">
        <tr><td class="hyse-content" style="padding:28px 32px 18px;">
          <table role="presentation" cellspacing="0" cellpadding="0" border="0"><tr>
            <td width="44" height="44" align="center" valign="middle" style="width:44px;height:44px;border-radius:10px;background:#0e8c8c;color:#ffffff;font-size:20px;font-weight:800;">H</td>
            <td style="padding-left:12px;color:#111114;"><span class="hyse-title" style="font-size:21px;line-height:1.2;font-weight:800;letter-spacing:-.3px;color:#111114;">Hyse</span><br><span class="hyse-muted" style="font-size:13px;line-height:1.4;color:#6e6e73;">Nutrition made clear.</span></td>
          </tr></table>
        </td></tr>
        <tr><td class="hyse-content" style="padding:18px 32px 16px;">
          <div style="font-size:12px;line-height:1.4;font-weight:800;letter-spacing:1.2px;text-transform:uppercase;color:#087070;">${eyebrow}</div>
          <h1 class="hyse-title" style="margin:10px 0 14px;font-size:30px;line-height:1.18;letter-spacing:-.6px;color:#111114;">${title}</h1>
          <p class="hyse-copy" style="margin:0;font-size:16px;line-height:1.65;color:#6e6e73;">${message}</p>
        </td></tr>
        <tr><td class="hyse-content" style="padding:10px 32px 26px;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"><tr><td class="hyse-button-cell" align="center" style="border-radius:14px;background:#0e8c8c;">
            <a class="hyse-button" href="{ACTION_URL}" style="display:block;padding:15px 22px;border-radius:14px;color:#ffffff;text-decoration:none;font-size:16px;line-height:1.25;font-weight:700;">${button}</a>
          </td></tr></table>
        </td></tr>
        <tr><td class="hyse-content" style="padding:0 32px 30px;">
          <p class="hyse-muted" style="margin:0 0 9px;font-size:13px;line-height:1.55;color:#6e6e73;">If the button does not work, copy and paste this secure link into your browser:</p>
          <p style="margin:0;word-break:break-all;font-size:12px;line-height:1.55;"><a class="hyse-link" href="{ACTION_URL}" style="color:#087070;">{ACTION_URL}</a></p>
          <div class="hyse-rule" style="height:1px;background:rgba(17,17,20,.10);margin:26px 0 20px;"></div>
          <p class="hyse-muted" style="margin:0;font-size:13px;line-height:1.55;color:#6e6e73;">${footerNote}</p>
        </td></tr>
      </table>
      <p class="hyse-muted" style="max-width:600px;margin:18px auto 0;font-size:12px;line-height:1.6;color:#6e6e73;">Sent by Hyse · <a class="hyse-link" href="https://hyse.minipliy.net" style="color:#087070;">Website</a> · <a class="hyse-link" href="mailto:hyse@minipliy.net" style="color:#087070;">Support</a> · <a class="hyse-link" href="https://hyse.minipliy.net/privacy" style="color:#087070;">Privacy</a></p>
    </td></tr>
  </table>
</body>
</html>`

  settings.meta.senderName = "Hyse"
  settings.meta.verificationTemplate.subject = "Verify your email for Hyse"
  settings.meta.verificationTemplate.body = layout(
    "Verify your email address to finish setting up Hyse.",
    "Email verification",
    "Welcome to Hyse",
    "Confirm your email address to finish setting up your account and securely sync your foods and nutrition data.",
    "Verify email",
    "You received this email because a Hyse account was created with this address. If that was not you, you can safely ignore it."
  )
  settings.meta.resetPasswordTemplate.subject = "Reset your Hyse password"
  settings.meta.resetPasswordTemplate.body = layout(
    "Use this secure link to reset your Hyse password.",
    "Password reset",
    "Choose a new password",
    "We received a request to reset the password for your Hyse account. Use the secure link below to continue.",
    "Reset password",
    "If you did not request a password reset, ignore this message. Your current password will remain unchanged."
  )
  settings.meta.confirmEmailChangeTemplate.subject = "Confirm your new Hyse email address"
  settings.meta.confirmEmailChangeTemplate.body = layout(
    "Confirm the new email address for your Hyse account.",
    "Email change",
    "Confirm your email address",
    "Confirm this address to complete the email change for your Hyse account.",
    "Confirm email address",
    "If you did not request this change, do not use the link and contact Hyse support."
  )

  dao.saveSettings(settings)
}, (db) => {
  const dao = new Dao(db)
  const settings = dao.findSettings()
  settings.meta.senderName = "Hyse"
  dao.saveSettings(settings)
})
