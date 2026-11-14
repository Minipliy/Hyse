#!/usr/bin/env ruby

def assert(condition, message)
  raise message unless condition
end

calories = File.read("CalorieTrackerApp/CalorieStore.swift")
entry_sync = File.read("CalorieTrackerApp/CalorieEntrySyncService.swift")
foods = File.read("CalorieTrackerApp/FoodStore.swift")
food_sync = File.read("CalorieTrackerApp/FoodSyncService.swift")
portion_sync = File.read("CalorieTrackerApp/FoodPortionSyncService.swift")
recipes = File.read("CalorieTrackerApp/Recipe.swift")
recipe_sync = File.read("CalorieTrackerApp/RecipeSyncService.swift")
training = File.read("CalorieTrackerApp/TrainingStore.swift")
daily_foods = File.read("CalorieTrackerApp/DailyFoodAutomation.swift")
streak_rewards = File.read("CalorieTrackerApp/StreakRewardsStore.swift")
account = File.read("CalorieTrackerApp/AccountDataStore.swift")
auth = File.read("CalorieTrackerApp/AuthManager.swift")
meal = File.read("CalorieTrackerApp/CategoryDetailView.swift")

assert(calories.include?("schedulePendingSync()") && calories.include?("Task.sleep(for: .seconds(2))"), "Meal mutations must batch PocketBase sync")
assert(calories.include?("timeIntervalSince(lastSuccessfulSyncAt) < 3_600"), "Foreground meal refreshes need a freshness window")
assert(entry_sync.scan("await fetchAll(token: token)").length == 1, "Meal sync must not fetch the full collection twice")
assert(entry_sync.include?("fullRefresh: Bool") && entry_sync.include?("entry.remoteID"), "Meal edits must reuse cached PocketBase IDs")
assert(entry_sync.include?("unresolvedUploads") && entry_sync.include?("fullRefresh: true"), "Failed lightweight meal sync must repair stale server IDs")
assert(entry_sync.include?("dirtyIDs.subtracting(localByID.keys)"), "Orphaned meal dirty markers must be resolved")
assert(food_sync.scan("await fetchAll(token: token)").length == 1, "Saved-food sync must not fetch the full collection twice")
assert(portion_sync.include?("matches($0, portion: portion") && portion_sync.include?("guard needsServerRefresh else"), "Unchanged portions must not be uploaded or refetched")
assert(foods.include?("schedulePendingFoodSync()") && foods.include?("timeIntervalSince(lastSuccessfulSyncAt) < 3_600"), "Food sync must batch and suppress fresh refetches")
assert(foods.include?("globalCatalogueRefreshKey") && foods.include?("86_400"), "The offline food catalogue must use a long-lived cache")
assert(foods.include?("globalSubmissionRetryTask") && foods.include?(".prefix(10)"), "Global food submissions must use bounded retry batches")
assert(foods.include?("break") && foods.include?("scheduleGlobalSubmissionRetry"), "Global food submission failures must stop and back off")
assert(recipes.include?("schedulePendingRecipeSync()") && recipes.include?("timeIntervalSince(lastSuccessfulSyncAt) < 3_600"), "Recipe sync must batch and suppress fresh refetches")
assert(recipes.include?("globalCatalogueRefreshKey") && recipes.include?("86_400"), "The global recipe catalogue must use a long-lived cache")
assert(recipe_sync.scan("await fetchPersonal(token: token)").length == 1, "Recipe sync must not fetch the personal collection twice")
assert(training.include?("scheduleDeferredSync()") && training.include?("timeIntervalSince(lastSuccessfulSyncAt) < 3_600"), "Training sync must stay batched and suppress fresh refetches")
assert(training.include?("training_last_successful_sync_") && training.include?("UserDefaults.standard.set(now, forKey: self.lastSuccessfulSyncKey(accountID))"), "Training freshness must survive app relaunches")
assert(daily_foods.include?("timeIntervalSince(lastSuccessfulSyncAt) < 3_600"), "Unchanged daily schedules must not refetch on every foreground event")
assert(streak_rewards.include?("pendingSyncKey") && streak_rewards.include?("timeIntervalSince(lastSuccessfulSyncAt) < 3_600"), "Unchanged streak state must not refetch on every foreground event")
assert(auth.include?("Date().timeIntervalSince(lastSessionRefreshAt) < 900"), "Account refreshes must use a local freshness window")
assert(!account.include?("publisher(for: .foodUsageShouldRefresh)"), "Food usage must not be rebuilt twice")
record_usage = account[/func recordUsage\(food:.*?\n    \}/m]
assert(record_usage && !record_usage.include?("syncCurrentState"), "Local last-used updates must not send unrelated account-state requests")
assert(meal.include?(".swipeActions(edge: .trailing, allowsFullSwipe: true)"), "Meal entries need full-swipe deletion")
assert(meal.include?("calorieStore.deleteEntry(id: entry.id)"), "Swipe deletion must use the durable delete queue")

puts "PocketBase request-budget and meal swipe contracts passed."
