#!/usr/bin/env ruby
require_relative "training_view_sources"

def assert(value, message)
  raise message unless value
end

design = File.read("CalorieTrackerApp/HyseDesignSystem.swift")
training = TrainingViewSources.read
insights = File.read("CalorieTrackerApp/TrainingInsightsViews.swift")

assert(design.include?("GlassEffectContainer"), "Shared segmented controls must use Apple's Liquid Glass container")
assert(design.include?(".glassEffect(") && design.include?(".interactive()"), "Shared segmented controls must use interactive native glass")
assert(design.include?("if #available(iOS 26.0, *)"), "Liquid Glass controls need an older-iOS fallback")

section_bar = training[/private struct TrainingSectionBar: View.*?\n}\n\nprivate struct FriendWorkoutDetailView/m]
assert(section_bar&.include?(".glassEffect("), "Friends, training and profile navigation must use Liquid Glass")
assert(section_bar&.include?("in: Capsule()"), "Training navigation must keep its compact capsule shape")
assert(section_bar&.include?("TrainingRootSection.allCases"), "All training destinations must remain available")
assert(section_bar&.include?("@GestureState private var draggedCenterX"), "Dragging must use transient local gesture state")
assert(section_bar&.include?(".updating($draggedCenterX)"), "The selection bubble must follow the finger without changing the whole screen")
assert(!section_bar&.include?(".onChanged"), "Dragging must not replace the selected training screen on every frame")
assert(section_bar&.include?(".accessibilityLabel(title(section))"), "Icon-only destinations must retain accessible names")
assert(!section_bar&.include?("Text(title(section))"), "The compact training bar should remain icon-only")

assert(insights.include?("items: TrainingWeightUnit.allCases"), "Exercise progress must offer a glass kg/lbs selector")
assert(insights.include?("items: TrainingChartRange.allCases"), "Exercise progress must offer a glass time-range selector")
assert(training.include?("items: TrainingWeightUnit.allCases") && training.include?("selection: $weightRange"), "Weight progress must retain glass unit and range selectors")

puts "Liquid Glass training-control regression tests passed."
