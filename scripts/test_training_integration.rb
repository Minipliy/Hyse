#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
checks = {
  "stable account-scoped cache" => ["CalorieTrackerApp/TrainingStore.swift", /account_.*training_state_/m],
  "active workout local persistence" => ["CalorieTrackerApp/TrainingStore.swift", /workouts: \[WorkoutLog\].*restTimerEnd/m],
  "guest training merge" => ["CalorieTrackerApp/TrainingStore.swift", /pendingGuestRoutines.*pendingGuestExercises/m],
  "stale response generation guard" => ["CalorieTrackerApp/TrainingStore.swift", /syncGeneration == generation/m],
  "server stale snapshot protection" => ["pb_hooks/training_owner_and_streaks.pb.js", /newer training version is already stored/m],
  "authenticated owner enforcement" => ["pb_hooks/training_owner_and_streaks.pb.js", /e\.record\.set\("user", account\.id\)/m],
  "idempotent workout index" => ["pb_migrations/1787506200_training_core.js", /idx_workouts_user_client/m],
  "idempotent workout set index" => ["pb_migrations/1787506200_training_core.js", /idx_workout_sets_user_client/m],
  "server training streak events" => ["pb_hooks/training_owner_and_streaks.pb.js", /training_streak_events/m],
  "account deletion includes workouts" => ["pb_hooks/account_deletion.pb.js", /workout_sets.*workouts/m],
  "active workout bar" => ["CalorieTrackerApp/ContentView.swift", /ActiveWorkoutBar/m],
  "no visible rest notification" => ["CalorieTrackerApp/TrainingStore.swift", /RestFeedbackController\.shared\.playTimerCompletion/m],
  "stable rest timer identity" => ["CalorieTrackerApp/TrainingStore.swift", /restTimerID == timerID/m],
  "rest timer stays visible at the bottom" => ["CalorieTrackerApp/TrainingViews.swift", /safeAreaInset\(edge: \.bottom, spacing: 0\).*if store\.restTimerEnd != nil.*bottomRestTimer/m],
  "absolute Live Activity rest deadline" => ["CalorieTrackerApp/TrainingActivityAttributes.swift", /restTimerEnd: Date\?/m],
  "ActivityKit lifecycle" => ["CalorieTrackerApp/TrainingLiveActivityController.swift", /(?=.*Activity\.request)(?=.*matching\.update)(?=.*activity\.end)/m],
  "Dynamic Island layouts" => ["CalorieWidget/TrainingLiveActivity.swift", /compactLeading:.*compactTrailing:.*minimal:/m],
  "configurable training overview" => ["CalorieTrackerApp/UserSettingsStore.swift", /case date, calories, training, water, nutrition, meals/m],
  "versioned synced training preferences" => ["CalorieTrackerApp/AccountDataStore.swift", /schemaVersion = 21.*rest_sound_enabled.*live_activity_enabled.*home_section_order/m],
  "paused workout backend state" => ["pb_migrations/1787511000_training_pause_status.js", /\["active", "paused", "completed"\]/m],
  "routine planning" => ["CalorieTrackerApp/TrainingViews.swift", /plannedWeekday.*moveExercise/m],
  "routine permits repeated exercises" => ["CalorieTrackerApp/TrainingViews.swift", /private func add\(_ exercise: TrainingExercise\).*draft\.exercises\.append\(RoutineExercise\(exercise: exercise\)\)/m],
  "dirty routine keeps local child snapshot" => ["CalorieTrackerApp/TrainingSyncService.swift", /for id in dirtyRoutineIDs.*mergedRoutinesByID\[id\] = local/m],
  "only dirty routines force root and child sync" => ["CalorieTrackerApp/TrainingSyncService.swift", /for routine in mergedRoutines where dirtyRoutineIDs\.contains\(routine\.id\).*syncRoutineChildren/m],
  "active workout uploads stay deferred" => ["CalorieTrackerApp/TrainingStore.swift", /completedWorkoutIDs.*syncableWorkoutIDs.*intersection/m],
  "training sync uses a multi-minute quiet period" => ["CalorieTrackerApp/TrainingStore.swift", /Task\.sleep\(for: \.seconds\(180\)\)/m],
  "profile chart supports exact low-overhead week selection" => ["CalorieTrackerApp/TrainingViews.swift", /chartOverlay.*selectProfilePoint.*selectedProfileWeek != point\.week/m],
  "training profile avatar is directly editable" => ["CalorieTrackerApp/TrainingViews.swift", /ProfileAvatarView\(size: 124, editable: true\)/m],
  "versioned routine child repair" => ["CalorieTrackerApp/TrainingStore.swift", /training_children_verified_.*_v3/m],
  "exercise add errors do not move successful workout content" => ["CalorieTrackerApp/TrainingViews.swift", /if let addErrorMessage.*style: \.error/m],
  "decorative background cannot block training controls" => ["CalorieTrackerApp/HyseDesignSystem.swift", /HyseColor\.background.*allowsHitTesting\(false\)/m],
  "exercise progress charts" => ["CalorieTrackerApp/TrainingInsightsViews.swift", /Chart \{.*ForEach\(chartPoints\)/m],
  "activity and training health overview" => ["CalorieTrackerApp/TrainingViews.swift", /healthActivityCard.*healthTrainingCard/m],
  "activity double-counting explanation" => ["CalorieTrackerApp/en.lproj/Localizable.strings", /Workout estimates are not added separately/m]
}

errors = checks.filter_map do |name, (relative, pattern)|
  path = File.join(root, relative)
  source = relative == "CalorieTrackerApp/TrainingViews.swift" ? TrainingViewSources.read(root) : (File.exist?(path) ? File.read(path) : "")
  source !~ pattern ? "Missing contract: #{name}" : nil
end

abort errors.join("\n") unless errors.empty?
training_views = TrainingViewSources.read
abort "Successful exercise additions must not insert a banner" if training_views.include?('addedMessage = t("training.exercise.added"')
abort "Routine search must not hide an exercise after selecting it" if training_views.include?("let selectedIDs = Set(draft.exercises")
puts "Training integration contracts passed (#{checks.length} checks)."
