migrate((db) => {
  const dao = new Dao(db)
  const settings = dao.findSettings()

  const layout = (options) => `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="color-scheme" content="light dark">
  <meta name="supported-color-schemes" content="light dark">
  <title>${options.title}</title>
  <style>
    :root { color-scheme:light dark; supported-color-schemes:light dark; }
    @media (prefers-color-scheme:dark) {
      .hyse-page, .hyse-shell { background:#111515 !important; }
      .hyse-card { background:#1c2121 !important; border-color:#343c3c !important; }
      .hyse-header { background:#171c1c !important; border-color:#343c3c !important; }
      .hyse-title, .hyse-strong { color:#f4f7f6 !important; }
      .hyse-copy, .hyse-muted { color:#adb7b5 !important; }
      .hyse-panel { background:#151a1a !important; border-color:#343c3c !important; }
      .hyse-link { color:#69d4ca !important; }
      .hyse-rule { background:#343c3c !important; }
    }
    @media only screen and (max-width:620px) {
      .hyse-shell-cell { padding:18px 10px !important; }
      .hyse-content { padding-left:22px !important; padding-right:22px !important; }
      .hyse-title { font-size:28px !important; line-height:1.15 !important; }
      .hyse-button-cell, .hyse-button { display:block !important; width:100% !important; box-sizing:border-box !important; text-align:center !important; }
    }
  </style>
</head>
<body class="hyse-page" style="margin:0;padding:0;background:#edf1f0;color:#17201f;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Segoe UI',Roboto,Helvetica,Arial,sans-serif;-webkit-text-size-adjust:100%;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;mso-hide:all;">${options.preheader}&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;</div>
  <table class="hyse-shell" role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;background:#edf1f0;">
    <tr><td class="hyse-shell-cell" align="center" style="padding:38px 12px;">
      <table class="hyse-card" role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;max-width:600px;background:#ffffff;border:1px solid #d9e0de;border-radius:26px;overflow:hidden;">
        <tr><td class="hyse-header hyse-content" style="padding:22px 30px;background:#17201f;border-bottom:1px solid #303938;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"><tr>
            <td valign="middle">
              <table role="presentation" cellspacing="0" cellpadding="0" border="0"><tr>
                <td width="40" height="40" align="center" valign="middle" style="width:40px;height:40px;border-radius:12px;background:#19a99b;color:#ffffff;font-size:18px;line-height:40px;font-weight:800;">H</td>
                <td style="padding-left:12px;color:#ffffff;font-size:20px;line-height:1.2;font-weight:800;letter-spacing:-.35px;">Hyse</td>
              </tr></table>
            </td>
            <td align="right" valign="middle"><span style="display:inline-block;padding:7px 10px;border:1px solid #42504e;border-radius:999px;color:#cbd5d3;font-size:10px;line-height:1;font-weight:800;letter-spacing:1px;text-transform:uppercase;">${options.badge}</span></td>
          </tr></table>
        </td></tr>
        <tr><td class="hyse-content" style="padding:37px 32px 16px;">
          <div style="font-size:11px;line-height:1.4;font-weight:800;letter-spacing:1.4px;text-transform:uppercase;color:#0e857b;">${options.eyebrow}</div>
          <h1 class="hyse-title" style="margin:9px 0 14px;font-size:32px;line-height:1.15;letter-spacing:-.8px;color:#17201f;">${options.title}</h1>
          <p class="hyse-copy" style="margin:0;font-size:16px;line-height:1.65;color:#586462;">${options.message}</p>
        </td></tr>
        <tr><td class="hyse-content" style="padding:14px 32px 24px;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"><tr>
            <td class="hyse-button-cell" align="center" style="border-radius:14px;background:#0e8c82;">
              <a class="hyse-button" href="{ACTION_URL}" style="display:block;padding:15px 22px;border-radius:14px;color:#ffffff;text-decoration:none;font-size:16px;line-height:1.25;font-weight:750;">${options.button}</a>
            </td>
          </tr></table>
        </td></tr>
        <tr><td class="hyse-content" style="padding:0 32px 30px;">
          <table class="hyse-panel" role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;background:#f3f6f5;border:1px solid #dfe6e4;border-radius:15px;">
            <tr><td style="padding:16px 17px;">
              <div class="hyse-strong" style="margin-bottom:5px;font-size:13px;line-height:1.4;font-weight:800;color:#27312f;">${options.detailTitle}</div>
              <div class="hyse-muted" style="font-size:13px;line-height:1.55;color:#687371;">${options.detail}</div>
            </td></tr>
          </table>
          <p class="hyse-muted" style="margin:18px 0 7px;font-size:12px;line-height:1.55;color:#73807d;">If the button does not open, copy this link into your browser:</p>
          <div style="word-break:break-all;font-size:11px;line-height:1.55;"><a class="hyse-link" href="{ACTION_URL}" style="color:#08766e;text-decoration:underline;">{ACTION_URL}</a></div>
          <div class="hyse-rule" style="height:1px;background:#e1e7e5;margin:24px 0 18px;"></div>
          <p class="hyse-muted" style="margin:0;font-size:13px;line-height:1.58;color:#687371;">${options.note}</p>
        </td></tr>
      </table>
      <p class="hyse-muted" style="max-width:600px;margin:17px auto 0;font-size:12px;line-height:1.65;color:#687371;">Hyse · Nutrition, training and health<br><a class="hyse-link" href="https://hyse.minipliy.net" style="color:#08766e;text-decoration:none;">Website</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a class="hyse-link" href="mailto:hyse@minipliy.net" style="color:#08766e;text-decoration:none;">Support</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a class="hyse-link" href="https://hyse.minipliy.net/privacy" style="color:#08766e;text-decoration:none;">Privacy</a></p>
    </td></tr>
  </table>
</body>
</html>`

  settings.meta.senderName = "Hyse"
  settings.meta.verificationTemplate.subject = "Verify your email · Hyse"
  settings.meta.verificationTemplate.body = layout({
    preheader: "Confirm your address and finish setting up your Hyse account.",
    badge: "Welcome",
    eyebrow: "Email verification",
    title: "One step to get started",
    message: "Verify this email address to activate your Hyse account and securely sync your nutrition, training and health data.",
    button: "Verify email address",
    detailTitle: "After verification",
    detail: "Return to Hyse and sign in. Your account will be ready across your devices.",
    note: "You received this because a Hyse account was created with this address. If that was not you, you can safely ignore this email."
  })
  settings.meta.resetPasswordTemplate.subject = "Reset your password · Hyse"
  settings.meta.resetPasswordTemplate.body = layout({
    preheader: "Use the secure link to choose a new Hyse password.",
    badge: "Security",
    eyebrow: "Password reset",
    title: "Choose a new password",
    message: "A password reset was requested for your Hyse account. Continue below to create a new password.",
    button: "Reset password",
    detailTitle: "Your account stays protected",
    detail: "Your current password remains active until you complete the reset through this secure link.",
    note: "Did not request this? Ignore the email. No password will be changed, and you do not need to take any further action."
  })
  settings.meta.confirmEmailChangeTemplate.subject = "Confirm your new email · Hyse"
  settings.meta.confirmEmailChangeTemplate.body = layout({
    preheader: "Confirm the new email address connected to your Hyse account.",
    badge: "Security",
    eyebrow: "Email change",
    title: "Confirm your new email",
    message: "Use the secure link below to finish changing the email address connected to your Hyse account.",
    button: "Confirm new email",
    detailTitle: "This only changes your sign-in address",
    detail: "Your Hyse profile and synced nutrition, training and health data remain unchanged.",
    note: "Did not request this change? Do not open the link and contact Hyse support so your account can be secured."
  })

  dao.saveSettings(settings)
}, (db) => {
  const dao = new Dao(db)
  const settings = dao.findSettings()
  settings.meta.senderName = "Hyse"
  dao.saveSettings(settings)
})
