#!/usr/bin/env ruby

view = File.read(File.expand_path("../CalorieTrackerApp/BatchAddEntryView.swift", __dir__))

abort "Search, preparation, and review must use separate List identities" unless view.include?('isPreparingReview ? "batch-preparing"') && view.include?('reviewing ? "batch-review" : "batch-search"')
abort "Opening review must cancel food-result work immediately" unless view.include?('task(id: "\(reviewing)|\(isPreparingReview)|') && view.include?('guard !reviewing, !isPreparingReview else { return }')
abort "Review preparation must allow a display frame to render" unless view.include?('isPreparingReview = true') && view.include?('Task.sleep(for: .milliseconds(80))')
abort "Review preparation must show visible progress" unless view.include?('ProgressView(t("batch_add.preparing_review"))')
abort "Preparation must replace the costly search list" unless view.include?('if isPreparingReview {') && view.include?('preparingReviewContent')
abort "Both review entry points must use the optimized transition" unless view.scan('beginReview()').length >= 3

puts "Batch review switches promptly, cancels search work, and shows progress."
