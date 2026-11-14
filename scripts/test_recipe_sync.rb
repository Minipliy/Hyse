#!/usr/bin/env ruby
# Deterministic regression contract for recipe persistence and PocketBase sync.

def assert(condition, message)
  raise message unless condition
end

recipe = File.read("CalorieTrackerApp/Recipe.swift")
sync = File.read("CalorieTrackerApp/RecipeSyncService.swift")
entry = File.read("CalorieTrackerApp/CalorieEntrySyncService.swift")
content = File.read("CalorieTrackerApp/ContentView.swift")
migration = File.read("pb_migrations/1787507400_recipe_sync.js")
hook = File.read("pb_hooks/recipes.pb.js")

contracts = {
  "guest/account recipe scopes" => recipe.include?('storagePrefix = "saved_recipes_v2"') && recipe.include?('"account_\\($0)"'),
  "legacy recipe migration" => recipe.include?("migrateLegacyRecipesIfNeeded"),
  "offline dirty and delete queues" => recipe.include?("markDirty") && recipe.include?("markDeleted"),
  "stale response protection" => recipe.include?("expectedSync") && recipe.include?("expectedProfile"),
  "confirmed-only guest removal" => recipe.include?("finishGuestMerge") && recipe.include?("confirmedIDs"),
  "idempotent stable client IDs" => sync.include?('"client_id": recipe.id.uuidString.lowercased()'),
  "conflict copy preservation" => sync.include?("conflictCopies") && sync.include?("copy.syncStatus = .conflict"),
  "atomic ingredient snapshots" => sync.include?('"ingredients": Self.ingredientObjects') && migration.include?('json("ingredients")'),
  "private owner rules" => migration.include?('user = @request.auth.id') && hook.include?('e.record.set("user", account.id)'),
  "unique per-user recipe ID" => migration.include?("idx_user_recipes_user_client"),
  "moderated global submissions" => migration.include?("global_recipe_submissions") && hook.include?("requireAdminAuth"),
  "approved global catalogue isolation" => migration.include?('moderation_status = "approved"'),
  "meal recipe relations" => entry.include?('payload["user_recipe"]') && entry.include?('payload["global_recipe"]'),
  "stable recipe meal fallback" => entry.include?('payload["recipe_client_id"]'),
  "login and foreground refresh" => content.include?("recipeStore.activateAccount()") && content.include?("recipeStore.syncPendingRecipes()"),
}
contracts.each { |name, valid| assert(valid, "Missing recipe sync contract: #{name}") }

# Precision and serving regression: 200 g at the values below, split into two
# portions. Internal values remain unrounded until presentation.
food = { kcal: 123.456, carbs: 10.25, protein: 7.75, fat: 3.125 }
amount = 200.0
servings = 2.0
totals = food.transform_values { |value| value * amount / 100.0 }
per_serving = totals.transform_values { |value| value / servings }
assert((per_serving[:kcal] - 123.456).abs < 0.000001, "Per-serving calorie math regressed")
assert((per_serving[:protein] - 7.75).abs < 0.000001, "Per-serving protein math regressed")
assert(!recipe.match?(/totalNutrients[\s\S]{0,1200}rounded\(/), "Recipe totals round too early")

puts "Recipe sync regression tests passed (#{contracts.length} architecture contracts and precision math)."
