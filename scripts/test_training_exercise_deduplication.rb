#!/usr/bin/env ruby

models = File.read(File.expand_path("../CalorieTrackerApp/TrainingModels.swift", __dir__))
store = File.read(File.expand_path("../CalorieTrackerApp/TrainingStore.swift", __dir__))
sync = File.read(File.expand_path("../CalorieTrackerApp/TrainingSyncService.swift", __dir__))
insights = File.read(File.expand_path("../CalorieTrackerApp/TrainingInsightsViews.swift", __dir__))

abort "Clavicular Fly must be retired" unless models.include?('e6fd2462-282c-53ab-b7eb-ca1661367f79')
abort "Imported exercise duplicates need a central retirement list" unless models.include?('retiredImportedExerciseIDs')
abort "Cached duplicates must be hidden from the catalog" unless store.include?('.filter { $0.isCustom && !TrainingExercise.isRetiredImported($0) }')
abort "Remote duplicates must not return after sync" unless sync.scan('!TrainingExercise.isRetiredImported($0)').length >= 2
abort "Retired exercises must not be uploaded again" unless store.match?(/let custom = self\.exercises\s+\.filter \{ \$0\.isCustom && !TrainingExercise\.isRetiredImported\(\$0\) \}/)
abort "Surviving imports need bilingual catalog metadata" unless models.include?('normalizedImportedCatalogEntry()')
abort "Imported Smith bench press needs a dedicated key" unless models.include?('smith_flat_bench_press')
abort "Cable biceps curl needs the requested German name" unless models.include?('"Bizepscurl am Kabelturm"')
abort "Imported exercises must be allowed to use local specific images" unless insights.include?('if UIImage(named: exerciseSpecificAsset) != nil')
abort "Compatible variants need local image fallbacks" unless insights.include?('compatibleLocalAssets')
abort "Machine glute kickback must be retired" unless models.include?('b291ac74-27ea-50cb-8a09-5fbbf1226b11')
abort "Cable glute kickback must be a built-in exercise" unless models.include?('.builtIn("cable_glute_kickback"')
abort "Both obsolete wrist curls must be retired" unless %w[8f2b623c-b12a-56c9-80bd-46547ee4c9ab 7bd7751e-c253-54f7-9c6d-bf8d638ec8d9].all? { models.include?(_1) }
abort "Only the unspecified knee raise must be retired" unless models.include?('22a68331-8169-526d-aea2-fea6cb306cf3') && models.include?('captains_chair_knee_raise')
abort "Kneeling band pulldown must be retired" unless models.include?('f829f3cb-3f37-5526-8c2e-2325df6df368')
abort "New forearm exercises are missing" unless %w[reverse_barbell_curl zottman_curl wrist_roller].all? { models.include?(_1) }
abort "Seated machine shoulder-press duplicate must be retired by name" unless models.include?('schulterpresse sitzend (maschine)')
abort "Cable lateral raise needs the corrected movement identity" unless models.include?('single_arm_cable_lateral_raise')

puts "Imported duplicate exercises are retired without deleting workout history."
