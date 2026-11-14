migrate((db) => {
  const dao = new Dao(db)
  const settings = dao.findSettings()

  const layout = (eyebrow, title, message, button, footerNote) => `
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${title}</title>
</head>
<body style="margin:0;padding:0;background:#eef5f3;color:#153735;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;">${message}</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:#eef5f3;">
    <tr><td align="center" style="padding:28px 12px;">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:600px;background:#ffffff;border-radius:24px;overflow:hidden;box-shadow:0 12px 32px rgba(9,54,50,.10);">
        <tr><td style="padding:30px 32px;background:#0d7068;color:#ffffff;">
          <div style="font-size:30px;font-weight:800;letter-spacing:-.8px;">Hyse</div>
          <div style="margin-top:6px;font-size:14px;line-height:1.5;color:#d9fffa;">Nutrition made clear.</div>
        </td></tr>
        <tr><td style="padding:34px 32px 18px;">
          <div style="font-size:12px;font-weight:800;letter-spacing:1.3px;text-transform:uppercase;color:#0d7068;">${eyebrow}</div>
          <h1 style="margin:10px 0 14px;font-size:28px;line-height:1.22;letter-spacing:-.5px;color:#153735;">${title}</h1>
          <p style="margin:0;font-size:16px;line-height:1.65;color:#496663;">${message}</p>
        </td></tr>
        <tr><td style="padding:10px 32px 26px;">
          <table role="presentation" cellspacing="0" cellpadding="0" border="0"><tr><td style="border-radius:12px;background:#0d7068;">
            <a href="{ACTION_URL}" style="display:inline-block;padding:15px 23px;color:#ffffff;text-decoration:none;font-size:16px;font-weight:750;">${button}</a>
          </td></tr></table>
        </td></tr>
        <tr><td style="padding:0 32px 30px;">
          <p style="margin:0 0 10px;font-size:13px;line-height:1.55;color:#6d817f;">If the button does not work, copy and paste this link into your browser:</p>
          <p style="margin:0;word-break:break-all;font-size:12px;line-height:1.5;"><a href="{ACTION_URL}" style="color:#0d7068;">{ACTION_URL}</a></p>
          <div style="height:1px;background:#e3ecea;margin:26px 0 20px;"></div>
          <p style="margin:0;font-size:13px;line-height:1.55;color:#6d817f;">${footerNote}</p>
        </td></tr>
      </table>
      <p style="max-width:600px;margin:18px auto 0;font-size:12px;line-height:1.6;color:#66807d;">Sent by Hyse · <a href="https://hyse.minipliy.net" style="color:#386f6a;">hyse.minipliy.net</a> · <a href="mailto:hyse@minipliy.net" style="color:#386f6a;">Support</a></p>
    </td></tr>
  </table>
</body>
</html>`

  settings.meta.senderName = "Hyse"
  settings.meta.verificationTemplate.subject = "Verify your email for Hyse"
  settings.meta.verificationTemplate.body = layout(
    "Email verification",
    "Welcome to Hyse",
    "Confirm your email address to finish setting up your account and securely sync your foods and nutrition data.",
    "Verify email",
    "You received this email because a Hyse account was created with this address. If that was not you, you can safely ignore it."
  )
  settings.meta.resetPasswordTemplate.subject = "Reset your Hyse password"
  settings.meta.resetPasswordTemplate.body = layout(
    "Password reset",
    "Choose a new password",
    "We received a request to reset the password for your Hyse account. Use the secure link below to continue.",
    "Reset password",
    "If you did not request a password reset, ignore this message. Your current password will remain unchanged."
  )
  settings.meta.confirmEmailChangeTemplate.subject = "Confirm your new Hyse email address"
  settings.meta.confirmEmailChangeTemplate.body = layout(
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
  settings.meta.verificationTemplate.subject = "Verify your Hyse email"
  settings.meta.verificationTemplate.body = "<p>Verify your email by clicking the link below.</p><p><a href=\"{ACTION_URL}\">Verify email</a></p>"
  settings.meta.resetPasswordTemplate.subject = "Reset your Hyse password"
  settings.meta.resetPasswordTemplate.body = "<p>Reset your password by clicking the link below.</p><p><a href=\"{ACTION_URL}\">Reset password</a></p>"
  settings.meta.confirmEmailChangeTemplate.subject = "Confirm your Hyse email change"
  settings.meta.confirmEmailChangeTemplate.body = "<p>Confirm your new email by clicking the link below.</p><p><a href=\"{ACTION_URL}\">Confirm email</a></p>"
  dao.saveSettings(settings)
})
