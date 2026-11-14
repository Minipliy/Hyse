#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
view = File.read(File.join(root, "CalorieTrackerApp", "AddEntryView.swift"))
store = File.read(File.join(root, "CalorieTrackerApp", "FoodStore.swift"))
service = File.read(File.join(root, "CalorieTrackerApp", "GlobalFoodService.swift"))

abort "opening Add Entry still starts a full food sync" if view.include?(".task { foodStore.syncPendingFoods(); foodStore.syncFavorites() }")
abort "food filtering is not moved away from the UI actor" unless view.include?("Task.detached(priority: .userInitiated)")
abort "the initial result list is not bounded" unless view.include?(".prefix(80)")
abort "search results are not bounded" unless view.include?(".prefix(120)")
abort "search loading feedback is missing" unless view.include?("isSearchingRemoteFoods") && view.include?("add_entry.searching_foods")
abort "repeated server searches are not cached" unless store.include?("globalTextSearchCache")
abort "server search can still leave the UI waiting too long" unless service.include?("request.timeoutInterval = 4")

puts "Add-entry opening and food-search performance contracts passed."
