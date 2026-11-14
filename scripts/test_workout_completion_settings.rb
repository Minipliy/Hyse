#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
views = TrainingViewSources.read
store = File.read(File.join(root, "CalorieTrackerApp", "TrainingStore.swift"))
settings = File.read(File.join(root, "CalorieTrackerApp", "SettingsView.swift"))
user_settings = File.read(File.join(root, "CalorieTrackerApp", "UserSettingsStore.swift"))
account_data = File.read(File.join(root, "CalorieTrackerApp", "AccountDataStore.swift"))

abort "completion screen still shows the redundant sync row" if views.include?('title: t("training.completion.sync")')
abort "routine tracking settings screen is missing" unless views.include?("RoutineTrackingSettingsView")
abort "routine tracking toggle is missing" unless views.include?("tracksRoutine: $tracksRoutine")
abort "routine value update toggle is missing" unless views.include?("updatesRoutineValues: $updatesRoutineValues")
abort "routine tracking is not persisted on save" unless views.include?("completedWorkout.routineID = routineID")
abort "routine values are not updated" unless store.include?("func updateRoutineValues") && store.include?("routineExercises(from: workout)")
abort "visibility is not presented as a dedicated sheet" unless views.include?("WorkoutVisibilitySheet(selection: visibility)")
abort "visibility sheet must only offer private and public" unless views.scan(/visibilityOption\(/).length == 3 && !views.include?('value: "friends"')
abort "visibility sheet unexpectedly includes heart-rate or calorie controls" if views.include?("publicHealthData") || views.include?("showHeartRateAndCalories")
abort "default gym setting is missing" unless settings.include?("settings.default_gym") && settings.include?("showingDefaultGymPicker")
abort "default visibility setting is missing" unless settings.include?("settings.default_workout_visibility") && settings.include?("$settingsStore.defaultWorkoutVisibility")
abort "default gym location is not persisted" unless user_settings.include?("defaultWorkoutGymAddress") && user_settings.include?("defaultWorkoutGymLatitude") && user_settings.include?("defaultWorkoutGymLongitude")
abort "new workout defaults are not applied at completion" unless views.include?("appliesDefaultPreferences: true") && views.include?("applyDefaultPreferencesIfNeeded()")
abort "workout defaults are not account-synced" unless account_data.include?("default_workout_gym_address") && account_data.include?("default_workout_visibility")

puts "Workout completion settings checks passed."
