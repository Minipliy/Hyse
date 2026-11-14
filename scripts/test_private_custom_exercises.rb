#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
views = TrainingViewSources.read
store = File.read(File.join(root, "CalorieTrackerApp", "TrainingStore.swift"))
sync = File.read(File.join(root, "CalorieTrackerApp", "TrainingSyncService.swift"))
migration = File.read(File.join(root, "pb_migrations", "1788700200_keep_custom_exercises_private.js"))

create_view = views[/private struct CreateExerciseView: View.*?\n}\n\nprivate struct SuggestedRoutineProgramView/m]
abort "CreateExerciseView is missing" unless create_view
abort "Custom exercises must use a single name field" unless create_view.include?('training.exercise.name')
abort "Custom exercises must not ask for an English name" if create_view.include?('training.exercise.english_name')
abort "Custom exercises must not ask for a German name" if create_view.include?('training.exercise.german_name')
abort "Custom exercise names must be language-independent" unless store.include?('englishName: customName, germanName: customName')
abort "Custom exercise sync must remain private" unless sync.include?('"visibility": "private", "moderation_status": "private"')
abort "Server rules must enforce private visibility" unless migration.include?('visibility = "private"') && migration.include?('moderation_status = "private"')

puts "Custom exercises use one name and remain private to their owner."
