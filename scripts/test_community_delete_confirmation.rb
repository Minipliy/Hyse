#!/usr/bin/env ruby
require_relative "training_view_sources"

source = TrainingViewSources.read

checks = {
  "custom delete sheet is presented" => source.include?(".sheet(item: $deletingPost)"),
  "message preview is shown" => source.match?(/deleteMessageConfirmationSheet[\s\S]*Text\(post\.body\)/),
  "delete action has a loading guard" => source.include?("guard !deletingPostInFlight else { return }"),
  "sheet cannot be dismissed while deleting" => source.include?(".interactiveDismissDisabled(deletingPostInFlight)"),
  "old system dialog is gone" => !source.match?(/\.confirmationDialog\(\s*t\("training\.community\.delete_message_title"\)/)
}

failures = checks.reject { |_, passed| passed }.keys
abort("Community delete confirmation checks failed: #{failures.join(', ')}") unless failures.empty?

puts "Community delete confirmation checks passed."
