#!/usr/bin/env ruby
require "json"

def assert(value, message)
  raise message unless value
end

asset = JSON.parse(File.read("CalorieTrackerApp/Assets.xcassets/AccentColor.colorset/Contents.json"))
design = File.read("CalorieTrackerApp/HyseDesignSystem.swift")
app_sources = Dir["CalorieTrackerApp/**/*.swift"].map { |path| File.read(path) }.join("\n")
widget = File.read("CalorieWidget/TrainingLiveActivity.swift")

assert(asset.fetch("colors").length == 1, "AccentColor must not have light/dark variants")
assert(asset.fetch("colors").none? { |color| color.key?("appearances") }, "AccentColor must be appearance-independent")
components = asset.fetch("colors").first.fetch("color").fetch("components")
assert(components.values_at("red", "green", "blue") == ["0.055", "0.549", "0.549"], "Asset and SwiftUI accent must match")
assert(design.include?("Color(red: 0.055, green: 0.549, blue: 0.549)"), "Central Hyse accent is inconsistent")
assert(!app_sources.include?("foregroundStyle(.tint)"), "Views must not fall back to a transitional system tint")
assert(!widget.include?(".teal"), "Live Activity must use the same Hyse accent")

puts "Stable Hyse accent regression tests passed."
