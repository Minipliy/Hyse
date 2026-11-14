#!/usr/bin/env ruby

def assert(condition, message)
  abort "FAILED: #{message}" unless condition
end

root = File.expand_path("..", __dir__)
read = ->(path) { File.read(File.join(root, path)) }

training_store = read.call("CalorieTrackerApp/TrainingStore.swift")
training_sync = read.call("CalorieTrackerApp/TrainingSyncService.swift")
training_models = read.call("CalorieTrackerApp/TrainingModels.swift")
content = read.call("CalorieTrackerApp/ContentView.swift")
add_entry = read.call("CalorieTrackerApp/AddEntryView.swift")
edit_entry = read.call("CalorieTrackerApp/EditEntryView.swift")
calorie_store = read.call("CalorieTrackerApp/CalorieStore.swift")
entry_sync = read.call("CalorieTrackerApp/CalorieEntrySyncService.swift")
entry_model = read.call("CalorieTrackerApp/CalorieEntry.swift")

# Premium gates must protect both creation and duplication paths, not just the UI.
limit_guard = "premiumTrainingUnlocked || routines.count < Self.freeRoutineLimit"
assert(training_store.scan(limit_guard).length >= 3, "training premium limit is not enforced on all routine mutations")
assert(training_store.include?("premiumTrainingUnlocked || customCount < Self.freeCustomExerciseLimit"), "custom exercise premium limit is missing")

# A non-premium user must be stopped and returned to today for future nutrition days.
assert(content.include?("handleSelectedNutritionDateChange(date)"), "calendar selection does not use the future-day gate")
assert(content.include?("startOfDay(for: selectedDate) > Calendar.current.startOfDay(for: Date())") && content.include?("showingNutritionPremium = true"), "future-day selection can bypass the nutrition premium gate")
assert(add_entry.include?("startOfDay(for: selectedEntryDate) > Calendar.current.startOfDay(for: Date())") && add_entry.include?("showingNutritionPremium = true"), "add-entry future date can bypass the nutrition premium gate")

# Local state must contain routines and amounts, and account sync must be retried
# from durable dirty markers after a relaunch.
assert(training_models.include?("var plannedWeekday: Int?"), "routine weekday is not part of the persisted model")
assert(training_store.include?("struct State: Codable") && training_store.include?("var routines: [WorkoutRoutine]"), "training restart snapshot omits routines")
assert(training_store.include?("storageKey(_ scope: String)") && training_store.include?("private func load(scope: String)"), "training store has no scoped restart load")
assert(training_store.include?("dirtyRoutineKey") && training_store.include?("markRoutineDirty(value.id)"), "routine edits are not durably marked for restart sync")
assert(training_store.include?("lastSuccessfulSyncKey") && training_store.include?("UserDefaults.standard.set(now, forKey: self.lastSuccessfulSyncKey(accountID))"), "training sync freshness is not persisted")
assert(training_sync.include?("for routine in mergedRoutines where dirtyRoutineIDs.contains(routine.id)"), "dirty routines are not pushed after a restart")

# Editing an amount must update local state, mark it dirty, and upload the same
# amount that the server must echo back before the dirty marker is cleared.
assert(calorie_store.include?("func updateEntry(_ entry: CalorieEntry)") && calorie_store.include?("markDirty(entry.id)"), "amount edits are not marked dirty")
assert(calorie_store.include?("updateEntries(_ changedEntries: [CalorieEntry])"), "batch amount edits have no durable store path")
assert(edit_entry.include?("updatedEntry.grams = updatedGrams") && edit_entry.include?("calorieStore.updateEntry(updatedEntry)"), "edit screen does not persist the changed amount")
assert(entry_sync.include?("\"amount\": entry.grams") && entry_sync.include?("Self.acknowledges(saved, entry: entry)"), "amount changes are not confirmed by sync")
assert(entry_sync.include?("abs(remote.amountGrams - entry.grams) <= tolerance"), "sync acknowledgement does not validate the changed amount")
assert(entry_model.include?("var kcal: Double") && entry_model.include?("grams / 100.0"), "nutrition totals are not recalculated from the edited amount")

puts "Edge-case regression contracts passed (premium, future days, restart sync and amounts)."
