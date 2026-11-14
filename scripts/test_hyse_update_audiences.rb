#!/usr/bin/env ruby

def assert(value, message)
  raise message unless value
end

delivery = File.read("pb_hooks/hyse_update_push_helpers.js")
notifications = File.read("pb_hooks/notifications.pb.js")
migration = File.read("pb_migrations/1790300000_hyse_update_audiences.js")
studio = File.read("hyse-update-studio/dist/index.html")
content = File.read("CalorieTrackerApp/ContentView.swift")

assert(delivery.include?("function matchesAudience"), "Updates must match recipients to their selected area")
assert(delivery.include?("interest === \"both\" || interest === audience"), "People using both areas must receive both targeted update types")
assert(delivery.include?("function createNotificationCenterEntries"), "Publishing must create notification-center entries immediately")
assert(delivery.include?("function deliverHyseUpdate"), "Publishing must use the notification-center delivery path")
assert(delivery.include?("pushDeviceCount: 0") && !delivery.include?("/send"), "Hyse updates must not send push banners")
assert(notifications.include?("hyseUpdateDelivery.deliverHyseUpdate("), "New, scheduled, and promoted updates must trigger delivery")
assert(notifications.include?("matchesAudience(dao, update, user.id)"), "Notification-center updates must respect the update audience")
assert(notifications.include?("return c.json(200, { update: null })"), "Older apps must not receive update popups")
assert(migration.include?("values: [\"all\", \"training\", \"nutrition\"]"), "The update schema must persist all three audiences")
assert(studio.include?("value=\"training\"") && studio.include?("value=\"nutrition\""), "The editor must expose training and nutrition audiences")
assert(studio.include?("show_popup:false,show_notification_center:true") && !studio.include?("popupToggle"), "The editor must publish to the notification center only")
assert(!content.include?("HyseUpdatePopupView") && !content.include?("updatePopup.load"), "The app must not present update popups")

puts "Hyse update audience regression checks passed."
