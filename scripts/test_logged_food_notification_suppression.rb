#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
manager = File.read(File.join(root, "CalorieTrackerApp", "MotivationNotificationManager.swift"))
store = File.read(File.join(root, "CalorieTrackerApp", "CalorieStore.swift"))

abort("food entries do not cancel today's notification") unless store.include?("MotivationNotificationManager.shared.cancelFoodLogReminder()")
abort("the 18:00 motivation notification has no date-specific identifier") unless manager.include?('motivationPrefix + notificationIdentifierDay(for: date) + ".18"')
abort("logging food does not remove today's motivation notification") unless manager.match?(/identifiers = foodLogReminderHours.*motivationIdentifier\(date\)/m)
abort("delivered reminders remain visible after food is logged") unless manager.include?("removeDeliveredNotifications(withIdentifiers: identifiers)")
abort("motivation notifications still use an uncancellable repeating trigger") if manager.match?(/motivationPrefix.*repeats: true/m)
abort("today's motivation is not skipped when food already exists") unless manager.match?(/scheduleMotivationalMessages\([\s\S]*skipToday: hasFoodToday \|\| hasLoggedFood\(on: Date\(\)\)/)
abort("a scheduling race can restore today's notification after logging") unless manager.match?(/revision != notificationScheduleRevision \|\| hasLoggedFood\(on: day\)/)

puts "logged food notification suppression checks passed"
