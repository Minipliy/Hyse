#!/usr/bin/env ruby

view = File.read(File.expand_path("../CalorieTrackerApp/HyseNotificationCenter.swift", __dir__))
picker = view[/private var categoryPicker: some View \{.*?\n    \}\n\n    private func notificationRow/m]

abort "Notification category picker is missing" unless picker
abort "All four notification filters must share the available width" unless picker.include?('.frame(maxWidth: .infinity)')
abort "Notification filters must reach close to both screen edges" unless picker.include?('leading: HyseSpacing.small') && picker.include?('trailing: HyseSpacing.small')
abort "Long selected category names must remain visible" unless picker.include?('.minimumScaleFactor(0.8)')

puts "Notification filters span the available screen width."
