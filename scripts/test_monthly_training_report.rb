#!/usr/bin/env ruby
require_relative "training_view_sources"

root = File.expand_path("..", __dir__)
report = File.read(File.join(root, "CalorieTrackerApp", "MonthlyTrainingReport.swift"))
training = TrainingViewSources.read
hub = File.read(File.join(root, "CalorieTrackerApp", "TrainingStatisticsHub.swift"))
settings = File.read(File.join(root, "CalorieTrackerApp", "SettingsView.swift"))
user_settings = File.read(File.join(root, "CalorieTrackerApp", "UserSettingsStore.swift"))

%w[workouts duration volume sets].each do |metric|
  abort("missing monthly metric: #{metric}") unless report.match?(/case[^\n]*\b#{metric}\b/)
end

abort("monthly report must compare with the previous month") unless report.include?("value: -1, to: reportMonth")
abort("monthly report needs a twelve-month chart") unless report.include?("monthlySummaries(endingAt: latestAvailableMonth, count: 12)")
abort("monthly report is not reachable from the training profile") unless hub.include?("TrainingMonthlyReportView(store: store")
abort("new report marker is not persisted") unless training.include?("lastViewedMonthlyTrainingReport_v1")
abort("monthly notification is not scheduled for day one") unless report.include?("components.day = 1")
abort("monthly notification does not repeat") unless report.include?("repeats: true")
abort("monthly notification preference is missing") unless settings.include?("monthlyTrainingReportNotificationsEnabled") && user_settings.include?("monthlyTrainingReportNotificationsEnabled_v1")
abort("monthly report share must render an image") unless report.include?("ImageRenderer(content: card)") && report.include?("DataRepresentation(exportedContentType: .png)")
abort("monthly report image must only render after tapping share") unless report.include?("Button(action: prepareAndPresentShareImage)") && !report.include?(".task(id: shareRenderID)")
abort("monthly report must share the rendered image instead of plain text") unless report.include?("MonthlyReportShareSheet(item: renderedShareImage)") && !report.include?("ShareLink(item: shareText)")
abort("monthly report share image is missing HYSE branding") unless report.include?('Text("HYSE")') && report.include?("MonthlyReportShareCard")
abort("monthly report share image is missing the Hyse URL") unless report.include?('Text("https://hyse.minipliy.net")')
abort("monthly report share comparisons do not use numeric red/green states") unless report.include?("comparisonColor(deltaValue)") && report.include?("value > 0 ? HyseColor.success : value < 0 ? Color.red")
abort("unchanged monthly values must stay neutral") unless report.include?("Color.white.opacity(0.56)")

puts "monthly training report checks passed"
