#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
views = TrainingViewSources.read
store = File.read(File.join(root, "CalorieTrackerApp", "TrainingStore.swift"))
hook = File.read(File.join(root, "pb_hooks", "training_social.pb.js"))

%w[share save_as_routine copy edit delete].each do |action|
  abort("missing feed action: #{action}") unless views.include?("training.feed.#{action}")
end

abort("feed card has no actions button") unless views.include?("selectedWorkoutActions = item")
abort("friend workout details are not loaded before copying") unless views.include?("await social.loadDetail(item, auth: authManager)")
abort("copy must start an active workout") unless views.include?("store.repeatWorkout(snapshot)") && views.include?("showingActiveWorkout = true")
abort("save as routine is not implemented") unless views.include?("store.createRoutine(from: snapshot)")
abort("edit/delete must be owner-only") unless views.include?("private func isOwnedWorkout(_ item: FriendWorkout)") &&
  views.include?("guard isOwnedWorkout(item) else { return }") &&
  views.include?("if item.userID == authManager.accountID { return true }")
abort("remote exercises need a local fallback") unless store.include?("englishName: log.exerciseNameSnapshot")
abort("the authenticated user's workouts are missing from the feed") unless hook.include?('const owners = [{ id: String(user.id), record: user }]')
abort("feed cards do not preview exercises") unless views.include?("snapshot.exercises.prefix(3)") && views.include?("ExerciseMovementVisual(exercise: exerciseSnapshot(exercise)")
abort("workout details do not show a muscle split") unless views.include?("private var muscleSplit:") && views.include?("ProgressView(value: entry.fraction)")
abort("workout details do not show completed sets") unless views.include?("workoutExerciseSection(exercise)") && views.include?("exercise.sets.filter(\\.completed)")

puts "training feed action checks passed"
