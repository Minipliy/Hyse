require_relative "training_view_sources"
# Static regression checks for the EU-oriented content report flow.
root = File.expand_path("..", __dir__)
hook = File.read(File.join(root, "pb_hooks", "content_reports.pb.js"))
migration = File.read(File.join(root, "pb_migrations", "1788700700_content_reports.js"))
public_migration = File.read(File.join(root, "pb_migrations", "1791000600_public_content_reports.js"))
public_hook = File.read(File.join(root, "pb_hooks", "public_content_reports.pb.js"))
social = File.read(File.join(root, "CalorieTrackerApp", "TrainingSocialService.swift"))
views = TrainingViewSources.read
public_view = File.read(File.join(root, "CalorieTrackerApp", "PublicContentReportView.swift"))
settings = File.read(File.join(root, "CalorieTrackerApp", "SettingsView.swift"))

checks = {
  "closed report collection" => migration.include?("listRule: null") && migration.include?("updateRule: null"),
  "all report target types" => %w[user avatar community community_post workout workout_comment].all? { |value| hook.include?("\"#{value}\"") },
  "reason and substantiation validation" => hook.include?("details.length < 10") && hook.include?("goodFaith"),
  "rate limiting" => hook.include?("Daily report limit reached"),
  "own reports only" => hook.include?("reporter = {:reporter}"),
  "appeal endpoint" => hook.include?("/api/hyse/reports/:id/appeal") && hook.include?("status"),
  "client report service" => social.include?("actor ContentReportService") && social.include?("func appeal"),
  "community reporting" => views.include?("content_reports.report_community"),
  "profile and avatar reporting" => views.include?("content_reports.report_avatar") && views.include?("content_reports.report_profile"),
  "workout and comment reporting" => views.include?("content_reports.report_workout") && views.include?("content_reports.report_comment"),
  "report history in settings" => settings.include?("ContentReportsView()"),
  "guest report collection stays private" => public_migration.include?('name: "public_content_reports"') && public_migration.include?("createRule: null"),
  "guest route validates and limits submissions" => public_hook.include?('/api/hyse/reports/public') && public_hook.include?("details.length < 10") && public_hook.include?("recent.length >= 10") && !public_hook.include?("requireRecordAuth"),
  "short-lived guest rate key" => public_hook.include?("hyse_clear_public_report_rate_keys") && public_hook.include?('report.set("rate_key", "")'),
  "in-app guest report form" => public_view.include?("submitPublic") && public_view.include?("contactEmail") && settings.include?("PublicContentReportView()")
}

failed = checks.filter_map { |name, passed| name unless passed }
abort "Content reporting checks failed: #{failed.join(', ')}" unless failed.empty?
puts "Content reporting checks passed (#{checks.length})."
