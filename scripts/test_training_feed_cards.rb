#!/usr/bin/env ruby
require_relative "training_view_sources"

source = TrainingViewSources.read

checks = {
  "profile uses detailed workout cards" => source.include?("profileWorkoutRow(workout)"),
  "profile card includes its workout title" => source.match?(/profileWorkoutRow[\s\S]*Text\(workout\.name\)/),
  "profile card includes duration and volume" => source.match?(/profileWorkoutRow[\s\S]*feedMetric\(t\("training\.duration"\)[\s\S]*feedMetric\(t\("training\.total_volume"\)/),
  "profile card previews three exercises" => source.match?(/profileWorkoutRow[\s\S]*workout\.exercises\.prefix\(3\)/),
  "profile card shows remaining exercise count" => source.match?(/profileWorkoutRow[\s\S]*training\.feed\.more_exercises/),
  "profile card has an actions menu" => source.match?(/profileWorkoutRow[\s\S]*Menu \{/),
  "friend cards preview exercise initials" => source.match?(/friendWorkoutRow[\s\S]*ExerciseMovementVisual/)
}

failures = checks.reject { |_, passed| passed }.keys
abort("Training feed card checks failed: #{failures.join(', ')}") unless failures.empty?

puts "Training feed card checks passed."
