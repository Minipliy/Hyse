#!/usr/bin/env ruby

source = File.read(File.expand_path("../CalorieTrackerApp/HyseNotificationCenter.swift", __dir__))
picker = source[/private var categoryPicker: some View \{[\s\S]*?\n    private func notificationRow/] || ""

checks = {
  "picker uses the full available width" => picker.include?("GeometryReader") && picker.include?("proxy.size.width"),
  "selected category receives expanded width" => picker.include?("isSelected ? selectedWidth : compactWidth"),
  "selected category always shows its full label" => picker.include?("Text(t(filter.localizationKey))"),
  "inactive categories stay compact" => picker.include?("compactWidth"),
  "picker reaches both content edges" => picker.include?("leading: 0") && picker.include?("trailing: 0"),
  "all filters remain accessible by name" => picker.include?(".accessibilityLabel(t(filter.localizationKey))")
}

failures = checks.reject { |_, passed| passed }.keys
abort("Notification category picker checks failed: #{failures.join(', ')}") unless failures.empty?

puts "Notification category picker checks passed."
