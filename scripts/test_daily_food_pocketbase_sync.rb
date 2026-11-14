root = File.expand_path("..", __dir__)
store = File.read(File.join(root, "CalorieTrackerApp", "DailyFoodAutomation.swift"))
service = File.read(File.join(root, "CalorieTrackerApp", "DailyFoodScheduleSyncService.swift"))
migration = File.read(File.join(root, "pb_migrations", "1788700520_daily_food_schedules.js"))
content = File.read(File.join(root, "CalorieTrackerApp", "ContentView.swift"))

abort("daily foods are not marked dirty") unless store.include?("markDirty(schedule.id)")
abort("daily-food changes do not schedule PocketBase sync") unless store.include?("schedulePendingSync()")
abort("daily-food account activation does not fetch PocketBase") unless store.include?("syncPendingSchedules()")
abort("daily-food store is missing authentication") unless content.include?("dailyFoodStore.authManager = authManager")
abort("daily foods are not refreshed when the app returns") unless content.include?("dailyFoodStore.syncPendingSchedules()")
abort("daily-food service does not use its PocketBase collection") unless service.include?("/api/collections/daily_food_schedules/records")
abort("daily-food PocketBase collection migration is missing") unless migration.include?('name: "daily_food_schedules"') && migration.include?("idx_daily_food_schedules_user_client")

puts "daily food PocketBase sync checks passed"
