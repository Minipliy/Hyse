#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
figure = File.read(File.join(root, "CalorieTrackerApp/DetailedTrainingMuscleFigure.swift"))
training = TrainingViewSources.read
statistics = File.read(File.join(root, "CalorieTrackerApp/TrainingStatisticsHub.swift"))
models = File.read(File.join(root, "CalorieTrackerApp/TrainingModels.swift"))
extractor = File.read(File.join(root, "scripts/extract_training_reference_overlays.py"))
asset = File.join(root, "CalorieTrackerApp/Assets.xcassets/TrainingAnatomyDetailed.imageset/training-anatomy.png")
silhouette_asset = File.join(root, "CalorieTrackerApp/Assets.xcassets/TrainingAnatomySilhouette.imageset/training-anatomy-silhouette.png")
reference_assets = %w[
  AnatomyNeutral Biceps Core BenchPress Chest PullUp Neck Row Lats UpperBack FacePull FrontShoulders RearShoulders Traps
  Triceps Forearms LowerBack Abductors Adductors Hamstrings BirdDog Glutes
  Quadriceps Calves
].map do |name|
  File.join(root, "CalorieTrackerApp/Assets.xcassets/TrainingReference#{name}.imageset/TrainingReference#{name}.png")
end

TRACKED_MUSCLE_CASES = {
  "chest" => "chest",
  "shoulders" => "shoulders",
  "front_shoulders" => "frontShoulders",
  "rear_shoulders" => "rearShoulders",
  "biceps" => "biceps",
  "triceps" => "triceps",
  "forearms" => "forearms",
  "abs" => "abs",
  "obliques" => "obliques",
  "hip_flexors" => "hipFlexors",
  "abductors" => "abductors",
  "quadriceps" => "quadriceps",
  "adductors" => "adductors",
  "neck" => "neck",
  "upper_back" => "upperBack",
  "lats" => "lats",
  "back" => "back",
  "glutes" => "glutes",
  "hamstrings" => "hamstrings",
  "calves" => "calves",
  "tibialis" => "tibialis"
}.freeze

HORIZONTAL_ROWS = %w[
  dumbbell_row barbell_row seated_cable_row band_row kettlebell_row
  tbar_supported_row supported_chest_row onearm_cable_row
  iso_lateral_high_row seated_machine_row
].freeze

def declaration_body(source, declaration, next_declaration: nil)
  start = source.index(declaration)
  return "" unless start

  tail = source[start..]
  if next_declaration && (finish = tail.index(next_declaration, declaration.length))
    tail[0...finish]
  else
    tail
  end
end

