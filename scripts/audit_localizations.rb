#!/usr/bin/env ruby
# Hyse localization gate. English is the source/fallback language; German must
# contain the same keys and positional format placeholders.

require "set"

root = File.expand_path("..", __dir__)
swift_files = Dir[File.join(root, "CalorieTrackerApp", "*.swift")]
widget_swift_files = Dir[File.join(root, "CalorieWidget", "*.swift")]

def read_strings(path)
  values = {}
  File.readlines(path).each_with_index do |line, index|
    next if line.strip.empty? || line.lstrip.start_with?("//")
    match = line.match(/^"([^"]+)"\s*=\s*"((?:\\.|[^"])*)";\s*$/)
    abort "Invalid .strings syntax at #{path}:#{index + 1}" unless match
    abort "Duplicate localization key #{match[1]} in #{path}" if values.key?(match[1])
    values[match[1]] = match[2]
  end
  values
end

english = read_strings(File.join(root, "CalorieTrackerApp", "en.lproj", "Localizable.strings"))
german = read_strings(File.join(root, "CalorieTrackerApp", "de.lproj", "Localizable.strings"))
errors = []

(english.keys - german.keys).sort.each { |key| errors << "Missing German translation: #{key}" }
(german.keys - english.keys).sort.each { |key| errors << "Missing English source: #{key}" }

placeholder = /%\d+\$(?:@|lld|ld|d|\.\d+f|f)/
(english.keys & german.keys).each do |key|
  en_placeholders = english[key].scan(placeholder).sort
  de_placeholders = german[key].scan(placeholder).sort
  errors << "Placeholder mismatch for #{key}: en=#{en_placeholders} de=#{de_placeholders}" unless en_placeholders == de_placeholders
  errors << "English translation exposes its technical key: #{key}" if english[key] == key || english[key].match?(/^[a-z0-9_]+(?:\.[A-Za-z0-9_]+)+$/)
  errors << "German translation exposes its technical key: #{key}" if german[key] == key || german[key].match?(/^[a-z0-9_]+(?:\.[A-Za-z0-9_]+)+$/)
end

source = swift_files.map { |file| [file, File.read(file)] }
referenced = source.flat_map do |_, content|
  content.scan(/(?:\bt|language\.text)\("([a-z0-9_]+(?:\.[A-Za-z0-9_]+)+)"/).flatten +
    content.scan(/"([a-z0-9_]+(?:\.[A-Za-z0-9_]+)+)"/).flatten.select { |key| english.key?(key) }
end.to_set
dynamic_prefixes = source.flat_map { |_, content| content.scan(/"([a-z0-9_]+(?:\.[A-Za-z0-9_]+)*\.)\\\(/).flatten }
english.keys.each { |key| referenced << key if dynamic_prefixes.any? { |prefix| key.start_with?(prefix) } }

(referenced - english.keys.to_set).sort.each { |key| errors << "Referenced key has no English source: #{key}" }
(english.keys.to_set - referenced).sort.each { |key| errors << "Unused localization key: #{key}" }

widget_english = read_strings(File.join(root, "CalorieWidget", "en.lproj", "Localizable.strings"))
widget_german = read_strings(File.join(root, "CalorieWidget", "de.lproj", "Localizable.strings"))
(widget_english.keys - widget_german.keys).sort.each { |key| errors << "Missing German widget translation: #{key}" }
(widget_german.keys - widget_english.keys).sort.each { |key| errors << "Missing English widget source: #{key}" }
(widget_english.keys & widget_german.keys).each do |key|
  en_placeholders = widget_english[key].scan(placeholder).sort
  de_placeholders = widget_german[key].scan(placeholder).sort
  errors << "Widget placeholder mismatch for #{key}: en=#{en_placeholders} de=#{de_placeholders}" unless en_placeholders == de_placeholders
end
widget_source = widget_swift_files.map { |file| [file, File.read(file)] }
widget_referenced = widget_source.flat_map { |_, content| content.scan(/WidgetLocalization\.text\("([a-z0-9_.]+)"\)/).flatten }.to_set
(widget_referenced - widget_english.keys.to_set).sort.each { |key| errors << "Referenced widget key has no English source: #{key}" }
(widget_english.keys.to_set - widget_referenced).sort.each { |key| errors << "Unused widget localization key: #{key}" }

ui_call = /\b(?:Text|Button|Label|Picker|Toggle|Section|TextField|SecureField|ProgressView)\(\s*"((?:\\.|[^"])*)"/
source.each do |file, content|
  content.each_line.with_index(1) do |line, line_number|
    next if line.lstrip.start_with?("//")
    line.scan(ui_call).flatten.each do |literal|
      next if literal.empty? || literal.match?(/^[a-z0-9_]+(?:\.[A-Za-z0-9_]+)+$/)
      next if literal == "🌯"
      next if literal.start_with?("\\(")
      if literal.include?("\\(")
        next unless literal.match?(/\b(?:Portion|serving|Mahlzeit|meal|Kalorie|calorie|Lebensmittel|food|Zutat|ingredient)\b/i)
      end
      next if literal.match?(%r{^[-+]?[%\d.,×/ ]*(?:kcal|g|ml|%)?$}i)
      next if literal.include?("\\(") && literal.gsub(/\\\([^)]*\)/, "").match?(%r{^[-+ ·×/%]*?(?:kcal|g|ml|%)?$}i)
      errors << "Hard-coded UI text: #{file.delete_prefix(root + '/')}:#{line_number}: \"#{literal}\""
    end
  end
end

# Dynamic String parameters are not treated as LocalizedStringKey by SwiftUI.
# Guard the food nutrient helpers that previously displayed keys such as
# `quick_entry.protein` even though the catalogue entry existed.
{
  "CreateFoodView.swift" => /private func nutrientField[\s\S]*?LabeledContent\(t\(title\)\)/,
  "EditFoodView.swift" => /private func nutrientField[\s\S]*?LabeledContent\(t\(title\)\)/
}.each do |name, pattern|
  content = File.read(File.join(root, "CalorieTrackerApp", name))
  errors << "Dynamic food labels are not resolved through LanguageStore in #{name}" unless content.match?(pattern)
end

widget_source.each do |file, content|
  content.each_line.with_index(1) do |line, line_number|
    next if line.lstrip.start_with?("//")
    line.scan(ui_call).flatten.each do |literal|
      next if literal.empty? || literal.start_with?("\\(")
      next if literal.match?(%r{^[-+]?[%\d.,×/ ]*(?:kcal|g|ml|%)?$}i)
      errors << "Hard-coded widget UI text: #{file.delete_prefix(root + '/')}:#{line_number}: \"#{literal}\""
    end
  end
end

if errors.empty?
  puts "Localization audit passed (#{english.length} app and #{widget_english.length} widget English/German keys)."
else
  warn errors.join("\n")
  exit 1
end
