#!/usr/bin/env ruby
require_relative "training_view_sources"

def assert(value, message)
  raise message unless value
end

hook = File.read("pb_hooks/gym_communities.pb.js")
repair = File.read("pb_migrations/1788700000_repair_gym_communities.js")
interactions = File.read("pb_migrations/1788700100_gym_community_post_interactions.js")
replies = File.read("pb_migrations/1788700300_gym_community_post_replies.js")
reply_repair = File.read("pb_migrations/1788700310_repair_gym_community_post_replies.js")
images = File.read("pb_migrations/1788700550_gym_community_images.js")
service = File.read("CalorieTrackerApp/TrainingSocialService.swift")
views = TrainingViewSources.read

assert(hook.scan('routerAdd(').length == 13, "All thirteen authenticated community and push routes must exist")
assert(hook.include?(': "id != \'\'"') && !hook.include?(': ""\n    const records = dao.findRecordsByFilter("gym_communities"'),
       "Listing all communities must use a valid non-empty PocketBase filter")
%w[gym_communities gym_community_members gym_community_posts].each do |collection|
  assert(repair.include?(%Q{find("#{collection}")}), "Repair must detect a missing #{collection} collection")
  assert(repair.include?(%Q{name: "#{collection}"}), "Repair must recreate #{collection}")
end
assert(repair.include?('listRule: null') && repair.include?('createRule: null'),
       "Repaired community collections must remain inaccessible through public collection APIs")
assert(service.include?('statusCode >= 500') && service.include?('"training.community.error"'),
       "Internal PocketBase errors must use the localized community message")
assert(service.include?('isCancellationError(error)') && service.include?('URLError') && service.include?('NSURLErrorCancelled') && service.include?('NSUnderlyingErrorKey'),
       "Cancelled pull-to-refresh requests must not be shown as community failures")
assert(interactions.include?('gym_community_post_reactions') && interactions.include?('idx_gym_post_reactions_unique'),
       "Community post reactions must have a private, unique schema")
assert(replies.include?('reply_to') && replies.include?('idx_gym_community_posts_reply'),
       "Community replies must persist their quoted post relation")
assert(reply_repair.include?('if (!field)') && reply_repair.include?('idx_gym_community_posts_reply'),
       "Community reply schema must repair PocketBase versions that return a missing field as null")
assert(hook.include?('"PATCH", "/api/hyse/gym-community-posts/:id"'),
       "Authors need an authenticated post-edit route")
assert(hook.include?('"DELETE", "/api/hyse/gym-community-posts/:id"'),
       "Authors and community moderators need an authenticated post-delete route")
assert(hook.include?('"POST", "/api/hyse/gym-community-posts/:id/reactions"'),
       "Members need an authenticated reaction-toggle route")
assert(hook.include?('"DELETE", "/api/hyse/gym-communities/:id"') && hook.include?('Only the community owner can delete it.'),
       "Only the owner may delete a complete community")
assert(hook.include?('Only the author can edit this post.') && hook.include?('role !== "owner" && role !== "admin"'),
       "Post mutations must enforce authorship and moderator permissions")
assert(service.include?('func toggleReaction') && service.include?('func editPost') && service.include?('func deletePost'),
       "The app service must expose reactions, editing, and deletion")
assert(service.include?('func deleteCommunity') && views.include?('showingDeleteCommunityConfirmation'),
       "Owners need a confirmed community deletion flow")
assert(views.include?('reactionSummary(post)') && views.include?('GymCommunityPostEditor') && views.include?('delete_message_confirmation'),
       "The Community UI must expose reactions, editing, and confirmed deletion")
assert(views.include?('communityPostActionsSheet') && views.include?('ForEach(reactionChoices'),
       "Long-press message actions must show reactions in one compact row")
assert(views.include?('UIPasteboard.general.string = "\\(copyAuthorName(for: post)): \\(post.body)"'),
       "Long-press message actions must copy author and message")
assert(views.include?('replySwipeGesture(for: post)') && views.include?('beginReply(to: post)'),
       "Messages must support swipe-to-reply and long-press reply")
assert(service.include?('replyToID: String?') && service.include?('replyTo: GymCommunityPost? = nil'),
       "Community replies must be sent through the app service")
assert(!hook.include?('gymCommunityReplyPreview') && !hook.include?('gymCommunitySendNewsPush') &&
       hook.scan('let replyPreview = null').length == 3 && hook.include?('function sendNewsPush') &&
       hook.include?('Replies must stay inside the same community.'),
       "Isolated PocketBase route callbacks must validate replies and send news without module-level helpers")
assert(!views.include?('Image(systemName: "face.smiling")'),
       "The separate reaction button below a message must stay removed")
assert(views.include?('.scrollDismissesKeyboard(.interactively)'),
       "Community chat scrolling must dismiss the keyboard interactively")
assert(images.include?('name: "image"') && images.include?('thumbs: ["128x128", "512x512"]'),
       "Communities must persist optimized cover images")
assert(hook.include?('/members/:userId/role') && hook.include?('Only the gym owner can manage member roles.'),
       "Only gym owners may assign employee roles")
assert(service.include?('func setMemberRole') && views.include?('GymCommunityMembersView'),
       "The app must expose member role management")

puts "Gym Community images, roles, reactions, editing, deletion, and localized errors are present."
