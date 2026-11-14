#!/usr/bin/env ruby
require_relative "training_view_sources"

def assert(condition, message)
  abort("FAILED: #{message}") unless condition
end

service = File.read("CalorieTrackerApp/TrainingSocialService.swift")
views = TrainingViewSources.read
push = File.read("CalorieTrackerApp/CommunityPushNotificationManager.swift")
hook = File.read("pb_hooks/gym_communities.pb.js")
migration = File.read("pb_migrations/1788700400_gym_community_notifications.js")
notification_center = File.read("CalorieTrackerApp/HyseNotificationCenter.swift")
content = File.read("CalorieTrackerApp/ContentView.swift")
notification_hook = File.read("pb_hooks/notifications.pb.js")
social_hook = File.read("pb_hooks/training_social.pb.js")

assert(service.include?("news_notifications_enabled"), "community responses must carry the per-community preference")
assert(service.include?("setNewsNotifications"), "the app must persist bell changes on the server")
assert(views.include?("private func joinCommunity()") && views.include?("communityNews: true") &&
       views.include?("setNewsNotifications(true, for: community"),
       "Joining a community must enable its news bell by default")
assert(views.include?("friendActivity: true") && views.include?("workoutLikes: true") && views.include?("workoutComments: true"),
       "Accepting a friend must enable workout, like, and comment notifications")
assert(views.include?("bell.fill") && views.include?("bell.slash"), "community details must expose an on/off bell")
assert(push.include?("registerForRemoteNotifications"), "enabled notifications must register with APNs")
assert(push.include?("/api/hyse/push-devices"), "APNs tokens must be registered securely with Hyse")
assert(migration.include?("push_devices") && migration.include?("news_notifications_enabled"), "the database must store devices and subscriptions")
assert(hook.include?("channel === \"news\""), "only news posts should trigger these notifications")
assert(hook.include?("user != {:author}"), "authors must not receive their own news push")
assert(notification_center.include?("HyseNotificationCenterStore") && notification_center.include?("unreadCount"), "the app needs an unread notification center")
assert(content.include?("HyseNotificationCenterView()\n                .environmentObject(language)\n                .environmentObject(authManager)\n                .environmentObject(notificationCenter)"), "the home notification sheet must receive its required stores")
assert(notification_hook.include?("/api/hyse/notifications/read-all"), "the server must support marking all notifications as read")
assert(social_hook.include?('type", "workout_like"') && social_hook.include?('type", "workout_comment"'), "likes and comments must create notification-center events")
assert(social_hook.include?('type", "friend_request"') && social_hook.include?('type", "friend_accepted"'), "friend requests and acceptances must create events")

puts "Gym Community notification regression checks passed."
