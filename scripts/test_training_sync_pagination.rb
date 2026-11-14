#!/usr/bin/env ruby

sync = File.read(File.expand_path("../CalorieTrackerApp/TrainingSyncService.swift", __dir__))

abort "training sync only requests the first result page" unless sync.include?("while true") && sync.include?("String(page)")
abort "training sync does not combine all result pages" unless sync.include?("values.append(contentsOf: result.items)")
abort "training sync has no page completion guard" unless sync.include?("result.page < result.totalPages")
abort "dirty workouts can be replaced by older server snapshots" unless sync.include?("for id in dirtyWorkoutIDs") && sync.include?("mergedWorkoutsByID[id] = local")

puts "Training sync paginates all server records."