def switch_case_body(source, name)
  match = source.match(/case\s+\.#{Regexp.escape(name)}\s*:\s*(.*?)(?=\n\s*case\s+\.|\n\s*default\s*:|\n\s*}\s*$)/m)
  match&.[](1).to_s
end

def exercise_line(source, id)
  source.lines.find do |line|
    line.include?(%Q{.builtIn("#{id}"}) || line.include?(%Q{curated("#{id}"})
  end.to_s
end

def primary_muscles(source, id)
  line = exercise_line(source, id)
  match = if line.include?(%Q{.builtIn("#{id}"})
            line.match(/\.builtIn\("#{Regexp.escape(id)}".*?,\s*\.\w+\s*,\s*\.\w+\s*,\s*\[([^\]]*)\]/)
          else
            line.match(/curated\("#{Regexp.escape(id)}".*?,\s*\.\w+\s*,\s*\[([^\]]*)\]/)
          end
  return [] unless match

  match[1].scan(/"([^"]+)"/).flatten
end

anatomy_enum = declaration_body(
  figure,
  "enum TrainingAnatomicalMuscle",
  next_declaration: "struct AnatomicalMuscleMask"
)
mask_shape = declaration_body(
  figure,
  "struct AnatomicalMuscleMask",
  next_declaration: "struct DetailedTrainingMuscleBody"
)
body_component = declaration_body(figure, "struct DetailedTrainingMuscleBody")
weighting = declaration_body(
  figure,
  "static func weightedRegions(",
  next_declaration: "static func expandedCounts"
)
weighting_implementation = weighting.lines.drop(1).reject { |line| line.match?(/^\s*_\s*=\s*secondary\s*$/) }.join
calf_contours = switch_case_body(anatomy_enum, "calves")

row_muscles = primary_muscles(models, "seated_cable_row")
exact_example_regions = (
  primary_muscles(models, "leg_extension") +
  row_muscles +
  primary_muscles(models, "standing_calf_raise")
).uniq.sort
built_in_ids = models.scan(/\.builtIn\("([^"]+)"/).flatten
ambiguous_primary_limb_entries = built_in_ids.select do |id|
  !(primary_muscles(models, id) & %w[arms legs]).empty?
end

checks = {
  "detailed anatomy asset exists" => File.exist?(asset),
  "legacy silhouette source remains available" => File.exist?(silhouette_asset),
  "every supplied screenshot has a persistent blue reference asset" => reference_assets.all? { |asset_path| File.exist?(asset_path) },
  "shared detailed body component uses the copied neutral reference atlas" =>
    figure.include?('Image("TrainingReferenceAnatomyNeutral")'),
  "every tracked muscle is an independently addressable enum case" =>
    anatomy_enum.include?("CaseIterable") &&
    TRACKED_MUSCLE_CASES.all? do |raw_value, case_name|
      declaration = /\bcase\s+#{Regexp.escape(case_name)}\b(?:\s*=\s*"#{Regexp.escape(raw_value)}")?/
      anatomy_enum.match?(declaration)
    end,
  "the reference layer selector iterates over active muscle regions" =>
    figure.include?("TrainingAnatomicalMuscle.allCases") &&
      figure.include?("TrainingReferenceOverlay.layers(for: activeMuscles, regionCounts: regionCounts)") &&
      figure.include?("regionCounts[$0.rawValue"),
  "the visible body renderer does not fall back to contour geometry" =>
    !body_component.include?("AnatomicalMuscleMask") &&
      !body_component.include?("colorMultiply"),
  "the legacy Canvas silhouettes and flat color overlays are gone" =>
    !figure.include?("Canvas") &&
    !figure.include?("DetailedTrainingMuscleFigure: View") &&
    !figure.include?(".fill(tint)"),
  "active muscles compose copied reference pixels rather than redrawing blue masks" =>
    figure.include?("Image(layer.assetName)") &&
      !figure.include?(".colorMultiply(HyseColor.accent)") &&
      !figure.include?(".mask(AnatomicalMuscleMask"),
  "reference assets preserve the white fascia between blue muscle fibres" =>
    figure.include?("TrainingReferenceAnatomyNeutral") &&
      figure.include?("TrainingReferenceOverlay") &&
      !figure.include?("luminanceToAlpha()"),
  "reference extraction never makes neutral blue-grey shading opaque" =>
    extractor.include?("blue - green >= 22") &&
      extractor.include?("green - red >= 17") &&
      extractor.include?("chroma >= 45"),
  "front and rear shoulders use separate view-specific reference layers" =>
    figure.include?("case frontShoulders = \"FrontShoulders\"") &&
      figure.include?("case rearShoulders = \"RearShoulders\"") &&
      figure.include?(".frontShoulders: .frontShoulders") &&
      figure.include?(".rearShoulders: .rearShoulders") &&
      extractor.include?("FrontShoulders") && extractor.include?("RearShoulders"),
  "each activity region selects its own copied reference layer" =>
    !figure.include?("func color(_ muscles: [String])") &&
      figure.include?("let individual: [TrainingAnatomicalMuscle: Self]") &&
      figure.include?("TrainingReferenceOverlay.layers(for: activeMuscles, regionCounts: regionCounts)"),
  "secondary muscles never contribute to the body distribution" =>
    weighting.include?("primary.flatMap") &&
    !weighting_implementation.match?(/\bsecondary\b/) &&
    !weighting.match?(/\b0\.5\b/),
  "generic arm and leg tags do not fan out into unrelated muscles" =>
    !figure.include?('return ["biceps", "triceps", "forearms"]') &&
    !figure.include?('return ["quadriceps", "hamstrings", "glutes", "calves"]'),
  "built-in exercises avoid ambiguous primary arm and leg tags" =>
    ambiguous_primary_limb_entries.empty?,
  "the requested exercise muscles map to one matching anatomical region each" =>
    %w[biceps quadriceps upper_back lats calves].all? do |muscle|
      figure.match?(/case\s+[^\n:]*"#{Regexp.escape(muscle)}"[^\n:]*:\s*return\s*\["#{Regexp.escape(muscle)}"\]/)
    end,
  "biceps curl colors only biceps even though forearms are support muscles" =>
    primary_muscles(models, "biceps_curl") == ["biceps"] &&
    exercise_line(models, "biceps_curl").include?('["forearms"]'),
  "leg extension row and calf raise produce exactly the requested regions" =>
    exact_example_regions == %w[calves lats quadriceps upper_back],
  "leg press overrides stale imported hamstring metadata everywhere" =>
    models.include?("static func canonicalMuscleAssignment") &&
      models.include?("static func repairedMuscleAssignment") &&
      models.include?("sourceName.contains(\"beinpresse\")") &&
      models.include?("primary: [\"quadriceps\", \"glutes\"]") &&
      training.include?("TrainingExercise.repairedMuscleAssignment") &&
      statistics.include?("TrainingExercise.repairedMuscleAssignment"),
  "seated machine rows repair stale imports to include upper back" =>
    models.include?("curated(\"seated_machine_row\"") &&
      models.include?("\"Rudern sitzend an der Maschine\"") &&
      models.include?("[\"upper_back\", \"lats\"]") &&
      models.include?("snapshot.normalizedImportedCatalogEntry()"),
  "combined exercises compose every active reference layer instead of replacing one" =>
    figure.include?("Every active muscle contributes its own transparent reference") &&
      figure.include?(".lats: .lats") &&
      figure.include?(".upperBack: .upperBack") &&
      figure.include?(".hamstrings: .hamstrings") &&
      figure.include?(".glutes: .glutes") &&
      !figure.include?("if active.count <= 4, active.contains(.lats) { return [.pullUp] }"),
  "direct biceps activation renders above the lat pulldown assist highlight" =>
    figure.include?("Biceps Curl over Lat Pulldown's light-blue biceps") &&
      figure.include?("return lhs.drawPriority < rhs.drawPriority"),
  "stronger overlapping muscle activity renders above a lighter assist highlight" =>
      figure.include?("Lat Pulldown + Row keeps the") &&
      figure.include?("if leftStrength != rightStrength { return leftStrength < rightStrength }") &&
      figure.include?("regionCounts[muscle.rawValue, default: 0]") &&
      figure.include?("case .benchPress, .row, .birdDog:") &&
      figure.include?("case .pullUp, .facePull, .frontShoulders, .rearShoulders, .hamstrings:"),
  "latissimus and upper back have non-overlapping reference exports" =>
    extractor.include?("write_imageset(\"Lats\", isolate_box") &&
      extractor.include?("write_imageset(\"UpperBack\", isolate_box") &&
      figure.include?(".lats: .lats") && figure.include?(".upperBack: .upperBack"),
  "primary-only muscle layers exclude screenshot assistance muscles" =>
    extractor.include?("write_imageset(\"Chest\", isolate_box") &&
      extractor.include?("write_imageset(\"Glutes\", isolate_box") &&
      extractor.include?("write_imageset(\"Hamstrings\", isolate_box") &&
      figure.include?(".chest: .chest") && figure.include?(".glutes: .glutes"),
  "horizontal rows target lats and upper back rather than lower back" =>
    HORIZONTAL_ROWS.all? { |id| primary_muscles(models, id).sort == %w[lats upper_back] },
  "calves use their copied reference layer" =>
    figure.include?("case calves = \"Calves\"") &&
      File.exist?(File.join(root, "CalorieTrackerApp/Assets.xcassets/TrainingReferenceCalves.imageset/TrainingReferenceCalves.png")),
  "primary-only mapping is shared by active and historical statistics" =>
    training.include?("TrainingMuscleRegionMap.weightedRegions") &&
    statistics.include?("TrainingMuscleRegionMap.weightedRegions"),
  "active workout header shows the detailed body" =>
    training.include?("DetailedTrainingMuscleBody(counts: muscleCounts)"),
  "statistics use the shared detailed body" =>
    statistics.include?("DetailedTrainingMuscleBody(counts: counts)"),
  "body distribution retains completed-set rows" =>
    statistics.include?("TrainingMuscleBodyGraphic(counts: Dictionary(uniqueKeysWithValues: counts))")
}

failures = checks.reject { |_, passed| passed }.keys
abort("Detailed training muscle body checks failed:\n- #{failures.join("\n- ")}") unless failures.empty?

puts "Detailed training muscle body checks passed."
