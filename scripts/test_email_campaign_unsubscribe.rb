#!/usr/bin/env ruby

def assert(value, message)
  raise message unless value
end

hook = File.read("pb_hooks/email_campaigns.pb.js")
migration = File.read("pb_migrations/1790400000_hyse_email_unsubscribe.js")
account = File.read("CalorieTrackerApp/AccountDataStore.swift")
content = File.read("CalorieTrackerApp/ContentView.swift")
legal = File.read("CalorieTrackerApp/LegalAndOnboardingViews.swift")
studio = File.read("hyse-updates-site/dist/index.html")

assert(hook.scan('!state || !state.getBool("marketing_consent")').length == 3,
       "Every email-campaign audience must require explicit marketing consent")
assert(hook.include?('send && category !== "update"') &&
       hook.include?('promo: 0, motivation: 0'),
       "Promotions and standalone motivation must not be sent under the product-news consent")
assert(!hook.include?('if (preferences && !preferences.getBool("hyse_updates"))'),
       "Email eligibility must not default to enabled when notification preferences are missing")
assert(hook.include?('"/api/hyse/email/unsubscribe/:token"'), "Public unsubscribe route is missing")
assert(hook.include?('$security.randomString(48)') && hook.include?('$security.sha256(rawToken)'),
       "Unsubscribe links must use opaque tokens stored only as hashes")
assert(hook.include?('state.set("marketing_consent", false)'),
       "Unsubscribe must disable the in-app marketing preference")
assert(hook.include?('receipt.set("source", "email_unsubscribe")'),
       "Unsubscribe must create an auditable revocation receipt")
assert(hook.include?("E-Mails abbestellen"), "Campaign emails must include an unsubscribe button")
assert(migration.include?('name: "hyse_email_unsubscribe_tokens"') && migration.include?("cascadeDelete: true"),
       "Unsubscribe tokens must have private, account-owned storage")
assert(legal.include?("marketingAccepted = true"), "Accept all must opt in to product emails")
assert(account.include?("guest.marketingUpdatedAt") && account.include?("remoteMarketingDate"),
       "Marketing consent must merge by timestamp between guest, account, and server")
assert(content.include?("accountData.refreshAccountState"),
       "Returning to the app must refresh an email unsubscribe")
assert(studio.include?('class="email-unsubscribe">E-Mails abbestellen') &&
       studio.include?("Produktneuigkeiten und hilfreiche Tipps"),
       "The campaign studio preview must show the unsubscribe control and exact consent audience")
assert(studio.include?('data-type="promo" disabled') && studio.include?('data-type="motivation" disabled'),
       "The campaign studio must visibly disable categories without matching consent")

puts "Email campaign consent and unsubscribe regression tests passed."
