#!/usr/bin/env ruby

service = File.read("CalorieTrackerApp/GlobalFoodService.swift")
store = File.read("CalorieTrackerApp/FoodStore.swift")
hook = File.read("pb_hooks/global_food_search.pb.js")
migration = File.read("pb_migrations/1788200000_global_food_fts.js")
views = %w[AddEntryView.swift BatchAddEntryView.swift RecipeEditorView.swift LocalFoodAnalysisView.swift].map do |name|
  File.read(File.join("CalorieTrackerApp", name))
end.join("\n")

abort("Global starter catalogue must be bounded") unless service.include?("while page <= 4")
abort("Global search route is not used") unless service.include?("/api/hyse/global-foods/search")
abort("Remote results are not cached locally") unless store.include?("hydrateGlobalSearch") && store.include?("saveGlobalFoods()")
abort("Food search screens must request remote results") unless views.scan("hydrateGlobalSearch").length >= 4
abort("Search route must require a user") unless hook.include?('$apis.requireRecordAuth("users")')
abort("Search result count must be bounded") unless hook.include?('LIMIT 80')
abort("FTS query must bind user input") unless hook.include?('MATCH {:match}') && hook.include?('.bind({ match:')
abort("FTS failures must not fall back to a full catalogue scan") if hook.include?('findRecordsByFilter("global_foods"')
abort("Failed searches must not be cached as empty results") unless service.include?('async -> [FoodItem]?') && store.include?('guard let matches = await GlobalFoodService.shared.search')
abort("FTS migration or maintenance triggers missing") unless migration.include?("USING fts5") && migration.scan("CREATE TRIGGER").length == 3

puts "Scalable global food search checks passed."
