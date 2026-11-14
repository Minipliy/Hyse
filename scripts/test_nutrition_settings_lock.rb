#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
store = File.read(File.join(root, "CalorieTrackerApp", "NutritionSettingsLockStore.swift"))
settings = File.read(File.join(root, "CalorieTrackerApp", "SettingsView.swift"))

required_scopes = %w[
  dailyCalorieGoal
  calorieBalance
  calorieLimitBuffer
  fastingBlock
  trackingWindow
  eveningRule
]

required_scopes.each do |scope|
  abort("missing nutrition lock scope: #{scope}") unless store.include?("case #{scope}")
  abort("missing settings gate: #{scope}") unless settings.include?("isNutritionSettingLocked(.#{scope})")
end

abort("passcode verifier is not stored in Keychain") unless store.include?("SecItemAdd") && store.include?("SecItemCopyMatching")
abort("passcode is not salted and hashed") unless store.include?("SHA256.hash") && store.include?("SecRandomCopyBytes")
abort("raw passcode must not be stored in UserDefaults") if store.match?(/UserDefaults[^\n]*passcode/i)
abort("lock management must require verification") unless settings.include?("presentNutritionCodePrompt(.manage)")
abort("session unlock must be cleared") unless settings.include?("unlockedNutritionScopes.removeAll()")
abort("calorie limit and buffer must share one protected gate") unless settings.include?("isNutritionSettingLocked(.calorieLimitBuffer)") && settings.include?("nutritionLockedRow(.calorieLimitBuffer)")

puts "nutrition settings lock checks passed"
