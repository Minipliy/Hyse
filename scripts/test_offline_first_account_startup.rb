#!/usr/bin/env ruby

def assert(value, message)
  raise message unless value
end

auth = File.read("CalorieTrackerApp/AuthManager.swift")
content = File.read("CalorieTrackerApp/ContentView.swift")
account = File.read("CalorieTrackerApp/AccountDataStore.swift")
calories = File.read("CalorieTrackerApp/CalorieStore.swift")
foods = File.read("CalorieTrackerApp/FoodStore.swift")
recipes = File.read("CalorieTrackerApp/Recipe.swift")
training = File.read("CalorieTrackerApp/TrainingStore.swift")

assert(auth.include?("self.isLoggedIn = !restoredToken.isEmpty && !restoredAccountID.isEmpty"), "Cached accounts must become visible before network refresh")
assert(auth.include?("catch {\n            // Keep the existing token for offline use"), "Temporary network failures must preserve the local session")
assert(auth.include?("http.statusCode == 401 || http.statusCode == 403"), "Explicitly rejected sessions must still log out")
assert(content.include?("calorieStore.activateAccount()") && content.include?("foodStore.activateAccount()"), "Nutrition caches must activate locally")
assert(content.include?("trainingStore.activateAccount()") && content.include?("recipeStore.activateAccount()"), "Training and recipe caches must activate locally")
assert(account.include?("loadSettingsSnapshot(scope: activeScope)"), "Cached account settings must apply before hydration")
assert(account.include?("saveSettingsSnapshot(snapshot, scope: activeScope)"), "Server settings must refresh the local cache")
assert(calories.include?('case .account(let id): return "\(storageKey)_account_\(id)"'), "Meal entries need an account cache")
assert(foods.include?("saved_food_items_v1") && recipes.include?("saved_recipes_v2") && training.include?("training_state_"), "All major data areas need persistent local storage")

puts "Offline-first account startup regression tests passed."
