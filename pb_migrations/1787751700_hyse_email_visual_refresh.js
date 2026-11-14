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
      .hyse-page, .hyse-shell { background:#171b1c !important; }
      .hyse-card { background:#202526 !important; border-color:#394041 !important; }
      .hyse-brand { background:#15191a !important; border-color:#394041 !important; }
      .hyse-title, .hyse-copy-strong { color:#f4f7f7 !important; }
      .hyse-copy, .hyse-muted { color:#aeb7b7 !important; }
      .hyse-link-panel { background:#181d1e !important; border-color:#394041 !important; }
      .hyse-link { color:#67d0cf !important; }
      .hyse-rule { background:#394041 !important; }
    }
    @media only screen and (max-width:620px) {
      .hyse-shell { padding:14px 10px !important; }
      .hyse-content { padding-left:22px !important; padding-right:22px !important; }
      .hyse-title { font-size:27px !important; line-height:1.16 !important; }
      .hyse-button-cell, .hyse-button { display:block !important; width:100% !important; box-sizing:border-box !important; text-align:center !important; }
      .hyse-brand-copy { padding-left:10px !important; }
    }
  </style>
</head>
<body class="hyse-page" style="margin:0;padding:0;background:#eef1f1;color:#171b1c;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text','Segoe UI',Roboto,Helvetica,Arial,sans-serif;-webkit-text-size-adjust:100%;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;mso-hide:all;">${options.preheader}&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;</div>
  <table class="hyse-shell" role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;background:#eef1f1;">
    <tr><td align="center" style="padding:36px 12px;">
      <table class="hyse-card" role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;max-width:590px;background:#ffffff;border:1px solid #dce2e2;border-radius:22px;overflow:hidden;">
        <tr><td style="height:5px;background:#0e8c8c;font-size:0;line-height:0;">&nbsp;</td></tr>
        <tr><td class="hyse-brand hyse-content" style="padding:23px 30px;background:#171b1c;border-bottom:1px solid #2d3334;">
          <table role="presentation" cellspacing="0" cellpadding="0" border="0"><tr>
            <td width="42" height="42" align="center" valign="middle" style="width:42px;height:42px;border-radius:12px;background:#0e8c8c;color:#ffffff;font-size:19px;line-height:42px;font-weight:800;">H</td>
            <td class="hyse-brand-copy" style="padding-left:12px;">
              <div style="font-size:20px;line-height:1.15;font-weight:800;letter-spacing:-.3px;color:#ffffff;">Hyse</div>
              <div style="margin-top:3px;font-size:12px;line-height:1.35;color:#aeb7b7;">Nutrition · Training · Health</div>
            </td>
          </tr></table>
        </td></tr>
        <tr><td class="hyse-content" style="padding:34px 32px 15px;">
          <div style="font-size:11px;line-height:1.4;font-weight:800;letter-spacing:1.35px;text-transform:uppercase;color:#0e8c8c;">${options.eyebrow}</div>
          <h1 class="hyse-title" style="margin:9px 0 13px;font-size:31px;line-height:1.16;letter-spacing:-.7px;color:#171b1c;">${options.title}</h1>
          <p class="hyse-copy" style="margin:0;font-size:16px;line-height:1.65;color:#596364;">${options.message}</p>
        </td></tr>
        <tr><td class="hyse-content" style="padding:13px 32px 25px;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0"><tr>
            <td class="hyse-button-cell" align="center" style="border-radius:14px;background:#0e8c8c;">
              <a class="hyse-button" href="{ACTION_URL}" style="display:block;padding:15px 22px;border-radius:14px;color:#ffffff;text-decoration:none;font-size:16px;line-height:1.25;font-weight:750;">${options.button}</a>
            </td>
          </tr></table>
        </td></tr>
        <tr><td class="hyse-content" style="padding:0 32px 32px;">
          <table class="hyse-link-panel" role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="width:100%;background:#f5f7f7;border:1px solid #e1e6e6;border-radius:14px;">
            <tr><td style="padding:15px 16px;">
              <div class="hyse-copy-strong" style="margin-bottom:5px;font-size:12px;line-height:1.4;font-weight:750;color:#2c3334;">Button not working?</div>
              <div class="hyse-muted" style="margin-bottom:7px;font-size:12px;line-height:1.5;color:#70797a;">Copy this secure link into your browser:</div>
              <div style="word-break:break-all;font-size:11px;line-height:1.55;"><a class="hyse-link" href="{ACTION_URL}" style="color:#087272;text-decoration:underline;">{ACTION_URL}</a></div>
            </td></tr>
          </table>
          <div class="hyse-rule" style="height:1px;background:#e1e6e6;margin:25px 0 18px;"></div>
          <p class="hyse-muted" style="margin:0;font-size:13px;line-height:1.58;color:#70797a;">${options.note}</p>
        </td></tr>
      </table>
      <p class="hyse-muted" style="max-width:590px;margin:17px auto 0;font-size:12px;line-height:1.6;color:#70797a;">Sent securely by Hyse&nbsp;&nbsp;·&nbsp;&nbsp;<a class="hyse-link" href="https://hyse.minipliy.net" style="color:#087272;text-decoration:none;">Website</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a class="hyse-link" href="mailto:hyse@minipliy.net" style="color:#087272;text-decoration:none;">Support</a>&nbsp;&nbsp;·&nbsp;&nbsp;<a class="hyse-link" href="https://hyse.minipliy.net/privacy" style="color:#087272;text-decoration:none;">Privacy</a></p>
    </td></tr>
  </table>
</body>
</html>`

  settings.meta.senderName = "Hyse"
  settings.meta.verificationTemplate.subject = "Verify your email for Hyse"
  settings.meta.verificationTemplate.body = layout({
    preheader: "One quick step to finish setting up your Hyse account.",
    eyebrow: "Account setup",
    title: "Verify your email",
    message: "Confirm this email address to activate your account and securely sync your nutrition, training and health data.",
    button: "Verify email address",
    note: "You received this email because a Hyse account was created with this address. If that was not you, you can safely ignore this message."
  })
  settings.meta.resetPasswordTemplate.subject = "Reset your Hyse password"
  settings.meta.resetPasswordTemplate.body = layout({
    preheader: "Use the secure Hyse link to choose a new password.",
    eyebrow: "Account security",
    title: "Reset your password",
    message: "A password reset was requested for your Hyse account. Continue with the secure link below to choose a new password.",
    button: "Choose new password",
    note: "If you did not request this reset, ignore this message. Your current password remains unchanged."
  })
  settings.meta.confirmEmailChangeTemplate.subject = "Confirm your new Hyse email address"
  settings.meta.confirmEmailChangeTemplate.body = layout({
    preheader: "Confirm the new email address for your Hyse account.",
    eyebrow: "Account security",
    title: "Confirm your new email",
    message: "Use the secure link below to finish changing the email address connected to your Hyse account.",
    button: "Confirm email address",
    note: "If you did not request this change, do not open the link and contact Hyse support."
  })

  dao.saveSettings(settings)
}, (db) => {
  const dao = new Dao(db)
  const settings = dao.findSettings()
  settings.meta.senderName = "Hyse"
  dao.saveSettings(settings)
})
