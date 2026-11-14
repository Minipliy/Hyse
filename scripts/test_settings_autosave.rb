#!/usr/bin/env ruby

view = File.read(File.expand_path("../CalorieTrackerApp/SettingsView.swift", __dir__))

abort "Settings must not require a manual save button" if view.include?('Button {\n                            saveSettings()')
abort "Draft settings must save after a quiet typing period" unless view.include?('scheduleAutomaticSave()') && view.include?('Task.sleep(for: .milliseconds(650))')
abort "Account sync must be debounced" unless view.include?('scheduleDeferredSettingsSync()') && view.include?('Task.sleep(for: .milliseconds(900))')
abort "Pending settings must flush when leaving" unless view.include?('.onDisappear {') && view.include?('flushPendingSettings()')
abort "Leaving unchanged settings must not trigger needless sync" unless view.include?('if shouldSync { syncSettingsNow() }')
abort "Autosave must not dismiss the keyboard while typing" if view.include?('private func applySettingsDraft') && view.match?(/private func applySettingsDraft.*resignFirstResponder/m)

puts "Settings save automatically, batch remote sync, and flush on exit."
