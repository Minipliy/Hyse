#!/usr/bin/env ruby
require_relative "training_view_sources"

def assert(condition, message)
  raise message unless condition
end

hook = File.read("pb_hooks/training_social.pb.js")
migration = File.read("pb_migrations/1787751500_training_social.js")
interaction_migration = File.read("pb_migrations/1787751800_training_social_interactions.js")
reply_migration = File.read("pb_migrations/1791001200_workout_comment_replies.js")
views = TrainingViewSources.read
service = File.read("CalorieTrackerApp/TrainingSocialService.swift")
training_store = File.read("CalorieTrackerApp/TrainingStore.swift")

routes = %w[profile username nickname search users connections request accept remove feed]
routes.each do |route|
  assert(hook.include?("/api/hyse/social/#{route}"), "Missing social route: #{route}")
end

assert(!hook.match?(/function\s+hyseSocial|\bhyseSocial[A-Z]/), "Social routes must not depend on module-level helpers in PocketBase 0.22")
route_count = hook.scan('routerAdd(').length
assert(hook.scan('$apis.requestInfo(c)').length == route_count, "Every social route must resolve its own request context")
assert(hook.scan('$apis.requireRecordAuth("users")').length == route_count - 1, "Only the public shared-workout route may omit user authentication")
assert(migration.include?("training_friendships"), "Missing private friendship collection")
assert(migration.include?("idx_training_friendships_pair"), "Missing unique friendship-pair index")
assert(migration.include?("listRule: null") && migration.include?("createRule: null"), "Friendships must remain inaccessible through public collection rules")
assert(hook.include?('/api/hyse/social/workouts/:id/like'), "Missing workout like route")
assert(hook.include?('/api/hyse/social/workouts/:id/comments'), "Missing workout comment route")
assert(hook.include?('/api/hyse/social/workouts/:id'), "Missing friend workout detail route")
assert(hook.include?('client_id = {:clientID}') && hook.include?('(!user || ownerID !== user.id)'), "Shared workout links must resolve public workouts without an account")
assert(hook.include?('avatar_url'), "Social responses must include a reliable avatar URL")
assert(hook.include?('"/api/hyse/social/nickname"') && hook.include?('nickname: String('),
       "Profiles must persist and return an optional display nickname")
assert(hook.include?('username ~ {:query}'), "Friend search must continue to use usernames")
assert(service.include?('var displayName: String') && service.include?('func updateNickname'),
       "The app must render nicknames while retaining usernames for friend search")
assert(interaction_migration.include?('training_workout_likes'), "Missing workout likes collection")
assert(interaction_migration.include?('training_workout_comments'), "Missing workout comments collection")
assert(interaction_migration.include?('idx_training_workout_likes_unique'), "Likes must be unique per user and workout")
assert(reply_migration.include?('name: "reply_to", type: "relation"') && reply_migration.include?('collectionId: comments.id'),
       "Workout replies must reference a comment in their own collection")
assert(hook.include?('String(replied.get("workout")) !== workoutID'),
       "A workout reply must reject comments from other workouts")
assert(hook.include?('reply_to: replyToID') && service.include?('replyToID: String? = nil'),
       "The reply target must round-trip through the API and app")
assert(views.include?('orderedWorkoutCommentRows(comments)') && views.include?('training.social.replying_to'),
       "Workout comments must display reply threads and the active reply target")
assert(views.include?('TrainingConnectionsListView(kind: .friends'), "Training profile friends count must open the friends list")
assert(views.include?('TrainingConnectionsListView(kind: .followers'), "Training profile followers count must open the followers list")
assert(views.include?('RemoteProfileAvatarView('), "Connection lists must show profile avatars")
assert(views.include?('friendPendingRemoval = friend'), "Removing a friend must first stage a confirmation")
assert(views.include?('training.social.remove_friend_title'), "Friend removal must show a confirmation alert")
assert(views.include?('role: .destructive) { confirmFriendRemoval() }'), "Only the confirmed destructive action may remove a friend")
assert(service.include?('if let currentIndex = feed.firstIndex(where: { $0.id == workoutID })'), "Like responses must resolve the current feed index after awaiting the server")
assert(!service.match?(/lastNetworkLoadAt = Date\(\).*let hasVisibleCache/m), "A failed social request must not start the freshness window")
assert(service.include?('isCancellationError(error)') && service.include?('NSURLErrorCancelled'),
       "Cancelled pull-to-refresh requests must not be shown as friend failures")
assert(service.include?('func removeFromFeed(workoutID: UUID, remoteFeedID: String?, accountID: String)') &&
       service.include?('locallyDeletedWorkoutIDs'),
       "Deleting an own workout must remove it from the friends feed and its cache")
assert(views.include?('remoteFeedID: workoutPendingSocialFeedID'),
       "Own feed deletion must use the remote feed workout ID")
assert(training_store.include?('sync(force: true)') && training_store.include?('deleted workout must disappear from the social feed'),
       "Deleted workouts must sync immediately so the social feed cannot restore them")
assert(service.include?('fractionalFormatter.date(from: created)'), "PocketBase comment timestamps with fractional seconds must remain readable")
assert(service.include?('workoutDetails = [:]') && service.include?('loadedAccountID = nil'), "Logout must clear account-scoped social details")

puts "Training social regression tests passed (#{route_count - 1} authenticated routes plus public shared workouts)."
