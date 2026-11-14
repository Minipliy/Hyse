#!/usr/bin/env ruby
require_relative "training_view_sources"

def assert(value, message)
  raise message unless value
end

app_sources = Dir["CalorieTrackerApp/**/*.swift"].map { |path| File.read(path) }.join("\n")
widget_sources = Dir["CalorieWidget/**/*.swift"].map { |path| File.read(path) }.join("\n")
design = File.read("CalorieTrackerApp/HyseDesignSystem.swift")
training_views = TrainingViewSources.read

gradient_count = app_sources.scan(/(?:Linear|Radial|Angular)Gradient|Gradient\s*\(/).size
assert(gradient_count.zero?, "Hyse app surfaces must use static colors instead of decorative gradients")
assert(design.include?("struct HyseNutritionBackdrop"), "The nutrition dashboard must keep its dedicated static backdrop")
assert(!widget_sources.match?(/(?:Linear|Radial|Angular)Gradient|Gradient\s*\(/), "Widgets must not use decorative gradients")
assert(design.include?(".glassEffect("), "Shared Hyse surfaces must use Liquid Glass on supported iOS versions")
assert(design.include?("struct HysePanelShape"), "Shared Hyse panels must keep the asymmetric cut-corner identity")
assert(design.include?("struct HyseFoodPattern"), "App backgrounds must keep the subtle food-symbol identity")
assert(design.include?("UIColor(red: 0.090"), "Dark mode must use Hyse charcoal instead of a black system background")
assert(design.scan(/Motif\(id:/).size >= 16, "The food-symbol background must remain visibly populated")
assert(design.include?("accessibilityReduceTransparency"), "Liquid Glass must provide a reduced-transparency fallback")
assert(design.include?("elevated ? HyseColor.elevatedSurface : HyseColor.surface"), "Repeated cards and older iOS versions must use the efficient static surface fallback")
assert(design.include?("static let information = accent"), "Informational UI must use the single Hyse accent")
assert(!design.match?(/ambient(?:Blue|Violet|Coral|Mint|Amber)/), "Decorative ambient color tokens must not return")
assert(!app_sources.match?(/HyseColor\.ambient/), "App screens must not reintroduce decorative competing accents")
assert(design.include?("DragGesture(minimumDistance: 0") && design.include?("draggedCenterX"), "Shared graph selectors must keep their draggable glass bubble")
assert(training_views.include?("private struct TrainingSectionBar") && training_views.include?("simultaneousGesture(selectionDrag"), "Training navigation must keep its draggable glass selector")

puts "Minimal Hyse Liquid Glass color-system regression tests passed."
