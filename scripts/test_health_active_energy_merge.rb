#!/usr/bin/env ruby

source = File.read("CalorieTrackerApp/HealthKitManager.swift")
content = File.read("CalorieTrackerApp/ContentView.swift")

def assert(condition, message)
  abort("FAILED: #{message}") unless condition
end

assert(
  source.include?("fetchEnergyResult(type: activeEnergyType, for: date, useHealthKitSourceMerge: true)"),
  "daily active energy must request HealthKit source merging"
)
assert(
  source.include?("options: useHealthKitSourceMerge ? .cumulativeSum : [.cumulativeSum, .separateBySource]"),
  "active energy must use the merged cumulative HealthKit statistic"
)
assert(
  source.include?('selectionStrategy: "healthKitMerged"'),
  "the merge strategy must remain diagnosable"
)
assert(
  source.include?("fetchRestingEnergyResult(type: restingEnergyType, for: date)"),
  "resting energy must use the manual-entry-aware calculation"
)
assert(
  source.include?("HKMetadataKeyWasUserEntered") &&
    source.include?("max(0, total - manualBySource[sourceID, default: 0])") &&
    source.include?("(selectedAutomatic?.value ?? 0) + manualTotal"),
  "manual resting energy must be added once on top of the selected automatic source"
)
assert(
  content.include?("healthKitManager.refreshEnergy(around: selectedDate, force: true)"),
  "returning from Health must bypass the refresh throttle"
)

puts "Health active-energy merge regression checks passed."
