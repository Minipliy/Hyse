#!/usr/bin/env ruby

require "json"

root = File.expand_path("..", __dir__)
path = File.join(root, "pb_migrations", "1788093000_open_food_facts_de_top_1000.js")
migration = File.read(path)
match = migration.match(/const foods = (\[.*\])\n  for \(let index/m)
abort("Generated OFF food array not found") unless match
foods = JSON.parse(match[1])

def valid_gtin?(code)
  return false unless [8, 12, 13, 14].include?(code.length) && code.match?(/\A\d+\z/)
  sum = code[0...-1].reverse.chars.each_with_index.sum { |digit, index| digit.to_i * (index.even? ? 3 : 1) }
  ((10 - sum % 10) % 10) == code[-1].to_i
end

abort("Expected exactly 1000 products, got #{foods.length}") unless foods.length == 1_000
barcodes = foods.map { |food| food.fetch("barcode") }
abort("Duplicate barcodes in OFF seed") unless barcodes.uniq.length == barcodes.length
abort("Invalid GTIN in OFF seed") unless barcodes.all? { |barcode| valid_gtin?(barcode) }
abort("Missing product identity") unless foods.all? { |food| !food.fetch("source_name_en").empty? && food.fetch("source_id") == food.fetch("barcode") }
abort("Invalid base unit") unless foods.all? { |food| %w[g ml].include?(food.fetch("unit")) }
abort("Invalid nutrient range") unless foods.all? do |food|
  food.fetch("calories").between?(0, 900) &&
    %w[carbs protein fat sugar fiber saturated_fat salt].all? { |key| food.fetch(key).between?(0, 100) }
end
abort("Seed must be idempotent and preserve non-OFF records") unless migration.include?('barcode_normalized = {:barcode}') && migration.include?('!== "open_food_facts"')
abort("Seed must publish approved indexed barcode records") unless migration.include?('record.set("moderation_status", "approved")') && migration.include?('record.set("barcode_normalized", food.barcode)')
abort("OFF attribution is missing") unless migration.include?("Open Food Facts (ODbL 1.0)") && migration.include?("openfoodfacts.org")

service = File.read(File.join(root, "CalorieTrackerApp", "GlobalFoodService.swift"))
abort("Global catalogue hydration should use 500-record pages") unless service.include?('URLQueryItem(name: "perPage", value: "500")')

puts "Open Food Facts German top-1000 seed checks passed."
