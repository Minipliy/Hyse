#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
views = TrainingViewSources.read
hooks = File.read(File.join(root, "pb_hooks", "gym_communities.pb.js"))

checks = {
  "removed reply target closes reply mode" => views.include?(".onChange(of: detail?.posts.map(\\.id) ?? [])") && views.include?("cancelUnavailableReply()"),
  "send button is disabled for a missing target" => views.include?("|| !replyTargetIsAvailable"),
  "server rejects deleted reply before creating post" => hooks.include?('throw new BadRequestError("The message being replied to no longer exists.")'),
  "offline replies are queued without a blocking refresh" => !views.include?("guard refreshSucceeded, stillExists else"),
  "draft text remains while unavailable reply is cancelled" => views.include?("private func cancelUnavailableReply()") && !views.match?(/private func cancelUnavailableReply\(\).*?message = ""/m),
  "user is told why sending was blocked" => views.include?("training.community.reply_unavailable_message")
}

failed = checks.reject { |_, passed| passed }
if failed.empty?
  puts "Deleted community reply checks passed (#{checks.length})."
else
  failed.each_key { |name| warn "FAILED: #{name}" }
  exit 1
end
