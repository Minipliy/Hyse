#!/usr/bin/env ruby

def assert(value, message)
  raise message unless value
end

content = File.read("CalorieTrackerApp/ContentView.swift")
training = File.read("CalorieTrackerApp/TrainingStore.swift")
frequency = File.read("CalorieTrackerApp/FrequencyStore.swift")
health = File.read("CalorieTrackerApp/HealthKitManager.swift")
design = File.read("CalorieTrackerApp/HyseDesignSystem.swift")

assert(content.include?("TabView(selection: tabSelection)"), "The add action must not mount a disposable blank tab")
assert(content.scan("safeAreaInset(edge: .bottom, spacing: HyseSpacing.small) { activeWorkoutInset }").length == 1,
       "Only one active-workout timer may be mounted across the main tabs")
assert(!content.include?(".toolbarBackground(.ultraThinMaterial, for: .tabBar)"),
       "The main tab bar must not stack another live blur below system Liquid Glass")
assert(!content[/private var homeView: some View.*?private var homeCalendarSheet/m].include?("applyAccountMode()"),
       "Returning to nutrition must not reactivate and resync every account store")
assert(training.include?("guard accountID != id else { return }"),
       "Training account activation must be idempotent")
assert(frequency.include?("guard accountID != id else { return }"),
       "Food-frequency account activation must be idempotent")
assert(health.include?("bodyWeightRefreshInFlight") && health.include?("energyRefreshesInFlight") && health.include?("stepRefreshesInFlight"),
       "Health queries must be coalesced while tab views appear")
static_panel = design[/private struct HysePanelBackground: View.*?\n}\n\nenum HyseSpacing/m]
assert(static_panel && !static_panel.include?(".glassEffect(") && !static_panel.include?(".thinMaterial"),
       "Repeated static cards must not each allocate a live blur surface")

puts "Main tab-switch performance regression tests passed."
