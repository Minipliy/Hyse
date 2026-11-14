#!/usr/bin/env ruby
require_relative "training_view_sources"

def assert(condition, message)
  raise message unless condition
end

store = File.read("CalorieTrackerApp/TrainingStore.swift")
models = File.read("CalorieTrackerApp/TrainingModels.swift")
views = TrainingViewSources.read
content = File.read("CalorieTrackerApp/ContentView.swift")

assert(store.include?("scheduleLocalSave()") && store.include?("milliseconds(650)"), "Training edits must use a short local-save debounce")
assert(store.include?("pendingActiveWorkoutID") && store.include?("persistPendingActiveChanges()"), "Dirty-state persistence must stay out of the active interaction frame")
assert(store.include?("persistActiveJournal(workout)") && store.include?("TrainingWorkoutRecovery.restoredWorkouts(from: value.workouts, journal: journal, completedCheckpoint: completedCheckpoint)"), "Active training changes need an immediate crash-safety journal")
assert(store.include?("persistCompletedWorkoutCheckpoint(workout)") && store.include?("completedWorkoutCheckpoint(scope: scope)"), "Finishing a workout must leave a durable completion checkpoint for relaunch")
assert(models.include?("restored[index].status != .completed || restored[index].updatedAt < completedCheckpoint.updatedAt"), "A completed checkpoint must replace an older active workout")
assert(store.include?("TrainingWorkoutRecovery.shouldKeepCurrent(value, over: merged[id])"), "An older sync result must not reactivate a completed workout")
assert(store.include?("scheduleDeferredSync()") && store.include?("seconds(180)"), "Training edits must batch server synchronization for a multi-minute quiet period")
assert(store.include?("flushPendingChanges()"), "Completed actions must be able to flush local changes immediately")
assert(content.include?("trainingStore.flushPendingChanges()"), "Pending edits must flush before app suspension")
assert(views.include?("store.flushPendingChanges(); dismiss()"), "Closing a workout must flush local changes immediately")
assert(views.include?("Array(store.exercises.prefix(20))") && views.include?("trimmed.count >= 2"), "Routine creation must not render the full exercise library before searching")
assert(!views.include?(".hyseForm()\n            .environment(\\.editMode, .constant(.active))"), "Routine search results must not inherit permanent move mode")
assert(views.include?("@State private var draftSet: TrainingSetLog"), "Set fields must edit a lightweight local draft")
assert(views.include?("if wasFocused && !focused { commitDraft() }"), "Set drafts must commit when editing finishes")
assert(store.include?("scheduleLiveActivityRefresh()") && store.include?("milliseconds(400)"), "Live Activity updates must be debounced while typing")
assert(views.include?("previousPerformances(workoutExerciseID: exercise.id, count: exercise.sets.count)"), "Previous sets must be fetched once per exercise placement card")
assert(views.include?("Button(action: applyPreviousSet)") && views.include?("private func applyPreviousSet()"), "Tapping a previous set must copy its values into the current set")
assert(views.include?("private struct SetDeleteInteraction<Content: View>: UIViewControllerRepresentable") && views.include?("UIPanGestureRecognizer"), "Set deletion swipes must use a lightweight native pan recognizer")
assert(views.include?("hostedController.view.transform = CGAffineTransform") && views.include?("gestureRecognizerShouldBegin"), "Set rows must move directly without rebuilding their SwiftUI fields during a horizontal swipe")
assert(views.include?("deleteButton.alpha = 0") && views.include?("deleteButton.alpha = min(1, max(0, -offset / actionWidth))"), "The delete action must remain hidden until a row is swiped")
assert(views.include?("deleteButton.layer.maskedCorners") && views.include?("deleteButton.transform = CGAffineTransform(scaleX:"), "The delete action must visually belong to the revealed row background")
assert(views.include?("configuration.imagePlacement = .top") && views.include?("deleteActionTitle: t(\"settings.delete\")"), "The revealed destructive action must be clearly labeled as delete")
assert(views.include?(".scaledBy(x: 0.96, y: 0.18)") && views.include?("private func performDelete()"), "A deleted set must contract before its data is removed")
assert(views.include?("deletionRequested: deletionRequested") && views.include?("requestDeletionAfterSheetDismissal"), "Deleting from set options must use the same exit animation")
assert(store.include?("workout.exercises[index].sets.removeAll { $0.id == setID }"), "The final set must be removable too")

puts "Training edit performance regression tests passed."
