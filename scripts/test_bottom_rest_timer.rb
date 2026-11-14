#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
views = TrainingViewSources.read
notifications = File.read(File.join(root, "CalorieTrackerApp", "RestTimerNotificationController.swift"))
store = File.read(File.join(root, "CalorieTrackerApp", "TrainingStore.swift"))

def assert(condition, message)
  abort(message) unless condition
end

assert(views.match?(/safeAreaInset\(edge: \.bottom, spacing: 0\).*bottomRestTimer/m), "Rest timer must stay pinned to the bottom")
assert(views.include?('restTimerValue(end, fontSize: keyboardVisible ? 28 : 30)'), "Remaining rest time must be prominent above the keyboard")
assert(views.include?('restAdjustmentButton("−15")') && views.include?('restAdjustmentButton("+15")'), "Rest adjustment controls must remain available")
assert(views.include?('keyboardDismissButton') && views.include?('compactRestTimer(end)'), "The keyboard dismissal button belongs in the compact timer bar")
assert(views.include?('.fixedSize(horizontal: false, vertical: true)') && views.include?('TimelineView(.periodic(from: .now, by: 1))'), "Only the timer value should refresh while the timer bar keeps its keyboard layout")
assert(views.match?(/else if keyboardVisible \{\s*HStack \{\s*Spacer\(minLength: 0\)\s*keyboardDismissButton\s*\}\s*\.padding\(\.trailing, 10\)/), "Without a timer only the keyboard dismiss control may stand at the right")
assert(store.include?('RestTimerNotificationController.shared.schedule(timerID: timerID, end: end)'), "An active rest timer must schedule background delivery")
assert(notifications.include?('UNTimeIntervalNotificationTrigger') && notifications.include?('UNNotificationSound(named:'), "Background delivery must include the selected bundled sound")

puts "Bottom rest timer and background sound contracts passed."
