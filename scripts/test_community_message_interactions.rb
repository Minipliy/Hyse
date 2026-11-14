#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
views = TrainingViewSources.read
post_row = views[/private func postRow.*?private func communityPostActionsSheet/m] || ""
actions_sheet = views[/private func communityPostActionsSheet.*?private func deleteMessageConfirmationSheet/m] || ""

checks = {
  "long press uses a prepared impact haptic" => views.include?("feedback.prepare()") && views.include?("feedback.impactOccurred(intensity: 0.9)"),
  "message visibly pops before actions appear" => views.include?("emphasizedPostID = post.id") && views.include?("return 1.035"),
  "message rows do not compete with vertical scrolling" => !post_row.include?("DragGesture") && !post_row.include?("replySwipeGesture"),
  "reply remains available in the message menu" => actions_sheet.include?("beginReply(to: post)"),
  "copy includes author and message" => views.include?("copyAuthorName(for: post)): \\(post.body)"),
  "editor uses a dedicated multiline surface" => views.include?("TextEditor(text: $text)") && views.include?("training.community.edit_message_hint"),
  "editor reports save success and failure haptically" => views.include?("notificationOccurred(.success)") && views.include?("notificationOccurred(.error)")
}

failed = checks.reject { |_, passed| passed }
if failed.empty?
  puts "Community message interaction checks passed (#{checks.length})."
else
  failed.each_key { |name| warn "FAILED: #{name}" }
  exit 1
end
