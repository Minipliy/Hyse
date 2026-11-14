#!/usr/bin/env ruby

source = File.read(File.expand_path("../CalorieTrackerApp/HyseNotificationCenter.swift", __dir__))

abort "notification center has no dismiss environment" unless source.include?("@Environment(\\.dismiss) private var dismiss")
abort "notification center has no persistent close action" unless source.include?("Button { dismiss() }")
abort "close action is not in the cancellation toolbar" unless source.include?("ToolbarItem(placement: .cancellationAction)")
abort "sheet drag indicator is not visible" unless source.include?(".presentationDragIndicator(.visible)")
abort "close action lacks accessibility text" unless source.include?("notifications.close")
abort "notification center cannot be dismissed with a broad downward swipe" unless source.include?(".simultaneousGesture(notificationCenterDismissGesture, including: .all)")
abort "dismiss swipe is too easy to trigger accidentally" unless source.include?("downwardDistance > 110") && source.include?("horizontalDistance * 1.35")

puts "Notification center dismissal checks passed."
