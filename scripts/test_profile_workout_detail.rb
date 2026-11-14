#!/usr/bin/env ruby
require_relative "training_view_sources"

source = TrainingViewSources.read
detail = source[/struct WorkoutSummaryView: View[\s\S]*?\nstruct TrainingStatisticsDashboardView: View/] || ""

checks = {
  "profile passes its username into workout detail" => source.include?("WorkoutSummaryView(workout: workout, store: store, username: social.username)"),
  "detail uses the Hyse backdrop and scrolling layout" => detail.include?("HyseBackdrop()") && detail.include?("ScrollView"),
  "detail shows workout header metrics" => detail.include?("workoutHeader") && detail.include?("training.completed_sets"),
  "detail shows a muscle split" => detail.include?("muscleSplitSection") && detail.include?("ProgressView(value: entry.fraction)"),
  "detail shows exercise initials and completed sets" => detail.include?("ExerciseMovementVisual") && detail.include?("exercise.sets.filter(\\.completed)"),
  "detail offers editing and sharing" => detail.include?("WorkoutCompletionEditor") && detail.include?("ShareLink"),
  "legacy list layout is removed" => !detail.match?(/\n\s*List \{/)
}

failures = checks.reject { |_, passed| passed }.keys
abort("Profile workout detail checks failed: #{failures.join(', ')}") unless failures.empty?

puts "Profile workout detail checks passed."
