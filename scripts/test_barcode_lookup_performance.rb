#!/usr/bin/env ruby

root = File.expand_path("..", __dir__)
store = File.read(File.join(root, "CalorieTrackerApp", "FoodStore.swift"))
entry = File.read(File.join(root, "CalorieTrackerApp", "AddEntryView.swift"))
recipe = File.read(File.join(root, "CalorieTrackerApp", "RecipeEditorView.swift"))
external = File.read(File.join(root, "CalorieTrackerApp", "OpenFoodFactsService.swift"))

checks = {
  "local barcode lookups use an index" => store.include?("personalBarcodeIndex[normalizedBarcode]") && store.include?("globalBarcodeIndex[normalizedBarcode]"),
  "remote barcode misses are cached" => store.include?("barcodeLookupCache[normalizedBarcode] = (Date(), matches)"),
  "entry lookup starts the external fallback concurrently" => entry.match?(/let externalTask = Task.*fetchProduct.*\n\s*let matches = await foodStore\.lookupKnownBarcode/m),
  "recipe lookup starts the external fallback concurrently" => recipe.match?(/let externalTask = Task.*fetchProduct.*\n\s*let matches = await foodStore\.lookupKnownBarcode/m),
  "Open Food Facts keeps positive results in memory" => external.include?("positiveCache[barcode] = value"),
  "Open Food Facts allows URL cache hits" => external.include?("request.cachePolicy = .returnCacheDataElseLoad")
}

failed = checks.reject { |_, passed| passed }
if failed.empty?
  puts "Barcode lookup performance checks passed."
  exit 0
end

failed.each_key { |name| warn "FAILED: #{name}" }
exit 1
