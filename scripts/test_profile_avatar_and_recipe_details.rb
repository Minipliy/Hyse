#!/usr/bin/env ruby

def assert(value, message)
  raise message unless value
end

auth = File.read("CalorieTrackerApp/AuthManager.swift")
avatar = File.read("CalorieTrackerApp/ProfileAvatarView.swift")
settings = File.read("CalorieTrackerApp/SettingsView.swift")
recipes = File.read("CalorieTrackerApp/RecipesView.swift")
recipe_details = File.read("CalorieTrackerApp/RecipeDetailViews.swift")
entry = File.read("CalorieTrackerApp/AddEntryView.swift")
migration = File.read("pb_migrations/1787751600_user_profile_avatars.js")
social_hook = File.read("pb_hooks/training_social.pb.js")

assert(auth.include?("multipart/form-data"), "Avatar must upload as a PocketBase file")
assert(auth.include?("maximumSide: CGFloat = 1024"), "Avatar must be resized before upload")
assert(auth.include?("accountAvatarLocalData") && auth.include?("pending_profile_avatar_"), "Own avatar must remain available offline and retry uploads")
assert(avatar.include?("ProfileImageDataCache") && avatar.include?("applicationSupportDirectory"), "Profile images need a persistent local cache")
assert(avatar.include?("canonicalAvatarURL") && avatar.include?('URLQueryItem(name: "thumb", value: "256x256")'), "Avatar sizes must share one persistent local file")
assert(avatar.include?("PhotosPicker"), "Profile must allow choosing a photo")
assert(avatar.include?("ProfileAvatarEditorView"), "Selected profile photos must open an editor")
assert(avatar.include?("Slider(value: $zoom") && avatar.include?("DragGesture()"), "Avatar editor must support resizing and repositioning")
assert(avatar.include?("renderedAvatarData()"), "Avatar editor must upload the adjusted crop")
assert(migration.include?('name: "avatar"') && migration.include?('maxSelect: 1'), "Users need one online avatar field")
assert(social_hook.include?('avatar: String('), "Training social responses must expose avatars")
assert(!settings.include?("NavigationView {\n            Form"), "Settings must not nest a second navigation container")
assert(settings.include?("NavigationLink { settingsDestination(category) }"), "Category navigation must use the native stack and back-swipe gesture")
assert(!settings.match?(/private func saveSettings\(\).*selectedSettingsCategory = nil/m), "Saving settings must keep the current category open")
assert(recipes.include?("RecipeLibraryCard") && recipes.include?("recipe.displayDescription") && entry.include?("RecipeLibraryCard("), "Recipe descriptions must be visible through the shared card in recipe and entry lists")
assert(recipe_details.include?('Text(description)') && recipe_details.include?('current.preparationSteps'), "Recipe details must show the description and preparation steps")

puts "Profile avatar, settings navigation and recipe detail regression tests passed."
